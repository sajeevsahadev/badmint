/**
 * Canonical "may this recipient receive an automated email?" rule for Badminton 360.
 *
 * Every email sender applies this exact gate, in this order:
 *   send-lifecycle-emails, send-announcement, send-weekly-digest,
 *   send-match-email, send-expense-email.
 *
 * A recipient is emailed ONLY when all of these hold:
 *   1. they still have an account/email        (a DELETED user has none → never)
 *   2. their account is NOT deactivated         (deactivated_at is null)
 *   3. their email is NOT on the suppression list (they haven't unsubscribed)
 *   4. the per-category preference is not OFF    (default ON when unset)
 *
 * The senders implement this inline (they run in Deno against Supabase); this
 * module is the single documented source of truth, unit-tested in
 * src/__tests__/email-gate.test.js. Keep the two in lockstep.
 */

/** A per-category email pref is ON unless explicitly set to false. Missing prefs = opt-in. */
export function prefEnabled(prefs, key) {
  if (!key) return true
  if (!prefs) return true
  const v = prefs[key]
  return v !== false && v !== 'false'
}

/** Case-insensitive membership check against a Set of suppressed (unsubscribed) emails. */
export function isSuppressed(email, suppressedSet) {
  if (!email || !suppressedSet) return false
  return suppressedSet.has(String(email).toLowerCase())
}

/**
 * @param {Object} r
 * @param {string|null} [r.email]         recipient email — null/empty means deleted/unknown → never email
 * @param {string|null} [r.deactivatedAt] user_profiles.deactivated_at — truthy means paused → never email
 * @param {boolean}     [r.suppressed]    true when the email is on the suppression list → never email
 * @param {Object|null} [r.prefs]         email_prefs jsonb
 * @param {string|null} [r.prefKey]       which preference gates this email (e.g. 'news', 'weekly_digest', 'match_recorded')
 * @returns {boolean} true only when the email may be sent
 */
export function canReceiveAutomatedEmail(r = {}) {
  const { email, deactivatedAt, suppressed, prefs, prefKey } = r
  if (!email) return false          // deleted / unknown account
  if (deactivatedAt) return false   // deactivated — no automated email
  if (suppressed) return false      // unsubscribed — honoured even over prefs
  return prefEnabled(prefs, prefKey)
}
