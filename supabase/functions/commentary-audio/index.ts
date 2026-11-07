// Spoken commentary for Coach Vision Deep Coaching. For the requested commentary lines of one analysis
// version, generate an AI-voice clip (Gemini TTS) per line, store it in R2 as WAV (cached — each line is
// voiced once), and return short-lived playback URLs. Usage (tokens) is metered into ai_usage.
//
// Body: { video_id, run_id, line_ids: [uuid, ...] (max 40 per call) }
// Secrets: GEMINI_API_KEY, R2_ACCOUNT_ID, R2_VIDEO_ACCESS_KEY_ID, R2_VIDEO_SECRET_ACCESS_KEY, R2_VIDEO_BUCKET.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4'
import { AwsClient } from 'https://esm.sh/aws4fetch@1.0.20'

const SUPA_URL = Deno.env.get('SUPABASE_URL') ?? ''
const SERVICE  = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
const GEMINI   = Deno.env.get('GEMINI_API_KEY') ?? ''
const ACCOUNT  = Deno.env.get('R2_ACCOUNT_ID') ?? ''
const BUCKET   = Deno.env.get('R2_VIDEO_BUCKET') ?? ''
const SECRET   = Deno.env.get('ANALYZE_SHARED_SECRET') ?? ''
const ENDPOINT = `https://${ACCOUNT}.r2.cloudflarestorage.com`
const aws = new AwsClient({ accessKeyId: Deno.env.get('R2_VIDEO_ACCESS_KEY_ID') ?? '',
  secretAccessKey: Deno.env.get('R2_VIDEO_SECRET_ACCESS_KEY') ?? '', service: 's3', region: 'auto' })
const TTS_MODELS = ['gemini-2.5-flash-preview-tts', 'gemini-2.5-flash-tts']
const VOICE = 'Puck'   // upbeat; reads like a sports commentator

const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type, apikey, x-client-info' }
const json = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { ...CORS, 'content-type': 'application/json' } })

function b64ToBytes(b64: string) { const bin = atob(b64); const u = new Uint8Array(bin.length); for (let i = 0; i < bin.length; i++) u[i] = bin.charCodeAt(i); return u }

// Wrap raw 16-bit mono PCM in a WAV container so every browser (incl. iOS Safari) can play it.
function wav(pcm: Uint8Array, rate: number) {
  const h = new DataView(new ArrayBuffer(44))
  const w = (o: number, s: string) => { for (let i = 0; i < s.length; i++) h.setUint8(o + i, s.charCodeAt(i)) }
  w(0, 'RIFF'); h.setUint32(4, 36 + pcm.length, true); w(8, 'WAVE'); w(12, 'fmt ')
  h.setUint32(16, 16, true); h.setUint16(20, 1, true); h.setUint16(22, 1, true); h.setUint32(24, rate, true)
  h.setUint32(28, rate * 2, true); h.setUint16(32, 2, true); h.setUint16(34, 16, true); w(36, 'data'); h.setUint32(40, pcm.length, true)
  const out = new Uint8Array(44 + pcm.length); out.set(new Uint8Array(h.buffer), 0); out.set(pcm, 44); return out
}

async function signed(key: string, method: string) {
  return (await aws.sign(`${ENDPOINT}/${BUCKET}/${key}?X-Amz-Expires=3600`, { method, aws: { signQuery: true } })).url
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })
  try {
    const supa = createClient(SUPA_URL, SERVICE)
    const body = await req.json()
    const { video_id, run_id, line_ids } = body
    // Server-side callers (worker / ops) may use the shared secret instead of a user session.
    const internal = !!SECRET && (req.headers.get('x-analyze-secret') || body.secret) === SECRET
    let userId: string | null = null
    if (!internal) {
      const jwt = (req.headers.get('Authorization') ?? '').replace('Bearer ', '')
      const { data: u } = await supa.auth.getUser(jwt)
      if (!u?.user) return json({ error: 'unauthorized' }, 401)
      userId = u.user.id
    }
    if (!video_id || !run_id || !Array.isArray(line_ids)) return json({ error: 'bad request' }, 400)

    const { data: vid } = await supa.from('match_videos').select('club_id, uploaded_by, storage_path').eq('id', video_id).maybeSingle()
    if (!vid) return json({ error: 'not found' }, 404)
    let ok = internal || vid.uploaded_by === userId
    if (!ok) ok = !!(await supa.from('club_members').select('user_id').eq('club_id', vid.club_id).eq('user_id', userId).maybeSingle()).data
    if (!ok) ok = !!(await supa.from('app_roles').select('role').eq('user_id', userId).eq('role', 'app_admin').maybeSingle()).data
    if (!ok) return json({ error: 'forbidden' }, 403)

    const club = String(vid.storage_path || '').split('/')[0] || vid.club_id
    const { data: lines } = await supa.from('analysis_commentary').select('id, text, audio_path')
      .eq('video_id', video_id).eq('run_id', run_id).in('id', line_ids.slice(0, 40))

    const usage = { input_tokens: 0, output_tokens: 0, calls: 0, chars: 0, voiced: 0 }
    let lastErr = ''

    async function voice(line: any) {
      if (line.audio_path) return
      for (const model of TTS_MODELS) {
        try {
          const resp = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${GEMINI}`, {
            method: 'POST', headers: { 'content-type': 'application/json' },
            body: JSON.stringify({
              contents: [{ parts: [{ text: `Say this like an upbeat, friendly badminton commentator: ${line.text}` }] }],
              generationConfig: { responseModalities: ['AUDIO'],
                speechConfig: { voiceConfig: { prebuiltVoiceConfig: { voiceName: VOICE } } } },
            }),
          })
          const out = await resp.json()
          usage.calls++
          usage.input_tokens += out?.usageMetadata?.promptTokenCount || 0
          usage.output_tokens += out?.usageMetadata?.candidatesTokenCount || 0
          const part = out?.candidates?.[0]?.content?.parts?.find((p: any) => p.inlineData?.data)
          if (!part) { lastErr = out?.error?.message || out?.candidates?.[0]?.finishReason || 'no audio'; continue }
          const rate = Number(/rate=(\d+)/.exec(part.inlineData.mimeType || '')?.[1] || 24000)
          const key = `${club}/audio/${video_id}/${run_id}/${line.id}.wav`
          const put = await fetch(await signed(key, 'PUT'), { method: 'PUT', headers: { 'content-type': 'audio/wav' },
            body: wav(b64ToBytes(part.inlineData.data), rate) })
          if (!put.ok) { lastErr = `R2 ${put.status}`; return }
          await supa.from('analysis_commentary').update({ audio_path: key }).eq('id', line.id)
          line.audio_path = key
          usage.chars += String(line.text).length
          usage.voiced++
          return
        } catch (e) { lastErr = String(e) }
      }
    }

    const todo = (lines ?? []).filter((l: any) => !l.audio_path)
    for (let i = 0; i < todo.length; i += 6) await Promise.all(todo.slice(i, i + 6).map(voice))

    if (usage.calls) {
      try {
        await supa.from('ai_usage').insert({ feature: 'commentary_audio', provider: 'gemini', video_id, run_id,
          user_id: userId, club_id: vid.club_id, units: { ...usage, model: TTS_MODELS[0], voice: VOICE } })
      } catch { /* ignore */ }
    }

    const clips = []
    for (const l of lines ?? []) if (l.audio_path) clips.push({ id: l.id, url: await signed(l.audio_path, 'GET') })
    return json({ clips, voiced: usage.voiced, error: clips.length ? undefined : lastErr || undefined })
  } catch (e) {
    return json({ error: String((e as Error)?.message ?? e) }, 500)
  }
})
