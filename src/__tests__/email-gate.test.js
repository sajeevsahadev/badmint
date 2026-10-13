import { describe, it, expect } from 'vitest'
import { canReceiveAutomatedEmail, prefEnabled, isSuppressed } from '../lib/emailGate.js'

// Guards the GDPR requirement: once a user is DEACTIVATED or DELETED (or has
// unsubscribed), no automated email may be sent to them — regardless of their
// per-category preferences. Every sender (lifecycle / announcement / digest /
// match / expense) applies canReceiveAutomatedEmail().

describe('canReceiveAutomatedEmail()', () => {
  const base = { email: 'player@example.com', deactivatedAt: null, suppressed: false, prefs: null, prefKey: 'news' }

  it('allows a normal, active, subscribed user (default opt-in)', () => {
    expect(canReceiveAutomatedEmail(base)).toBe(true)
  })

  // ── DEACTIVATED → never ─────────────────────────────────────────────
  it('BLOCKS a deactivated user even when the preference is ON', () => {
    expect(canReceiveAutomatedEmail({ ...base, deactivatedAt: '2026-10-13T00:00:00Z', prefs: { news: true } })).toBe(false)
  })

  it('BLOCKS a deactivated user regardless of any pref key', () => {
    for (const prefKey of ['news', 'weekly_digest', 'match_recorded', 'payment_reminders']) {
      expect(canReceiveAutomatedEmail({ ...base, prefKey, deactivatedAt: '2026-01-01T00:00:00Z' })).toBe(false)
    }
  })

  it('treats any truthy deactivated_at as deactivated', () => {
    expect(canReceiveAutomatedEmail({ ...base, deactivatedAt: '2026-10-13T10:00:00.000Z' })).toBe(false)
  })

  // ── DELETED → never (no email / no account) ─────────────────────────
  it('BLOCKS a deleted/unknown user (no email address)', () => {
    expect(canReceiveAutomatedEmail({ ...base, email: null })).toBe(false)
    expect(canReceiveAutomatedEmail({ ...base, email: '' })).toBe(false)
    expect(canReceiveAutomatedEmail({ ...base, email: undefined })).toBe(false)
  })

  // ── UNSUBSCRIBED (suppressed) → never ───────────────────────────────
  it('BLOCKS an unsubscribed (suppressed) email even if the preference is ON', () => {
    expect(canReceiveAutomatedEmail({ ...base, suppressed: true, prefs: { news: true } })).toBe(false)
  })

  // ── Preferences ─────────────────────────────────────────────────────
  it('BLOCKS when the category preference is explicitly false', () => {
    expect(canReceiveAutomatedEmail({ ...base, prefs: { news: false } })).toBe(false)
    expect(canReceiveAutomatedEmail({ ...base, prefs: { news: 'false' } })).toBe(false)
  })

  it('ALLOWS when the category preference is true or unset', () => {
    expect(canReceiveAutomatedEmail({ ...base, prefs: { news: true } })).toBe(true)
    expect(canReceiveAutomatedEmail({ ...base, prefs: {} })).toBe(true)        // key missing
    expect(canReceiveAutomatedEmail({ ...base, prefs: null })).toBe(true)      // no prefs row
    expect(canReceiveAutomatedEmail({ ...base, prefKey: null })).toBe(true)    // sender uses no category gate
  })

  it('ignores an OFF pref for a DIFFERENT category', () => {
    // digest is gated on weekly_digest; a match_recorded=false must not block it
    expect(canReceiveAutomatedEmail({ ...base, prefKey: 'weekly_digest', prefs: { match_recorded: false } })).toBe(true)
  })

  // ── Precedence: block reasons win over an ON preference ─────────────
  it('deactivation and suppression override an explicitly-enabled preference', () => {
    expect(canReceiveAutomatedEmail({ email: 'a@b.com', deactivatedAt: 'x', suppressed: false, prefs: { weekly_digest: true }, prefKey: 'weekly_digest' })).toBe(false)
    expect(canReceiveAutomatedEmail({ email: 'a@b.com', deactivatedAt: null, suppressed: true, prefs: { weekly_digest: true }, prefKey: 'weekly_digest' })).toBe(false)
  })
})

describe('prefEnabled()', () => {
  it('defaults to ON when prefs or key missing', () => {
    expect(prefEnabled(null, 'news')).toBe(true)
    expect(prefEnabled({}, 'news')).toBe(true)
    expect(prefEnabled({ news: true }, null)).toBe(true)
  })
  it('is OFF only for explicit false / "false"', () => {
    expect(prefEnabled({ news: false }, 'news')).toBe(false)
    expect(prefEnabled({ news: 'false' }, 'news')).toBe(false)
    expect(prefEnabled({ news: true }, 'news')).toBe(true)
  })
})

describe('isSuppressed()', () => {
  it('matches case-insensitively', () => {
    const set = new Set(['xavier@furnemont.be'])
    expect(isSuppressed('Xavier@Furnemont.BE', set)).toBe(true)
    expect(isSuppressed('xavier@furnemont.be', set)).toBe(true)
    expect(isSuppressed('someone@else.com', set)).toBe(false)
  })
  it('is safe with empty inputs', () => {
    expect(isSuppressed(null, new Set())).toBe(false)
    expect(isSuppressed('a@b.com', null)).toBe(false)
  })
})
