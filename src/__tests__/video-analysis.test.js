import { describe, it, expect } from 'vitest'
import {
  expectedSides, flipSide, courtSideAt, slotComplete, slotsComplete, anySlotComplete, buildTags, videoTitle, isDefaultTitle, resolveTagName,
  versionLabel, tagThumbPath,
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

describe('one named player is enough', () => {
  it('needs at least one complete slot', () => {
    expect(anySlotComplete([{ assign: 'p:1' }, { assign: '' }, { assign: '' }, { assign: '' }])).toBe(true)
    expect(anySlotComplete([{ assign: '' }, { assign: 'label', label: ' ' }])).toBe(false)
    expect(anySlotComplete([])).toBe(false)
  })
  it('empty slots are not sent as tags', () => {
    const tags = buildTags([
      { assign: '', court_side: 'near_left', is_subject: true },
      { assign: 'p:me', court_side: 'near_right', is_subject: true },
      { assign: 'label', label: '', court_side: 'far_left', is_subject: true },
    ])
    expect(tags).toHaveLength(1)
    expect(tags[0]).toMatchObject({ player_id: 'me', court_side: 'near_right', is_subject: true })
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

describe('versionLabel', () => {
  const run = { version: 2, created_at: '2026-11-07T07:16:00Z', is_mock: false }
  it('names the version and marks the latest', () => {
    const s = versionLabel(run, 2, 'en-GB')
    expect(s.startsWith('Version 2 · ')).toBe(true)
    expect(s).toContain('2026')
    expect(s.endsWith('(latest)')).toBe(true)
  })
  it('older versions are not marked latest; samples are flagged', () => {
    expect(versionLabel({ ...run, version: 1 }, 2)).not.toContain('latest')
    expect(versionLabel({ ...run, is_mock: true }, 3)).toContain('Sample')
  })
  it('copes with missing data', () => {
    expect(versionLabel(null, 1)).toBe('')
    expect(versionLabel({ version: 4 }, 4)).toBe('Version 4 (latest)')
  })
})

describe('tagThumbPath', () => {
  const tracks = [
    { id: 't1', court_side: 'near_left', thumb_path: 'club/thumbs/v/near_left.jpg' },
    { id: 't2', court_side: 'far_right', thumb_path: null },
  ]
  it('prefers the tag photo, then the linked track, then the same court position', () => {
    expect(tagThumbPath({ thumb_path: 'own.jpg', track_id: 't1' }, tracks)).toBe('own.jpg')
    expect(tagThumbPath({ track_id: 't1' }, tracks)).toBe('club/thumbs/v/near_left.jpg')
    expect(tagThumbPath({ court_side: 'near_left' }, tracks)).toBe('club/thumbs/v/near_left.jpg')
  })
  it('returns null when no photo exists', () => {
    expect(tagThumbPath({ court_side: 'far_right' }, tracks)).toBe(null)
    expect(tagThumbPath(null, tracks)).toBe(null)
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

describe('video title from tagged players', () => {
  const names = { a: 'Sajeev', b: 'Aravind', c: 'Vishnu', d: 'Mathews' }
  const tags = [
    { player_id: 'c', court_side: 'far_left' }, { player_id: 'b', court_side: 'near_right' },
    { player_id: 'a', court_side: 'near_left' }, { label: 'Opponent A', court_side: 'far_right' },
  ]
  it('names both sides, near side first', () => {
    expect(videoTitle({ title: 'Uploaded match · 11/14/2026' }, tags, names)).toBe('Sajeev & Aravind vs Vishnu & Opponent A')
    expect(videoTitle({ title: 'Match video · 11/8/2026' }, [{ player_id: 'a', court_side: 'near' }, { player_id: 'c', court_side: 'far' }], names)).toBe('Sajeev vs Vishnu')
  })
  it('one tagged player shows just that name', () => {
    expect(videoTitle({ title: 'Uploaded match · 1/1/2026' }, [{ player_id: 'a', court_side: 'near_left' }], names)).toBe('Sajeev')
  })
  it('keeps a typed title and the default when nobody is named', () => {
    expect(videoTitle({ title: 'Saj Aravind vs Vishnu Mathew' }, tags, names)).toBe('Saj Aravind vs Vishnu Mathew')
    expect(videoTitle({ title: 'Uploaded match · 1/1/2026' }, [], names)).toBe('Uploaded match · 1/1/2026')
    expect(videoTitle({ title: 'Uploaded match · 1/1/2026' }, [{ player_id: 'zz', court_side: 'near' }], names)).toBe('Uploaded match · 1/1/2026')
    expect(isDefaultTitle('')).toBe(true); expect(isDefaultTitle('Final')).toBe(false)
  })
})
