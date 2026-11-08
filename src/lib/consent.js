// Single source of truth for the AI video-analysis consent.
// The version string is stored on each match_videos row (consent_version) so a later wording
// change never retroactively "covers" footage captured under older terms.
export const CONSENT_VERSION = 'v2-2026-11'

export const CONSENT_SUMMARY =
  'Everyone visible on court agrees to be recorded, and to this video being processed by automated AI to produce movement and technique analysis.'

// Full, plain-language terms. Kept precise because the video is biometric-adjacent (body movement)
// and one lens produces injury-risk observations.
export const CONSENT_POINTS = [
  'All players and anyone else visible on court have agreed to be recorded or to this footage being uploaded.',
  'The video is processed by automated computer-vision and AI to estimate movement, court positioning, shots and technique. No human is guaranteed to review it.',
  'Resulting analysis is visible to members of this club and to app administrators. The person who records/uploads controls the video.',
  'The video is stored privately (encrypted at rest on Cloudflare R2) and can be deleted on request. By default it is kept for up to 30 days, or only as a private link if you choose.',
  'The injury-risk / physiotherapy view is general information generated from movement patterns. It is NOT a medical diagnosis or medical advice. Consult a qualified professional for any pain or injury.',
  'Players who have turned on "Recognise me in match videos" may be suggested by face. For everyone else, any face signature made from this video is deleted once it is tagged.',
  'Analysis accuracy is affected by camera angle, lighting, video quality and players blocking the view. Low-confidence results are labelled, not hidden.',
  'Processors involved: Supabase (database), Cloudflare R2 (video storage), Google (AI analysis). Your video is not sold or used for advertising.',
  'You can withdraw consent and request removal of a video at any time via your club manager or support.',
]
