// Generates the "client secret" JWT that Supabase's Apple provider needs.
// Runs entirely on YOUR machine with YOUR .p8 key — the key never leaves it.
//
// Usage:
//   node scripts/generate-apple-secret.js <TEAM_ID> <KEY_ID> <SERVICES_ID> <path-to-AuthKey.p8>
//
// Example:
//   node scripts/generate-apple-secret.js A1B2C3D4E5 XYZ1234567 app.badminton360.web ./AuthKey_XYZ1234567.p8
//
// Paste the printed token into Supabase → Auth → Providers → Apple → "Secret Key (for OAuth)".
// Apple caps the lifetime at 6 months, so re-run this before it expires.
import crypto from 'crypto'
import { readFileSync } from 'fs'

const [, , teamId, keyId, servicesId, p8Path] = process.argv
if (!teamId || !keyId || !servicesId || !p8Path) {
  console.error('Usage: node scripts/generate-apple-secret.js <TEAM_ID> <KEY_ID> <SERVICES_ID> <path-to-AuthKey.p8>')
  process.exit(1)
}

const key = readFileSync(p8Path, 'utf8')
const now = Math.floor(Date.now() / 1000)
const b64 = (o) => Buffer.from(JSON.stringify(o)).toString('base64url')

const header  = { alg: 'ES256', kid: keyId, typ: 'JWT' }
const payload = {
  iss: teamId,
  iat: now,
  exp: now + 60 * 60 * 24 * 180,   // 180 days (Apple's max ~6 months)
  aud: 'https://appleid.apple.com',
  sub: servicesId,
}

const signingInput = `${b64(header)}.${b64(payload)}`
// ieee-p1363 gives the raw R||S signature JOSE/JWT requires (not DER).
const sig = crypto.sign('sha256', Buffer.from(signingInput), { key, dsaEncoding: 'ieee-p1363' }).toString('base64url')

console.log('\nApple client secret (paste into Supabase → Auth → Providers → Apple):\n')
console.log(`${signingInput}.${sig}\n`)
