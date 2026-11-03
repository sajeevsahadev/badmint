// Grounded performance chat. Given a video + subject tag + a question, it answers ONLY from that
// player's computed metrics and 3-lens report — never invented numbers. Writes the user and
// assistant turns into analysis_chat_threads / analysis_chat_messages and returns the reply.
//
// Secrets: GEMINI_API_KEY (shared), SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY (auto-injected).
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4'

const SUPA_URL = Deno.env.get('SUPABASE_URL') ?? ''
const SERVICE  = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
const GEMINI   = Deno.env.get('GEMINI_API_KEY') ?? ''
const MODEL    = 'gemini-3.6-flash'

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type, apikey, x-client-info',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}
const json = (o: unknown, status = 200) =>
  new Response(JSON.stringify(o), { status, headers: { ...CORS, 'content-type': 'application/json' } })

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })
  try {
    if (!GEMINI) return json({ error: 'Assistant is not configured yet.' }, 503)
    const jwt = (req.headers.get('Authorization') ?? '').replace('Bearer ', '')
    if (!jwt) return json({ error: 'unauthorized' }, 401)

    const supa = createClient(SUPA_URL, SERVICE)
    const { data: u } = await supa.auth.getUser(jwt)
    if (!u?.user) return json({ error: 'unauthorized' }, 401)
    const userId = u.user.id

    const { video_id, tag_id, thread_id, message } = await req.json()
    if (!video_id || !tag_id || !message) return json({ error: 'bad request' }, 400)

    // Access check: member of the video's club, uploader, or app admin.
    const { data: vid } = await supa.from('match_videos')
      .select('club_id, uploaded_by, game_type, title').eq('id', video_id).maybeSingle()
    if (!vid) return json({ error: 'not found' }, 404)
    let ok = vid.uploaded_by === userId
    if (!ok) {
      const { data: mem } = await supa.from('club_members')
        .select('user_id').eq('club_id', vid.club_id).eq('user_id', userId).maybeSingle()
      ok = !!mem
    }
    if (!ok) {
      const { data: adm } = await supa.from('app_roles')
        .select('role').eq('user_id', userId).eq('role', 'app_admin').maybeSingle()
      ok = !!adm
    }
    if (!ok) return json({ error: 'forbidden' }, 403)

    // Pull this player's grounding data.
    const [{ data: metricRow }, { data: reportRows }, { data: tagRow }] = await Promise.all([
      supa.from('player_metrics').select('metrics, confidence, is_mock').eq('video_id', video_id).eq('tag_id', tag_id).maybeSingle(),
      supa.from('analysis_reports').select('lens, content').eq('video_id', video_id).eq('tag_id', tag_id),
      supa.from('video_player_tags').select('label, player_id, court_side').eq('id', tag_id).maybeSingle(),
    ])

    let name = tagRow?.label || 'the player'
    if (tagRow?.player_id) {
      const { data: p } = await supa.from('players').select('display_name').eq('id', tagRow.player_id).maybeSingle()
      if (p?.display_name) name = p.display_name
    }

    const grounding = {
      match: { title: vid.title, type: vid.game_type },
      player: name,
      metrics: metricRow?.metrics ?? {},
      confidence: metricRow?.confidence ?? {},
      is_sample_data: !!metricRow?.is_mock,
      reports: Object.fromEntries((reportRows ?? []).map((r: any) => [r.lens, r.content])),
    }

    // Ensure a thread.
    let tid = thread_id
    if (!tid) {
      const { data: t, error: te } = await supa.from('analysis_chat_threads')
        .insert({ video_id, tag_id, user_id: userId }).select('id').single()
      if (te) throw te
      tid = t.id
    }
    await supa.from('analysis_chat_messages').insert({ thread_id: tid, role: 'user', content: message })

    // Recent history for context.
    const { data: hist } = await supa.from('analysis_chat_messages')
      .select('role, content').eq('thread_id', tid).order('created_at', { ascending: true }).limit(12)

    const sys =
      `You are a supportive, practical badminton coach assistant for the app Badminton 360. ` +
      `Answer ONLY using the player's analysis JSON provided. Do not invent statistics, scores or events ` +
      `that are not in the data; if asked about something not measured, say you don't have that detail yet. ` +
      `Be concise (2-5 sentences), encouraging and specific, and suggest a drill when relevant. ` +
      `For injury/physio questions, give general movement guidance and remind them it is not medical advice. ` +
      (grounding.is_sample_data ? `Note: this analysis is SAMPLE data for testing; say so if the user relies on exact numbers. ` : ``) +
      `Player's analysis JSON:\n${JSON.stringify(grounding)}`

    const contents = [
      { role: 'user', parts: [{ text: sys }] },
      { role: 'model', parts: [{ text: `Understood. I'll help ${name} using only their analysis.` }] },
      ...(hist ?? []).map((h: any) => ({ role: h.role === 'assistant' ? 'model' : 'user', parts: [{ text: h.content }] })),
    ]

    const resp = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent?key=${GEMINI}`,
      { method: 'POST', headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ contents, generationConfig: { temperature: 0.4, maxOutputTokens: 400 } }) },
    )
    const out = await resp.json()
    const reply = out?.candidates?.[0]?.content?.parts?.[0]?.text?.trim()
      || "I couldn't generate a reply just now — please try again."

    await supa.from('analysis_chat_messages').insert({ thread_id: tid, role: 'assistant', content: reply })
    return json({ thread_id: tid, reply })
  } catch (e) {
    return json({ error: String((e as Error)?.message ?? e) }, 500)
  }
})
