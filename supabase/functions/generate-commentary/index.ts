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

// Pull every complete {...} line out of a reply that was cut off mid-array.
function salvage(raw: string): any[] {
  const out: any[] = []
  for (const m of raw.match(/\{[^{}]*"text"[^{}]*\}/g) || []) { try { out.push(JSON.parse(m)) } catch { /* skip */ } }
  return out
}

// ── Head Coach Summary ───────────────────────────────────────────────────────────────────────────
// KPIs are COUNTED from what the pose engine measured per stroke; nothing here is estimated by the AI.
// Placement, errors and shots out need shuttle tracking, so they are reported as not-yet-measured (null).
const sumUsage = { input_tokens: 0, output_tokens: 0, thinking_tokens: 0, calls: 0 }

function pct(n: number, d: number) { return d ? Math.round((n / d) * 100) : null }

export function computeKpis(shots: any[], motion: any) {
  const T = (s: any) => s.technique || {}
  const H = (s: any) => T(s).height || s.shot_type
  const over = shots.filter(s => H(s) === 'overhead')
  const low  = shots.filter(s => H(s) === 'low')
  const mid  = shots.filter(s => H(s) !== 'overhead' && H(s) !== 'low')
  const fw   = shots.filter(s => typeof T(s).off_base === 'boolean')           // strokes with footwork data
  const off  = fw.filter(s => T(s).off_base)
  const rec  = off.filter(s => T(s).recovered)
  const late = off.filter(s => T(s).late_recovery)
  const recTimes = rec.map(s => Number(T(s).recovery_s)).filter(v => v > 0)
  const lowFw = low.filter(s => typeof T(s).lunge === 'boolean')
  const mins = motion?.tracked_s ? motion.tracked_s / 60 : 0
  return {
    strokes: shots.length, overhead: over.length, mid: mid.length, low: low.length,
    fast: shots.filter(s => T(s).pace === 'fast').length,
    fast_pct: pct(shots.filter(s => T(s).pace === 'fast').length, shots.length),
    elbow_up_pct: pct(over.filter(s => T(s).elbow_up).length, over.length),
    elbow_low: over.filter(s => T(s).elbow_up === false).length,
    off_base: fw.length ? off.length : null,
    no_recovery: fw.length ? off.length - rec.length : null,
    late_recovery: fw.length ? late.length : null,
    recovery_pct: fw.length ? pct(rec.length, off.length) : null,
    avg_recovery_s: recTimes.length ? Math.round(recTimes.reduce((a, b) => a + b, 0) / recTimes.length * 100) / 100 : null,
    low_no_lunge: lowFw.length ? lowFw.filter(s => !T(s).lunge).length : null,
    lunge_pct: lowFw.length ? pct(lowFw.filter(s => T(s).lunge).length, lowFw.length) : null,
    movement_per_min: mins > 0.2 && motion?.distance_bh != null ? Math.round(motion.distance_bh / mins * 10) / 10 : null,
    tracked_min: mins ? Math.round(mins * 10) / 10 : null,
    // need shuttle tracking — deliberately not guessed
    missed_hits: null, out_of_court: null, net_errors: null,
  }
}

async function buildSummaries(supa: any, ctx: any): Promise<number> {
  const { video_id, run_id, tags, shots, nameByTag, lines, usage } = ctx
  const { data: motionRows } = await supa.from('analysis_player_summary').select('tag_id, motion').eq('run_id', run_id)
  const motionBy: Record<string, any> = Object.fromEntries((motionRows ?? []).map((m: any) => [m.tag_id, m.motion]))
  const { data: vrow } = await supa.from('match_videos').select('created_at, game_type').eq('id', video_id).maybeSingle()
  let n = 0
  await Promise.all(tags.filter((t: any) => t.is_subject).map(async (t: any) => {
    const mine = shots.filter((s: any) => s.tag_id === t.id)
    const kpis = computeKpis(mine, motionBy[t.id])
    let previous: any = null
    if (t.player_id) {
      const { data: prev } = await supa.from('analysis_player_summary')
        .select('kpis, created_at, video_id, match_videos!inner(created_at), analysis_runs!inner(status, is_mock)')
        .eq('player_id', t.player_id).neq('video_id', video_id)
        .eq('analysis_runs.status', 'done').eq('analysis_runs.is_mock', false)
        .lt('match_videos.created_at', vrow?.created_at || new Date().toISOString())
        .order('created_at', { ascending: false }).limit(1)
      previous = prev?.[0]?.kpis?.strokes != null ? prev[0].kpis : null
    }
    const coach = kpis.strokes ? await coachVerdict(nameByTag[t.id] || 'Player', kpis, previous,
      lines.filter((l: any) => l.tag_id === t.id).map((l: any) => l.text).slice(0, 60), vrow?.game_type, usage) : null
    const { error } = await supa.from('analysis_player_summary').upsert(
      { video_id, run_id, tag_id: t.id, kpis, coach, audio_path: null }, { onConflict: 'run_id,tag_id' })
    if (!error) n++
  }))
  return n
}

async function coachVerdict(name: string, kpis: any, previous: any, lines: string[], gameType: string, usage: any) {
  const prompt =
    `You are a BWF Level 3 head coach reviewing ${name}'s ${gameType || 'badminton'} match from video analysis. ` +
    `You are warm, direct and specific — like a top national-squad coach talking one-to-one after a match.\n` +
    `DATA YOU CAN TRUST (pose tracking, counted per stroke):\n${JSON.stringify(kpis)}\n` +
    (previous ? `SAME PLAYER, PREVIOUS ANALYSED MATCH:\n${JSON.stringify(previous)}\n` : `No previous match to compare yet.\n`) +
    `Shot-by-shot notes already given:\n${lines.join('\n')}\n\n` +
    `KPI meanings: off_base = strokes played away from their usual base position; no_recovery = of those, times they ` +
    `did NOT get back to base before their next stroke; late_recovery = got back but slower than 1.2 s; ` +
    `avg_recovery_s = average time to get back; elbow_low = overheads hit with the elbow below the shoulder; ` +
    `elbow_up_pct = % of overheads with a high elbow; low_no_lunge = low strokes played without bending into a lunge; ` +
    `lunge_pct = % of low strokes with a proper lunge; fast_pct = % of strokes with a fast racket swing; ` +
    `movement_per_min = ground covered per minute (in body-heights). null = not measured yet (missed hits, shots out ` +
    `and net errors need shuttle tracking) — NEVER mention or guess those.\n` +
    `Rules: use only the numbers above, quote them exactly, never invent results, scores, placement or opponents' ` +
    `play. SAMPLE SIZE: a % built on fewer than 6 strokes (see the counts overhead / low / off_base) is a small ` +
    `sample — mention it only as "a few" and never make it the #1 focus or the next goal. ` +
    `Prioritise like a coach: the ONE thing that will change their game most comes first (usually base recovery ` +
    `or preparation before technique). If a previous match exists, say clearly what improved or slipped, with both numbers.\n` +
    `Return STRICT JSON:\n` +
    `{"headline":"<max 12 words, the big picture>",` +
    `"summary":"<2-3 sentences, plain English>",` +
    `"strengths":[{"title":"<3-5 words>","detail":"<1 sentence citing a number>"}] (2-3 items),` +
    `"focus":[{"title":"<3-5 words>","why":"<1 sentence citing a number>","how":"<1-2 sentences of concrete coaching cues>"}] (exactly 3, most important first),` +
    `"drills":[{"name":"<drill name>","how":"<2 sentences>","dose":"<e.g. 3 x 2 min, 30 s rest>"}] (2-3 items, standard BWF coaching drills),` +
    `"next_goal":"<one measurable target for the next match, using a KPI above>",` +
    `"progress":"<1 sentence vs previous match, or empty string if none>",` +
    `"script":"<what you would SAY to ${name}: 70-110 words, spoken, encouraging, first name, covers the headline, top strength, the #1 focus with how, and the next goal>"}`
  for (let attempt = 0; attempt < 3; attempt++) {
    try {
      const resp = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent?key=${GEMINI}`, {
        method: 'POST', headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ contents: [{ role: 'user', parts: [{ text: prompt }] }],
          generationConfig: { temperature: 0.5, maxOutputTokens: 8192, responseMimeType: 'application/json' } }),
      })
      const out = await resp.json()
      const um = out?.usageMetadata || {}
      usage.calls++; usage.input_tokens += um.promptTokenCount || 0
      usage.output_tokens += um.candidatesTokenCount || 0; usage.thinking_tokens += um.thoughtsTokenCount || 0
      const text = out?.candidates?.[0]?.content?.parts?.map((p: any) => p.text || '').join('') || ''
      const v = JSON.parse(text.slice(text.indexOf('{'), text.lastIndexOf('}') + 1))
      if (v?.headline && Array.isArray(v.focus)) return v
    } catch { /* retry */ }
    await new Promise((r) => setTimeout(r, 1500 * (attempt + 1)))
  }
  return null
}

async function meterSummary(supa: any, video_id: string, run_id: string | null, user_id: string | null, players: number) {
  if (!sumUsage.calls) return
  try {
    await supa.from('ai_usage').insert({ feature: 'commentary', provider: 'gemini', video_id, run_id, user_id: user_id || null,
      units: { ...sumUsage, kind: 'coach_summary', players, model: MODEL } })
  } catch { /* ignore */ }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })
  let video_id = '', run_id: string | null = null
  const supa = createClient(SUPA_URL, SERVICE)
  try {
    const body = await req.json()
    const given = req.headers.get('x-analyze-secret') || body.secret || ''
    if (!SECRET || given !== SECRET) return json({ error: 'forbidden' }, 403)
    Object.assign(sumUsage, { input_tokens: 0, output_tokens: 0, thinking_tokens: 0, calls: 0 })
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
    const allShots = (shots ?? []).filter((s: any) => subjIds.has(s.tag_id)).slice(0, 400)

    // Re-build only the Head Coach Summary from an existing version (no new commentary, no GPU).
    if (body.summary_only && run_id) {
      const { data: lineRows } = await supa.from('analysis_commentary').select('tag_id, t_s, text').eq('run_id', run_id).order('t_s')
      const n = await buildSummaries(supa, { video_id, run_id, tags: tags ?? [], shots: allShots, nameByTag, lines: lineRows ?? [], usage: sumUsage })
      await meterSummary(supa, video_id, run_id, body.user_id, n)
      return json({ ok: true, summaries: n })
    }

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

    const rules =
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
      `Output STRICT JSON: an array of {"shot_id":"<id>","text":"<line>","severity":"good|info|watch"}, one per stroke.\n`

    // Long matches have hundreds of strokes: send them in batches of 20 (in parallel) so no single reply
    // hits the output-token limit (the model's thinking also counts against it).
    const usage = { input_tokens: 0, output_tokens: 0, thinking_tokens: 0, calls: 0 }
    const record = async (lines: number) => {
      try {
        await supa.from('ai_usage').insert({ feature: 'commentary', provider: 'gemini', video_id, run_id,
          user_id: body.user_id || null, units: { ...usage, lines, model: MODEL } })
      } catch { /* metering must never break the product */ }
    }

    async function commentBatch(batch: any[]): Promise<{ rows: any[], finish: string }> {
      let text = '[]', finish = ''
      for (let attempt = 0; attempt < 3; attempt++) {
        try {
          const resp = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent?key=${GEMINI}`, {
            method: 'POST', headers: { 'content-type': 'application/json' },
            body: JSON.stringify({
              contents: [{ role: 'user', parts: [{ text: rules + `Strokes:\n${JSON.stringify(batch)}` }] }],
              generationConfig: { temperature: 0.6, maxOutputTokens: 16384, responseMimeType: 'application/json' },
            }),
          })
          const out = await resp.json()
          const um = out?.usageMetadata || {}
          usage.calls++
          usage.input_tokens += um.promptTokenCount || 0
          usage.output_tokens += um.candidatesTokenCount || 0
          usage.thinking_tokens += um.thoughtsTokenCount || 0
          finish = out?.candidates?.[0]?.finishReason ?? (out?.error?.message ? 'ERR:' + out.error.message : 'none')
          text = out?.candidates?.[0]?.content?.parts?.map((p: any) => p.text || '').join('') || '[]'
          if (!finish.startsWith('ERR') && !finish.startsWith('EXC')) break
        } catch (e) { finish = 'EXC:' + String(e) }
        await new Promise((r) => setTimeout(r, 2000 * (attempt + 1)))
      }
      let lines = toLines(text)
      if (!lines.length) lines = salvage(text)          // truncated reply: keep every complete line
      const rows = lines.map((ln: any, i: number) => {
        if (!ln || !ln.text) return null
        const sid = (ln.shot_id && tagOfShot[ln.shot_id]) ? ln.shot_id : (batch[i]?.shot_id || null)
        if (!sid) return null
        return {
          video_id, run_id, tag_id: tagOfShot[sid], shot_id: sid, t_s: tOfShot[sid], lens: 'coach',
          text: String(ln.text).slice(0, 500),
          severity: ['good', 'info', 'watch', 'warning'].includes(ln.severity) ? ln.severity : 'info',
        }
      }).filter(Boolean)
      return { rows, finish }
    }

    const batches: any[][] = []
    for (let i = 0; i < shotList.length; i += 20) batches.push(shotList.slice(i, i + 20))
    const results: { rows: any[], finish: string }[] = []
    for (let i = 0; i < batches.length; i += 8) {          // at most 8 calls in flight
      results.push(...await Promise.all(batches.slice(i, i + 8).map(commentBatch)))
    }
    const seen = new Set<string>()
    const rows = results.flatMap(r => r.rows).filter((r: any) => !seen.has(r.shot_id) && seen.add(r.shot_id))
    const finish = results.map(r => r.finish).join(',')

    // Strokes existed but no commentary came back → a clear, retryable failure (never an empty "done").
    await record(rows.length)
    if (!rows.length) {
      const busy = /ERR|EXC/.test(finish)
      console.error('commentary: no lines', run_id, finish.slice(0, 600))
      await supa.rpc('fail_deep', { p_video_id: video_id, p_run_id: run_id,
        p_error: busy ? 'AI commentary is busy right now — please try again in a few minutes.'
                      : 'Could not write commentary for this video — please re-analyse.' })
      return json({ ok: false, reason: busy ? 'rate_limited' : 'empty', finish })
    }

    if (run_id) await supa.from('analysis_commentary').delete().eq('run_id', run_id)   // idempotent retry of THIS version only
    if (rows.length) await supa.from('analysis_commentary').insert(rows)
    // Head Coach Summary per player (KPIs + verdict). Never blocks the commentary from finishing.
    if (run_id) {
      try {
        const n = await buildSummaries(supa, { video_id, run_id, tags: tags ?? [], shots: allShots, nameByTag, lines: rows, usage: sumUsage })
        await meterSummary(supa, video_id, run_id, body.user_id, n)
      } catch (e) { console.error('summary failed', e) }
    }
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
