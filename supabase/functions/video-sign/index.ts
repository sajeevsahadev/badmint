// Presigns Cloudflare R2 (S3-compatible) URLs for match-video upload/playback/delete.
//
// Why: Supabase free tier is 1 GB — a single match video can exceed that. Videos live in
// R2 instead; this function hands the browser a short-lived presigned URL so the big bytes
// go straight to R2 (never through Supabase). The R2 keys stay server-side as secrets.
//
// Secrets required (set with: supabase secrets set ...):
//   R2_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_BUCKET
//
// Request body: { action: 'put' | 'get' | 'delete', clubId, key, contentType? }
//   key MUST be "<clubId>/<uuid>.<ext>" — the caller must be a member of that club.
import { AwsClient } from 'https://esm.sh/aws4fetch@1.0.20'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4'

const ACCOUNT  = Deno.env.get('R2_ACCOUNT_ID') ?? ''
const KEY_ID   = Deno.env.get('R2_ACCESS_KEY_ID') ?? ''
const SECRET   = Deno.env.get('R2_SECRET_ACCESS_KEY') ?? ''
const BUCKET   = Deno.env.get('R2_BUCKET') ?? ''
const SUPA_URL = Deno.env.get('SUPABASE_URL') ?? ''
const SERVICE  = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''

const ENDPOINT = `https://${ACCOUNT}.r2.cloudflarestorage.com`
const aws = new AwsClient({ accessKeyId: KEY_ID, secretAccessKey: SECRET, service: 's3', region: 'auto' })

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
    if (!ACCOUNT || !KEY_ID || !SECRET || !BUCKET) {
      return json({ error: 'R2 is not configured on the server yet.' }, 503)
    }
    const jwt = (req.headers.get('Authorization') ?? '').replace('Bearer ', '')
    if (!jwt) return json({ error: 'unauthorized' }, 401)

    const supa = createClient(SUPA_URL, SERVICE)
    const { data: u, error: uErr } = await supa.auth.getUser(jwt)
    if (uErr || !u?.user) return json({ error: 'unauthorized' }, 401)
    const userId = u.user.id

    const { action = 'put', clubId, key, contentType } = await req.json()
    if (!clubId || !key) return json({ error: 'bad request' }, 400)
    if (!String(key).startsWith(`${clubId}/`)) return json({ error: 'forbidden path' }, 403)

    // Caller must be a member of the club (or an app admin).
    const { data: mem } = await supa.from('club_members')
      .select('user_id').eq('club_id', clubId).eq('user_id', userId).maybeSingle()
    if (!mem) {
      const { data: adm } = await supa.from('app_roles')
        .select('role').eq('user_id', userId).eq('role', 'app_admin').maybeSingle()
      if (!adm) return json({ error: 'forbidden' }, 403)
    }

    const url = `${ENDPOINT}/${BUCKET}/${key}`
    const method = action === 'get' ? 'GET' : action === 'delete' ? 'DELETE' : 'PUT'
    const reqToSign = new Request(url, {
      method,
      headers: (method === 'PUT' && contentType) ? { 'content-type': contentType } : undefined,
    })
    // 1-hour presigned URL (query-signed so the browser can call it directly).
    const signed = await aws.sign(reqToSign, { aws: { signQuery: true }, headers: { 'x-amz-expires': '3600' } })
    return json({ url: signed.url, method, contentType: contentType ?? null })
  } catch (e) {
    return json({ error: String((e as Error)?.message ?? e) }, 500)
  }
})
