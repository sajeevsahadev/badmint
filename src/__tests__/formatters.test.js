import { describe, it, expect, beforeEach, vi } from 'vitest'
import { aed, fmtExpMonth, fmtExpDay, fmtDMY, parseLocalDate, timeAgo, deviceIcon } from '../utils/formatters'

describe('fmtDMY()', () => {
  it('converts YYYY-MM-DD to dd-MM-yyyy', () => {
    expect(fmtDMY('2026-09-07')).toBe('07-09-2026')
    expect(fmtDMY('2026-01-31')).toBe('31-01-2026')
  })
  it('returns empty string for blank/invalid input', () => {
    expect(fmtDMY('')).toBe('')
    expect(fmtDMY(null)).toBe('')
    expect(fmtDMY(undefined)).toBe('')
    expect(fmtDMY('not-a-date')).toBe('')
    expect(fmtDMY('07/09/2026')).toBe('')
  })
})

// ── aed() ─────────────────────────────────────────────────────────────────────

describe('aed()', () => {
  it('formats integer with two decimal places', () => {
    expect(aed(10)).toBe('AED 10.00')
  })

  it('formats decimal with two decimal places', () => {
    expect(aed(10.5)).toBe('AED 10.50')
  })

  it('rounds to 2 decimal places via toFixed', () => {
    // Note: 10.555 in IEEE-754 is 10.554999… so toFixed(2) → '10.55', not '10.56'
    // This documents the known JS float behaviour rather than asserting "wrong" rounding.
    expect(aed(10.555)).toBe('AED 10.55')
    expect(aed(10.556)).toBe('AED 10.56')
    expect(aed(10.554)).toBe('AED 10.55')
  })

  it('handles zero', () => {
    expect(aed(0)).toBe('AED 0.00')
  })

  it('handles string input by coercing to number', () => {
    expect(aed('25.5')).toBe('AED 25.50')
  })

  it('handles large amounts', () => {
    expect(aed(10000)).toBe('AED 10000.00')
  })
})

// ── parseLocalDate() ──────────────────────────────────────────────────────────

describe('parseLocalDate()', () => {
  it('parses a YYYY-MM-DD string without UTC timezone shift', () => {
    const d = parseLocalDate('2025-01-15')
    // In any UTC+ timezone, '2025-01-15T00:00:00' local time stays on Jan 15
    expect(d.getDate()).toBe(15)
    expect(d.getMonth()).toBe(0) // January = 0
    expect(d.getFullYear()).toBe(2025)
  })

  it('does not shift date for UTC+ timezone (guards against UTC parse)', () => {
    // If parsed as UTC midnight in UTC+4, Date would be Jan 14 at 8PM local —
    // getDate() would return 14, not 15. Our T00:00:00 suffix prevents this.
    const d = parseLocalDate('2025-03-01')
    expect(d.getDate()).toBe(1)
  })
})

// ── fmtExpMonth() / fmtExpDay() ───────────────────────────────────────────────

describe('fmtExpMonth()', () => {
  it('returns short month name', () => {
    // '2025-06-15' should return 'Jun'
    expect(fmtExpMonth('2025-06-15')).toBe('Jun')
  })

  it('returns — for falsy input', () => {
    expect(fmtExpMonth(null)).toBe('—')
    expect(fmtExpMonth('')).toBe('—')
    expect(fmtExpMonth(undefined)).toBe('—')
  })
})

describe('fmtExpDay()', () => {
  it('returns zero-padded day', () => {
    expect(fmtExpDay('2025-06-05')).toBe('05')
    expect(fmtExpDay('2025-06-15')).toBe('15')
  })

  it('returns — for falsy input', () => {
    expect(fmtExpDay(null)).toBe('—')
    expect(fmtExpDay('')).toBe('—')
  })
})

// ── timeAgo() ─────────────────────────────────────────────────────────────────

describe('timeAgo()', () => {
  beforeEach(() => {
    // Fix Date.now() so tests are deterministic
    vi.useFakeTimers()
    vi.setSystemTime(new Date('2025-06-15T12:00:00Z'))
  })
  afterEach(() => {
    vi.useRealTimers()
  })

  it('returns "just now" for timestamps within 1 minute', () => {
    const ts = new Date('2025-06-15T11:59:31Z').toISOString()
    expect(timeAgo(ts)).toBe('just now')
  })

  it('returns "Xm ago" for timestamps within 1 hour', () => {
    const ts = new Date('2025-06-15T11:55:00Z').toISOString()
    expect(timeAgo(ts)).toBe('5m ago')
  })

  it('returns "Xh ago" for timestamps within 1 day', () => {
    const ts = new Date('2025-06-15T09:00:00Z').toISOString()
    expect(timeAgo(ts)).toBe('3h ago')
  })

  it('returns "Xd ago" for timestamps within 7 days', () => {
    const ts = new Date('2025-06-13T12:00:00Z').toISOString()
    expect(timeAgo(ts)).toBe('2d ago')
  })

  it('returns a date string for timestamps older than 7 days', () => {
    const ts = new Date('2025-06-01T12:00:00Z').toISOString()
    const result = timeAgo(ts)
    expect(result).toMatch(/\d+/)       // contains a number
    expect(result).not.toMatch(/ago$/)  // not a relative label
  })
})

// ── deviceIcon() ──────────────────────────────────────────────────────────────

describe('deviceIcon()', () => {
  it('returns apple emoji for iPhone', () => {
    expect(deviceIcon('Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)')).toBe('🍎')
  })

  it('returns apple emoji for iPad', () => {
    expect(deviceIcon('Mozilla/5.0 (iPad; CPU OS 17_0 like Mac OS X)')).toBe('🍎')
  })

  it('returns robot emoji for Android', () => {
    expect(deviceIcon('Mozilla/5.0 (Linux; Android 14; Pixel 9)')).toBe('🤖')
  })

  it('returns desktop emoji for Windows', () => {
    expect(deviceIcon('Mozilla/5.0 (Windows NT 10.0; Win64; x64)')).toBe('🖥')
  })

  it('returns laptop emoji for macOS', () => {
    expect(deviceIcon('Mozilla/5.0 (Macintosh; Intel Mac OS X 13_0)')).toBe('💻')
  })

  it('returns globe emoji for unknown UA', () => {
    expect(deviceIcon('curl/7.88.1')).toBe('🌐')
  })

  it('returns empty string for null/undefined', () => {
    expect(deviceIcon(null)).toBe('')
    expect(deviceIcon(undefined)).toBe('')
    expect(deviceIcon('')).toBe('')
  })
})
