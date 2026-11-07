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

// Parse Gemini output into an array of lines, tolerating a bare array, a wrapped object
// ({commentary:[...]}), or a single object.
function toLines(raw: string): any[] {
  let v: any = null
  try { v = JSON.parse(raw) } catch { try { v = JSON.parse(raw.slice(raw.indexOf('['), raw.lastIndexOf(']') + 1)) } catch { v = null } }
  if (!v) return []
  if (Array.isArray(v)) return v
  if (typeof v === 'object') {
    for (const k of Object.keys(v)) if (Array.isArray(v[k])) return v[k]
    if (v.text) return [v]
  }
  return []
}

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
    const subjIds = new Set(subjects.map((t: any) => t.id))
    // ALL players' shots in ONE Gemini call per analysis (free tier = 20 req/day, so minimise calls).
    const allShots = (shots ?? []).filter((s: any) => subjIds.has(s.tag_id)).slice(0, 50)
    const tagOfShot: Record<string, string> = {}
    const tOfShot: Record<string, number> = {}
    for (const s of allShots) { tagOfShot[s.id] = s.tag_id; tOfShot[s.id] = Number(s.t_s) }

    let rowsToInsert: any[] = []
    let debug: any = { shots: allShots.length }

    if (allShots.length) {
      const shotList = allShots.map((s: any) => ({
        shot_id: s.id, player: nameByTag[s.tag_id], time: fmtClock(Number(s.t_s)),
        type: s.shot_type || 'unknown', confidence: s.confidence, technique: s.technique || {},
      }))
      const sys =
        `You are an expert badminton coach giving BALL-BY-BALL commentary, like a cricket commentator crossed ` +
        `with a personal coach. The JSON lists shots by one or more players (field "player"). For EACH shot, ` +
        `write ONE short, specific, honest coaching line (max ~28 words) addressed to that player by name, ` +
        `referencing what happened and giving a concrete correction when a technique flag shows a fault ` +
        `(elbow dropped, contact behind the body, no recovery to base). Use the shot time in the line. Do NOT ` +
        `invent shuttle placement or opponent actions not in the data; hedge low-confidence shot types. ` +
        `Output STRICT JSON: an array of {"shot_id":"<id>","text":"<line>","severity":"good|info|watch|warning"}, ` +
        `exactly one per shot. Shots:\n${JSON.stringify(shotList)}`

      let text = '[]'
      let finish = ''
      for (let attempt = 0; attempt < 3; attempt++) {
        try {
          const resp = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent?key=${GEMINI}`, {
            method: 'POST', headers: { 'content-type': 'application/json' },
            body: JSON.stringify({
              contents: [{ role: 'user', parts: [{ text: sys }] }],
              generationConfig: { temperature: 0.5, maxOutputTokens: 8192, responseMimeType: 'application/json' },
            }),
          })
          const out = await resp.json()
          finish = out?.candidates?.[0]?.finishReason ?? (out?.error?.message ? 'ERR:' + out.error.message : 'none')
          text = out?.candidates?.[0]?.content?.parts?.[0]?.text ?? '[]'
          if (!finish.startsWith('ERR') && !finish.startsWith('EXC')) break
        } catch (e) { finish = 'EXC:' + String(e) }
        await new Promise((r) => setTimeout(r, 2000 * (attempt + 1)))
      }

      const lines = toLines(text)
      debug = { shots: allShots.length, finish, rawLen: text.length, parsed: lines.length }
      rowsToInsert = lines.map((ln: any, i: number) => {
        if (!ln || !ln.text) return null
        const sid = (ln.shot_id && tagOfShot[ln.shot_id]) ? ln.shot_id : (allShots[i]?.id || null)
        const tag = sid ? tagOfShot[sid] : (subjects[0]?.id || null)
        return {
          video_id, tag_id: tag, shot_id: sid, t_s: sid ? tOfShot[sid] : 0, lens: 'coach',
          text: String(ln.text).slice(0, 500),
          severity: ['good', 'info', 'watch', 'warning'].includes(ln.severity) ? ln.severity : 'info',
        }
      }).filter(Boolean)
    }

    // If we got nothing because the AI was rate-limited/errored, mark it failed (clear retry signal)
    // rather than finalising an empty "done".
    if (!rowsToInsert.length && String(debug?.finish || '').startsWith('ERR')) {
      await supa.rpc('fail_deep', { p_video_id: video_id, p_error: 'AI commentary is busy right now — please try again in a few minutes.' })
      return json({ ok: false, reason: 'rate_limited', debug })
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

    return json({ ok: true, lines: rowsToInsert.length, debug })
  } catch (e) {
    try {
      const supa = createClient(SUPA_URL, SERVICE)
      const b = await req.clone().json().catch(() => ({}))
      if (b?.video_id) await supa.rpc('fail_deep', { p_video_id: b.video_id, p_error: String(e) })
    } catch { /* ignore */ }
    return json({ error: String((e as Error)?.message ?? e) }, 500)
  }
})
