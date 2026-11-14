import { describe, it, expect } from 'vitest'
import { MOVES, ISSUES, fk, samplePose, moveDuration, matchIssue, matchDrill, examplesFor, clipWindow, repeatStatus, staminaCheck, READY } from '../lib/coachMoves'
import { formScore, levelFor, badges, nextBadge, risingStreak } from '../lib/coachGame'

const shot = (tag, t, tech) => ({ tag_id: tag, t_s: t, technique: tech })

describe('movement library', () => {
  it('every move has frames with finite joints and a positive duration', () => {
    for (const [id, m] of Object.entries(MOVES)) {
      expect(moveDuration(m), id).toBeGreaterThan(0)
      for (let t = 0; t < moveDuration(m); t += 90) {
        const j = fk(samplePose(m, t).pose)
        for (const k of ['hip', 'neck', 'head', 'kneeF', 'footF', 'kneeB', 'footB', 'elbowR', 'handR', 'tipR', 'elbowL', 'handL']) {
          expect(Number.isFinite(j[k].x) && Number.isFinite(j[k].y), `${id}.${k}`).toBe(true)
          expect(j[k].x, `${id}.${k}.x`).toBeGreaterThan(0); expect(j[k].x, `${id}.${k}.x`).toBeLessThan(240)
          expect(j[k].y, `${id}.${k}.y`).toBeGreaterThan(0)
        }
        expect(Math.max(j.footF.y, j.footB.y)).toBeLessThanOrEqual(165.01)   // never below the floor
      }
    }
  })
  it('every issue points at real moves', () => {
    for (const is of Object.values(ISSUES)) for (const k of ['good', 'bad', 'drill']) expect(MOVES[is[k]], `${is.key}.${k}`).toBeTruthy()
  })
  it('the lowest foot rests on the floor in the ready pose', () => {
    const j = fk(READY)
    expect(Math.max(j.footF.y, j.footB.y)).toBeCloseTo(165, 5)
  })
  it('a high elbow is above the shoulder, a low one below', () => {
    const hit = (id) => fk(MOVES[id].frames[2].p)
    expect(hit('elbow_good').elbowR.y).toBeLessThan(hit('elbow_good').neck.y)
    expect(hit('elbow_bad').elbowR.y).toBeGreaterThan(hit('elbow_bad').neck.y)
  })
  it('samplePose wraps and holds cut frames', () => {
    const m = MOVES.recover_bad
    expect(samplePose(m, moveDuration(m) + 10).index).toBe(0)
    const a = samplePose(m, 500 + 450 + 1400 + 10), b = samplePose(m, 500 + 450 + 1400 + 700)
    expect(a.pose.x).toBe(b.pose.x)
  })
})

describe('matching coach text to measured issues and drills', () => {
  it('maps real focus titles', () => {
    expect(matchIssue({ title: 'Immediate Base Recovery' }).key).toBe('recovery')
    expect(matchIssue({ title: 'Lunge Execution on Low Balls' }).key).toBe('lunge')
    expect(matchIssue({ title: 'Low Forecourt Lunging' }).key).toBe('lunge')
    expect(matchIssue({ title: 'Low-Shot Lunge Execution' }).key).toBe('lunge')
    expect(matchIssue({ title: 'Overhead Preparation Consistency' }).key).toBe('elbow')
    expect(matchIssue({ title: 'Compact Mid-Court Preparation' }).key).toBe('drive')
    expect(matchIssue({ title: 'Compact Mid-Drive Resets' }).key).toBe('drive')
    expect(matchIssue({ title: 'Serve variety' })).toBe(null)
    expect(matchIssue(null)).toBe(null)
  })
  it('gives the same answer when called twice (no regex state)', () => {
    const f = { title: 'Immediate Base Recovery', why: 'failed to recover to base', how: 'push back to base' }
    expect(matchIssue(f).key).toBe(matchIssue(f).key)
  })
  it('maps real drill names', () => {
    expect(matchDrill({ name: 'Hit and Recover Shadow Footwork' })).toBe('shadow_footwork')
    expect(matchDrill({ name: 'Low Feeding with Deep Lunge' })).toBe('multi_lunge')
    expect(matchDrill({ name: 'Low Multi-Shuttle Lunge Drill' })).toBe('multi_lunge')
    expect(matchDrill({ name: 'Off-Base Hit & Recovery Shadows' })).toBe('shadow_footwork')
    expect(matchDrill({ name: 'Yoga' })).toBe(null)
  })
})

describe('the player own examples', () => {
  const shots = [
    shot('a', 30, { off_base: true, recovered: false }),
    shot('a', 10, { off_base: true, recovered: true, late_recovery: false }),
    shot('a', 20, { off_base: false, recovered: true }),
    shot('a', 40, { height: 'low', lunge: false }),
    shot('a', 50, { height: 'overhead', elbow_up: false }),
    shot('b', 5,  { off_base: true, recovered: false }),
    { tag_id: 'a', t_s: 60 },
  ]
  it('only this player, only the measured mistake, in time order', () => {
    const r = examplesFor(shots, 'a', ISSUES.recovery)
    expect(r.mistakes.map(s => s.t_s)).toEqual([30]); expect(r.rights.map(s => s.t_s)).toEqual([10])
    expect(examplesFor(shots, 'a', ISSUES.lunge).mistakes).toHaveLength(1)
    expect(examplesFor(shots, 'a', ISSUES.elbow).mistakes).toHaveLength(1)
    expect(examplesFor(shots, 'a', ISSUES.drive).mistakes).toHaveLength(0)
    expect(examplesFor(shots, 'a', null).mistakes).toHaveLength(0)
    expect(examplesFor(null, 'a', ISSUES.lunge).mistakes).toHaveLength(0)
  })
  it('clip windows are about 5 s and never negative', () => {
    expect(clipWindow(ISSUES.recovery, 10)).toEqual({ start: 9, end: 14 })
    expect(clipWindow(ISSUES.lunge, 1)).toEqual({ start: 0, end: 3.5 })
    expect(clipWindow(ISSUES.elbow, 100, 101).end).toBe(101)
  })
})

describe('repeat status and stamina', () => {
  it('says improving / repeated / worse / ok from the measured rate only', () => {
    expect(repeatStatus(ISSUES.recovery, { recovery_pct: 60 }, { recovery_pct: 40 }).state).toBe('improving')
    expect(repeatStatus(ISSUES.recovery, { recovery_pct: 42 }, { recovery_pct: 40 }).state).toBe('repeated')
    expect(repeatStatus(ISSUES.recovery, { recovery_pct: 24 }, { recovery_pct: 67 }).state).toBe('worse')
    expect(repeatStatus(ISSUES.elbow, { elbow_up_pct: 95 }, { elbow_up_pct: 96 }).state).toBe('ok')
    expect(repeatStatus(ISSUES.recovery, { recovery_pct: 24 }, null)).toBe(null)
    expect(repeatStatus(ISSUES.drive, { recovery_pct: 24 }, { recovery_pct: 24 })).toBe(null)
    expect(repeatStatus(null, {}, {})).toBe(null)
  })
  it('detects a fade only with enough strokes', () => {
    const mk = (n, okFirst, okSecond) => Array.from({ length: n }, (_, i) =>
      shot('a', i, { off_base: true, recovered: i < n / 2 ? i < okFirst : i - n / 2 < okSecond }))
    expect(staminaCheck(mk(8, 4, 0), 'a')).toBe(null)
    expect(staminaCheck(mk(20, 8, 2), 'a')).toMatchObject({ first: 80, second: 20, drop: 60, state: 'fade', n: 20 })
    expect(staminaCheck(mk(20, 5, 5), 'a').state).toBe('steady')
    expect(staminaCheck(mk(20, 2, 8), 'a').state).toBe('strong_finish')
  })
})

describe('form score, levels and badges', () => {
  const pt = (k) => ({ at: '2026-11-01', kpis: k })
  it('averages the technique rates and needs at least two', () => {
    expect(formScore({ recovery_pct: 24, elbow_up_pct: 100, lunge_pct: 33 })).toBe(52)
    expect(formScore({ recovery_pct: 24 })).toBe(null)
    expect(formScore(null)).toBe(null)
  })
  it('levels', () => {
    expect(levelFor(52).name).toBe('Club Player'); expect(levelFor(52).toNext).toBe(8)
    expect(levelFor(95).next).toBe(null); expect(levelFor(null)).toBe(null)
  })
  it('badges come only from real matches', () => {
    expect(badges([]).filter(b => b.earned)).toHaveLength(0)
    const pts = [pt({ recovery_pct: 30, elbow_up_pct: 50, lunge_pct: 30 }), pt({ recovery_pct: 40, elbow_up_pct: 60, lunge_pct: 40 }),
      pt({ recovery_pct: 55, elbow_up_pct: 95, lunge_pct: 65, overhead: 8 })]
    const got = badges(pts).filter(b => b.earned).map(b => b.id)
    expect(got).toEqual(expect.arrayContaining(['first', 'regular', 'base50', 'lunge60', 'elbow90', 'rising', 'best']))
    expect(got).not.toContain('base70'); expect(got).not.toContain('devoted')
    expect(risingStreak(pts)).toBe(2)
    expect(nextBadge(pts).id).toBe('base70')
  })
  it('high elbow badge needs 5 overheads', () => {
    expect(badges([pt({ recovery_pct: 30, elbow_up_pct: 100, overhead: 2 })]).find(b => b.id === 'elbow90').earned).toBe(false)
  })
})
