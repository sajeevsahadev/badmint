import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { AwsClient } from 'https://esm.sh/aws4fetch@1.0.20'

// Issues short-lived presigned R2 PUT URLs so the phone uploads a compressed
// image (+ small thumbnail) straight to Cloudflare R2 — bytes never pass
// through Supabase.
//
// Non-secret R2 config is hardcoded on purpose — only the access key + secret
// live in Edge Function secrets (R2_ACCESS_KEY_ID / R2_SECRET_ACCESS_KEY).
const ACCOUNT_ID = 'ec52a38cc5c9769a2266d172e1f85206'
const BUCKET = 'b360-chat-images'
const PUBLIC_BASE = 'https://images.badminton360.app'

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

function slugify(name: string): string {
  return (name || '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 40) || 'club'
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  const json = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { ...cors, 'Content-Type': 'application/json' } })

  try {
    const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
    const ANON = Deno.env.get('SUPABASE_ANON_KEY')!
    const SVC = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const AK = Deno.env.get('R2_ACCESS_KEY_ID')!
    const SK = Deno.env.get('R2_SECRET_ACCESS_KEY')!

    const authHeader = req.headers.get('authorization') ?? ''
    if (!authHeader) return json({ error: 'Unauthorized' }, 401)
    const userClient = createClient(SUPABASE_URL, ANON, { global: { headers: { Authorization: authHeader } } })
    const { data: { user }, error: authErr } = await userClient.auth.getUser()
    if (authErr || !user) return json({ error: 'Unauthorized' }, 401)

    const { club_id } = await req.json()
    if (!club_id) return json({ error: 'Missing club_id' }, 400)

    const admin = createClient(SUPABASE_URL, SVC)
    const { data: membership } = await admin
      .from('club_members').select('user_id').eq('club_id', club_id).eq('user_id', user.id).maybeSingle()
    if (!membership) return json({ error: 'Not a member' }, 403)

    // Readable, stable, unique folder: <club-slug>-<first 8 of club_id>
    const { data: club } = await admin.from('clubs').select('name').eq('id', club_id).maybeSingle()
    const folder = `${slugify(club?.name ?? '')}-${String(club_id).replace(/-/g, '').slice(0, 8)}`

    const id = crypto.randomUUID()
    const key = `${folder}/${id}.webp`
    const thumbKey = `${folder}/${id}_t.webp`
    const aws = new AwsClient({ accessKeyId: AK, secretAccessKey: SK, service: 's3', region: 'auto' })
    const sign = (k: string) => aws.sign(
      `https://${ACCOUNT_ID}.r2.cloudflarestorage.com/${BUCKET}/${k}?X-Amz-Expires=300`,
      { method: 'PUT', aws: { signQuery: true } },
    )
    const [full, thumb] = await Promise.all([sign(key), sign(thumbKey)])

    return json({
      uploadUrl: full.url, publicUrl: `${PUBLIC_BASE}/${key}`,
      thumbUploadUrl: thumb.url, thumbUrl: `${PUBLIC_BASE}/${thumbKey}`,
      key,
    })
  } catch (err) {
    return json({ error: err instanceof Error ? err.message : String(err) }, 500)
  }
})
