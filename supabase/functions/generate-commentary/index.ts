// Turns a detected stroke timeline into ball-by-ball COACH commentary (Gemini) for ONE analysis
// version (run). Grounded strictly in what pose estimation measured — no invented placement,
// footwork, outcomes or numbers. Called by the Modal deep worker (shared-secret).
// Writes analysis_commentary for the run, finalises the run, and notifies the uploader.
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

function fmtClock(s: number) { const m = Math.floor(s / 60), x = Math.floor(s % 60); return `${m}:${String(x).padStart(2, '0')}` }

// Parse Gemini output into an array of lines, tolerating a bare array, a wrapped object, or one object.
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
  let video_id = '', run_id: string | null = null
  const supa = createClient(SUPA_URL, SERVICE)
  try {
    const body = await req.json()
    const given = req.headers.get('x-analyze-secret') || body.secret || ''
    if (!SECRET || given !== SECRET) return json({ error: 'forbidden' }, 403)
    video_id = body.video_id
    if (!video_id) return json({ error: 'missing video_id' }, 400)

    run_id = body.run_id || null
    if (!run_id) {
      const { data: r } = await supa.from('analysis_runs').select('id').eq('video_id', video_id).eq('kind', 'deep')
        .order('version', { ascending: false }).limit(1).maybeSingle()
      run_id = r?.id ?? null
    }

    const { data: tags } = await supa.from('video_player_tags').select('id, player_id, label, is_subject').eq('video_id', video_id)
    let q = supa.from('analysis_shots').select('id, tag_id, t_s, shot_type, confidence, technique').eq('video_id', video_id)
    q = run_id ? q.eq('run_id', run_id) : q.is('run_id', null)
    const { data: shots } = await q.order('t_s')

    const nameByTag: Record<string, string> = {}
    for (const t of tags ?? []) {
      let name = t.label || 'Player'
      if (t.player_id) {
        const { data: p } = await supa.from('players').select('display_name').eq('id', t.player_id).maybeSingle()
        if (p?.display_name) name = p.display_name
      }
      const first = String(name).trim().split(/\s+/)[0] || 'Player'   // coach addresses players by first name
      nameByTag[t.id] = first.charAt(0).toUpperCase() + first.slice(1)
    }

    const subjIds = new Set((tags ?? []).filter((t: any) => t.is_subject).map((t: any) => t.id))
    const allShots = (shots ?? []).filter((s: any) => subjIds.has(s.tag_id)).slice(0, 60)

    // Honest "nothing to say" result — e.g. a warm-up clip with no real strokes.
    if (!allShots.length) {
      await supa.rpc('finalize_deep', { p_video_id: video_id, p_run_id: run_id })
      return json({ ok: true, lines: 0, note: 'no strokes detected' })
    }

    const tagOfShot: Record<string, string> = {}
    const tOfShot: Record<string, number> = {}
    for (const s of allShots) { tagOfShot[s.id] = s.tag_id; tOfShot[s.id] = Number(s.t_s) }

    const ordered = [...allShots].sort((a: any, b: any) => a.t_s - b.t_s)
    const shotList = ordered.map((s: any, i: number) => {
      const tech = s.technique || {}
      const prev = i > 0 ? ordered[i - 1] : null
      return {
        shot_id: s.id, player: nameByTag[s.tag_id], time: fmtClock(Number(s.t_s)),
        stroke_height: tech.height || s.shot_type, swing: tech.swing, pace: tech.pace,
        elbow_above_shoulder: tech.elbow_up,
        after_previous_stroke_s: prev ? Math.round((Number(s.t_s) - Number(prev.t_s)) * 10) / 10 : null,
      }
    })

    const sys =
      `You are an experienced badminton coach giving short ball-by-ball feedback, like a cricket commentator ` +
      `crossed with a personal coach. You can ONLY see these pose-estimation measurements per stroke (there is NO ` +
      `shuttle tracking): stroke_height (overhead = racket hand above the shoulder, mid, low = below the hip), swing ` +
      `direction, pace, whether the elbow was above the shoulder at the peak, and the time since the previous stroke.\n` +
      `Write EXACTLY ONE line per stroke, max 25 words, starting with the time, addressing the player by name, using ` +
      `"looks like" language. Base the cue ONLY on the measurements:\n` +
      `- overhead: early preparation, side-on, contact high and in front; if elbow_above_shoulder is false, tell them to lift the elbow.\n` +
      `- low: get low early with a long lunge, racket up and ready, lift high and deep or play tight to the net.\n` +
      `- mid / drive: compact swing, racket in front of the body, reset quickly for the next shot.\n` +
      `Phrase every cue as ADVICE ("prepare early and turn side-on"), never as praise or a description of something ` +
      `you did not measure (do NOT write "good side-on preparation"). The only things you may praise are an elbow ` +
      `above the shoulder on an overhead, or a fast pace.\n` +
      `NEVER mention footwork recovery, base position, where the shuttle went, whether the rally was won or lost, ` +
      `the opponent's intent, or any numbers/speeds. Do not repeat the same sentence — vary the wording.\n` +
      `severity: "watch" when the line is a correction, "good" only for a fast overhead with the elbow up, otherwise "info".\n` +
      `Output STRICT JSON: an array of {"shot_id":"<id>","text":"<line>","severity":"good|info|watch"}, one per stroke.\n` +
      `Strokes:\n${JSON.stringify(shotList)}`

    let text = '[]', finish = ''
    for (let attempt = 0; attempt < 3; attempt++) {
      try {
        const resp = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent?key=${GEMINI}`, {
          method: 'POST', headers: { 'content-type': 'application/json' },
          body: JSON.stringify({
            contents: [{ role: 'user', parts: [{ text: sys }] }],
            generationConfig: { temperature: 0.6, maxOutputTokens: 8192, responseMimeType: 'application/json' },
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
    const rows = lines.map((ln: any, i: number) => {
      if (!ln || !ln.text) return null
      const sid = (ln.shot_id && tagOfShot[ln.shot_id]) ? ln.shot_id : (ordered[i]?.id || null)
      if (!sid) return null
      return {
        video_id, run_id, tag_id: tagOfShot[sid], shot_id: sid, t_s: tOfShot[sid], lens: 'coach',
        text: String(ln.text).slice(0, 500),
        severity: ['good', 'info', 'watch', 'warning'].includes(ln.severity) ? ln.severity : 'info',
      }
    }).filter(Boolean)

    if (!rows.length && finish.startsWith('ERR')) {
      await supa.rpc('fail_deep', { p_video_id: video_id, p_error: 'AI commentary is busy right now — please try again in a few minutes.', p_run_id: run_id })
      return json({ ok: false, reason: 'rate_limited', finish })
    }

    if (run_id) await supa.from('analysis_commentary').delete().eq('run_id', run_id)   // idempotent retry of THIS version only
    if (rows.length) await supa.from('analysis_commentary').insert(rows)
    await supa.rpc('finalize_deep', { p_video_id: video_id, p_run_id: run_id })

    try {
      await fetch(`${SUPA_URL}/functions/v1/notify-analysis`, {
        method: 'POST',
        headers: { 'content-type': 'application/json', 'apikey': SERVICE, 'Authorization': `Bearer ${SERVICE}`, 'x-analyze-secret': SECRET },
        body: JSON.stringify({ video_id, secret: SECRET }),
      })
    } catch { /* ignore */ }

    return json({ ok: true, lines: rows.length, shots: allShots.length, finish })
  } catch (e) {
    try { if (video_id) await supa.rpc('fail_deep', { p_video_id: video_id, p_error: String(e), p_run_id: run_id }) } catch { /* ignore */ }
    return json({ error: String((e as Error)?.message ?? e) }, 500)
  }
})
