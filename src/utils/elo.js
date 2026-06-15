/**
 * Elo calculation engine (mirrors the SQL record_match RPC).
 * K is locked at 24 for all clubs — cross-club Elo comparability.
 */
export const K = 24

/**
 * Expected score for a side given average Elo values.
 * @param {number} ownAvg  Average Elo of this side's two players
 * @param {number} oppAvg  Average Elo of the opposing side's two players
 * @returns {number} value in (0, 1)
 */
export function expectedScore(ownAvg, oppAvg) {
  return 1 / (1 + Math.pow(10, (oppAvg - ownAvg) / 400))
}

/**
 * Apply one Elo update for a single player.
 * @param {number} oldElo       Player's current Elo
 * @param {number} actual       1 (win) or 0 (loss)
 * @param {number} ownSideAvg  Average Elo of the player's side
 * @param {number} oppSideAvg  Average Elo of the opposing side
 * @returns {number} new Elo (rounded to integer)
 */
export function applyElo(oldElo, actual, ownSideAvg, oppSideAvg) {
  return Math.round(oldElo + K * (actual - expectedScore(ownSideAvg, oppSideAvg)))
}

/**
 * Process one complete match: four players, two sides.
 * Returns { newEloA1, newEloA2, newEloB1, newEloB2 }.
 * @param {{ elo: number }[]} sideA  Two players on side A
 * @param {{ elo: number }[]} sideB  Two players on side B
 * @param {boolean} sideAWins
 */
export function processMatch(sideA, sideB, sideAWins) {
  const avgA = (sideA[0].elo + sideA[1].elo) / 2
  const avgB = (sideB[0].elo + sideB[1].elo) / 2
  const actualA = sideAWins ? 1 : 0
  const actualB = sideAWins ? 0 : 1
  return {
    newEloA1: applyElo(sideA[0].elo, actualA, avgA, avgB),
    newEloA2: applyElo(sideA[1].elo, actualA, avgA, avgB),
    newEloB1: applyElo(sideB[0].elo, actualB, avgB, avgA),
    newEloB2: applyElo(sideB[1].elo, actualB, avgB, avgA),
  }
}
