import { describe, it, expect } from 'vitest'
import {
  expectedSides, flipSide, courtSideAt, slotComplete, slotsComplete, buildTags, resolveTagName,
} from '../lib/videoAnalysis'
import { CONSENT_VERSION, CONSENT_POINTS, CONSENT_SUMMARY } from '../lib/consent'

describe('expectedSides', () => {
  it('singles has 2 positions, doubles has 4', () => {
    expect(expectedSides('singles')).toEqual(['near', 'far'])
    expect(expectedSides('doubles')).toHaveLength(4)
  })
})

describe('flipSide (change of ends from a fixed camera)', () => {
  it('flips near<->far', () => {
    expect(flipSide('near')).toBe('far')
    expect(flipSide('far')).toBe('near')
  })
  it('flips both axes for doubles corners', () => {
    expect(flipSide('near_left')).toBe('far_right')
    expect(flipSide('far_right')).toBe('near_left')
  })
  it('is its own inverse', () => {
    for (const s of ['near', 'far', 'near_left', 'near_right', 'far_left', 'far_right']) {
      expect(flipSide(flipSide(s))).toBe(s)
    }
  })
  it('handles empty/null safely', () => {
    expect(flipSide('')).toBe('')
    expect(flipSide(null)).toBe(null)
  })
})

describe('courtSideAt (identity after mid-match end swaps)', () => {
  const swaps = [{ at_s: 420 }]
  it('before the swap the player is on their base side', () => {
    expect(courtSideAt('near', swaps, 100)).toBe('near')
  })
  it('after one swap the side is flipped', () => {
    expect(courtSideAt('near', swaps, 500)).toBe('far')
  })
  it('two swaps returns to base', () => {
    expect(courtSideAt('near_left', [{ at_s: 100 }, { at_s: 200 }], 300)).toBe('near_left')
  })
  it('no events means no change', () => {
    expect(courtSideAt('far', [], 9999)).toBe('far')
  })
})

describe('tagging slot completeness', () => {
  it('a roster assignment is complete', () => {
    expect(slotComplete({ assign: 'p:abc' })).toBe(true)
  })
  it('a label needs non-empty text', () => {
    expect(slotComplete({ assign: 'label', label: '  ' })).toBe(false)
    expect(slotComplete({ assign: 'label', label: 'Opponent A' })).toBe(true)
  })
  it('unassigned is incomplete', () => {
    expect(slotComplete({ assign: '' })).toBe(false)
  })
  it('all slots must be complete', () => {
    expect(slotsComplete([{ assign: 'p:1' }, { assign: '' }])).toBe(false)
    expect(slotsComplete([{ assign: 'p:1' }, { assign: 'label', label: 'X' }])).toBe(true)
    expect(slotsComplete([])).toBe(false)
  })
})

describe('buildTags', () => {
  it('maps roster, labels and subject flag to the RPC payload', () => {
    const tags = buildTags([
      { track_id: 't1', assign: 'p:player9', court_side: 'near', is_subject: true },
      { track_id: null, assign: 'label', label: '  Opponent A  ', court_side: 'far', is_subject: false },
    ])
    expect(tags[0]).toEqual({ track_id: 't1', player_id: 'player9', label: null, court_side: 'near', is_subject: true })
    expect(tags[1]).toEqual({ track_id: null, player_id: null, label: 'Opponent A', court_side: 'far', is_subject: false })
  })
})

describe('resolveTagName', () => {
  it('prefers linked roster name, falls back to label', () => {
    expect(resolveTagName({ player_id: 'p1' }, { p1: 'Marcus' })).toBe('Marcus')
    expect(resolveTagName({ label: 'Opponent A' }, {})).toBe('Opponent A')
    expect(resolveTagName(null)).toBe('Player')
  })
})

describe('consent terms', () => {
  it('has a version and covers AI processing + not-medical-advice', () => {
    expect(CONSENT_VERSION).toMatch(/^v\d/)
    expect(CONSENT_SUMMARY.toLowerCase()).toContain('ai')
    const joined = CONSENT_POINTS.join(' ').toLowerCase()
    expect(joined).toContain('computer-vision')
    expect(joined).toContain('not a medical')
    expect(joined).toContain('withdraw consent')
  })
})
