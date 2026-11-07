import { describe, it, expect } from 'vitest'
import { kpiDelta, fmtKpi, seriesFor, KPI_DEFS, HEADLINE_KEYS, TREND_KEYS } from '../lib/coachKpis'

describe('coach KPIs', () => {
  it('fewer missed recoveries is an improvement', () => {
    const d = kpiDelta('no_recovery', 7, 10)
    expect(d.better).toBe(true)
    expect(d.word).toBe('▼ 3')
  })
  it('a higher recovery rate is an improvement, a lower one is not', () => {
    expect(kpiDelta('recovery_pct', 80, 60).better).toBe(true)
    expect(kpiDelta('recovery_pct', 50, 60).better).toBe(false)
    expect(kpiDelta('recovery_pct', 80, 60).word).toBe('▲ 20 pts')
  })
  it('neutral KPIs and unchanged values have no verdict', () => {
    expect(kpiDelta('strokes', 120, 90).better).toBe(null)
    expect(kpiDelta('no_recovery', 5, 5)).toEqual({ diff: 0, better: null, word: 'same as last time' })
  })
  it('missing data gives no delta', () => {
    expect(kpiDelta('no_recovery', 5, null)).toBe(null)
    expect(kpiDelta('no_recovery', undefined, 3)).toBe(null)
  })
  it('formats by unit', () => {
    expect(fmtKpi('recovery_pct', 66.6)).toBe('67%')
    expect(fmtKpi('avg_recovery_s', 0.84)).toBe('0.8s')
    expect(fmtKpi('no_recovery', 9)).toBe('9')
    expect(fmtKpi('no_recovery', null)).toBe('—')
  })
  it('builds a series oldest-first, skipping matches without the KPI', () => {
    const pts = [{ at: '1', kpis: { no_recovery: 10, strokes: 50 } }, { at: '2', kpis: { strokes: 40 } }, { at: '3', kpis: { no_recovery: 7, strokes: 60 } }]
    expect(seriesFor(pts, 'no_recovery').map(p => p.value)).toEqual([10, 7])
  })
  it('every headline/trend key has a definition', () => {
    const keys = new Set(KPI_DEFS.map(d => d.key))
    for (const k of [...HEADLINE_KEYS, ...TREND_KEYS]) expect(keys.has(k)).toBe(true)
  })
})
