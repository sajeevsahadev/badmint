// Turns a detected shot timeline into ball-by-ball COACH commentary (Gemini), grounded strictly in
// the detected facts. Called by the Modal deep worker (shared-secret) after it writes analysis_shots.
// Writes analysis_commentary, marks deep_status done, and notifies the uploader.
//
// Secrets: GEMINI_API_KEY, ANALYZE_SHARED_SECRET, SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY (auto).
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4'

const SUPA_URL = Deno.env.get('SUPABASE_URL') ?? ''
const SERVICE  = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
const GEMINI   = Deno.env.get('GEMINI_API_KEY') ?? ''
const SECRET   = Deno.env.get('ANALYZE_SHARED_SECRET') ?? ''
const MODEL    = 'gemini-3.6-flash'

const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type, apikey, x-analyze-secret' }
const json = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { ...CORS, 'content-type': 'application/json' } })

function fmtClock(s: number) { const m = Math.floor(s / 60), x = Math.round(s % 60); return `${m}:${String(x).padStart(2, '0')}` }

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })
  try {
    const body = await req.json()
    const given = req.headers.get('x-analyze-secret') || body.secret || ''
    if (!SECRET || given !== SECRET) return json({ error: 'forbidden' }, 403)
    const video_id = body.video_id
    if (!video_id) return json({ error: 'missing video_id' }, 400)

    const supa = createClient(SUPA_URL, SERVICE)
    const { data: vid } = await supa.from('match_videos').select('game_type, title').eq('id', video_id).maybeSingle()
    const { data: tags } = await supa.from('video_player_tags').select('id, player_id, label, is_subject, court_side').eq('video_id', video_id)
    const { data: shots } = await supa.from('analysis_shots').select('id, tag_id, t_s, shot_type, confidence, technique').eq('video_id', video_id).order('t_s')

    // resolve names
    const nameByTag: Record<string, string> = {}
    for (const t of tags ?? []) {
      let name = t.label || 'Player'
      if (t.player_id) {
        const { data: p } = await supa.from('players').select('display_name').eq('id', t.player_id).maybeSingle()
        if (p?.display_name) name = p.display_name
      }
      nameByTag[t.id] = name
    }

    const subjects = (tags ?? []).filter((t: any) => t.is_subject)
    const rowsToInsert: any[] = []

    for (const subj of subjects) {
      const myShots = (shots ?? []).filter((s: any) => s.tag_id === subj.id)
      if (!myShots.length) continue
      const name = nameByTag[subj.id]
      const shotList = myShots.map((s: any) => ({
        shot_id: s.id, time: fmtClock(Number(s.t_s)), t_s: Number(s.t_s),
        type: s.shot_type || 'unknown', confidence: s.confidence, technique: s.technique || {},
      }))

      const sys =
        `You are an expert badminton coach giving BALL-BY-BALL commentary on ${name}'s shots, like a cricket ` +
        `commentator crossed with a personal coach. For EACH shot in the JSON, write ONE short, specific, ` +
        `encouraging-but-honest coaching line (max ~30 words) that references what actually happened and gives ` +
        `a concrete correction when the technique flags show a fault (e.g. elbow dropped, contact behind the body, ` +
        `no recovery to base). Use the shot time in your line. Do NOT invent shuttle placement or opponent actions ` +
        `that are not in the data. If a shot type confidence is low, hedge ("looked like a clear"). ` +
        `Output STRICT JSON: an array of {"shot_id": "<id>", "text": "<line>", "severity": "good|info|watch|warning"}. ` +
        `Severity: good = well executed, watch = minor fix, warning = clear fault. Shots:\n${JSON.stringify(shotList)}`

      const resp = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent?key=${GEMINI}`, {
        method: 'POST', headers: { 'content-type': 'application/json' },
        body: JSON.stringify({
          contents: [{ role: 'user', parts: [{ text: sys }] }],
          generationConfig: { temperature: 0.5, maxOutputTokens: 4096, responseMimeType: 'application/json' },
        }),
      })
      const out = await resp.json()
      let text = out?.candidates?.[0]?.content?.parts?.[0]?.text ?? '[]'
      let lines: any[] = []
      try { lines = JSON.parse(text) } catch { try { lines = JSON.parse(text.slice(text.indexOf('['), text.lastIndexOf(']') + 1)) } catch { lines = [] } }

      const tById: Record<string, number> = {}
      for (const s of myShots) tById[s.id] = Number(s.t_s)
      for (const ln of lines) {
        const sid = ln.shot_id && tById[ln.shot_id] !== undefined ? ln.shot_id : null
        rowsToInsert.push({
          video_id, tag_id: subj.id, shot_id: sid,
          t_s: sid ? tById[sid] : 0, lens: 'coach',
          text: String(ln.text || '').slice(0, 500),
          severity: ['good', 'info', 'watch', 'warning'].includes(ln.severity) ? ln.severity : 'info',
        })
      }
    }

    // Replace any prior commentary for this video, then insert fresh.
    await supa.from('analysis_commentary').delete().eq('video_id', video_id)
    if (rowsToInsert.length) await supa.from('analysis_commentary').insert(rowsToInsert)

    await supa.rpc('finalize_deep', { p_video_id: video_id })

    // Notify (reuse the analysis push).
    try {
      await fetch(`${SUPA_URL}/functions/v1/notify-analysis`, {
        method: 'POST',
        headers: { 'content-type': 'application/json', 'apikey': SERVICE, 'Authorization': `Bearer ${SERVICE}`, 'x-analyze-secret': SECRET },
        body: JSON.stringify({ video_id, secret: SECRET }),
      })
    } catch { /* ignore */ }

    return json({ ok: true, lines: rowsToInsert.length })
  } catch (e) {
    try {
      const supa = createClient(SUPA_URL, SERVICE)
      const b = await req.clone().json().catch(() => ({}))
      if (b?.video_id) await supa.rpc('fail_deep', { p_video_id: b.video_id, p_error: String(e) })
    } catch { /* ignore */ }
    return json({ error: String((e as Error)?.message ?? e) }, 500)
  }
})
