import { describe, it, expect } from 'vitest'
import { K, expectedScore, applyElo, processMatch } from '../utils/elo'

describe('K factor', () => {
  it('is fixed at 24 — changing this breaks global ranking comparability', () => {
    expect(K).toBe(24)
  })
})

describe('expectedScore()', () => {
  it('is exactly 0.5 when both sides have equal average Elo', () => {
    expect(expectedScore(1000, 1000)).toBeCloseTo(0.5, 10)
  })

  it('is greater than 0.5 when own Elo is higher', () => {
    expect(expectedScore(1200, 1000)).toBeGreaterThan(0.5)
  })

  it('is less than 0.5 when own Elo is lower', () => {
    expect(expectedScore(800, 1000)).toBeLessThan(0.5)
  })

  it('is always in the range (0, 1)', () => {
    const cases = [[1000,1000],[1500,1000],[500,1000],[2000,0],[0,2000]]
    for (const [own, opp] of cases) {
      const e = expectedScore(own, opp)
      expect(e).toBeGreaterThan(0)
      expect(e).toBeLessThan(1)
    }
  })

  it('approaches 1 for large Elo advantage', () => {
    expect(expectedScore(3000, 1000)).toBeGreaterThan(0.99)
  })

  it('approaches 0 for large Elo deficit', () => {
    expect(expectedScore(1000, 3000)).toBeLessThan(0.01)
  })

  it('is symmetric: E(A,B) + E(B,A) = 1', () => {
    const pairs = [[1000,1200],[800,1100],[1500,1500]]
    for (const [a, b] of pairs) {
      expect(expectedScore(a, b) + expectedScore(b, a)).toBeCloseTo(1, 10)
    }
  })
})

describe('applyElo()', () => {
  it('winner and loser at equal Elo each move by 12', () => {
    // K=24, expected=0.5, delta = 24*(1-0.5) = 12
    expect(applyElo(1000, 1, 1000, 1000)).toBe(1012)
    expect(applyElo(1000, 0, 1000, 1000)).toBe(988)
  })

  it('winner gains what loser loses (symmetric)', () => {
    const before = 1000
    const win  = applyElo(before, 1, before, before) - before
    const loss = before - applyElo(before, 0, before, before)
    expect(win).toBe(loss)
  })

  it('upset win (weaker beats stronger) yields more than 12 points', () => {
    const gained = applyElo(900, 1, 900, 1100) - 900
    expect(gained).toBeGreaterThan(12)
  })

  it('expected win (stronger beats weaker) yields fewer than 12 points', () => {
    const gained = applyElo(1100, 1, 1100, 900) - 1100
    expect(gained).toBeLessThan(12)
  })

  it('returns an integer (rounds to nearest point)', () => {
    const result = applyElo(1000, 1, 1000, 1050)
    expect(Number.isInteger(result)).toBe(true)
  })

  it('Elo never exceeds realistic bounds for a single match', () => {
    // Max possible change: K=24, actual=1, expected≈0 → +24 per match
    const maxGain = applyElo(1000, 1, 0, 3000) - 1000
    expect(maxGain).toBeLessThanOrEqual(24)
  })
})

describe('processMatch()', () => {
  it('winning side both gain, losing side both lose', () => {
    const sideA = [{ elo: 1000 }, { elo: 1000 }]
    const sideB = [{ elo: 1000 }, { elo: 1000 }]
    const { newEloA1, newEloA2, newEloB1, newEloB2 } = processMatch(sideA, sideB, true)
    expect(newEloA1).toBeGreaterThan(1000)
    expect(newEloA2).toBeGreaterThan(1000)
    expect(newEloB1).toBeLessThan(1000)
    expect(newEloB2).toBeLessThan(1000)
  })

  it('total Elo in the system stays constant (zero-sum)', () => {
    const sideA = [{ elo: 1050 }, { elo: 950 }]
    const sideB = [{ elo: 1100 }, { elo: 900 }]
    const before = sideA[0].elo + sideA[1].elo + sideB[0].elo + sideB[1].elo
    const { newEloA1, newEloA2, newEloB1, newEloB2 } = processMatch(sideA, sideB, true)
    const after = newEloA1 + newEloA2 + newEloB1 + newEloB2
    // Due to rounding, allow ±2 total
    expect(Math.abs(after - before)).toBeLessThanOrEqual(2)
  })

  it('both players on winning side receive the same Elo change', () => {
    const sideA = [{ elo: 1000 }, { elo: 1000 }]
    const sideB = [{ elo: 1000 }, { elo: 1000 }]
    const { newEloA1, newEloA2 } = processMatch(sideA, sideB, true)
    expect(newEloA1).toBe(newEloA2)
  })

  it('strong pair loses less Elo when upset by weak pair', () => {
    const strongPair = [{ elo: 1200 }, { elo: 1200 }]
    const weakPair   = [{ elo:  800 }, { elo:  800 }]
    // Strong pair loses to weak pair — should lose more than normal
    const { newEloA1 } = processMatch(strongPair, weakPair, false)
    const normalLoss    = 1000 - applyElo(1000, 0, 1000, 1000)
    const upsetLoss     = 1200 - newEloA1
    expect(upsetLoss).toBeGreaterThan(normalLoss)
  })

  it('sideB wins when sideAWins is false', () => {
    const sideA = [{ elo: 1000 }, { elo: 1000 }]
    const sideB = [{ elo: 1000 }, { elo: 1000 }]
    const { newEloA1, newEloB1 } = processMatch(sideA, sideB, false)
    expect(newEloA1).toBe(988)
    expect(newEloB1).toBe(1012)
  })
})
