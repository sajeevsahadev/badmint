// AI Match Analysis — the motivating layer over the measured KPIs: a Form Score, a level, and badges.
// Everything is derived from real analysed matches (get_player_ai_progress().points) — nothing is awarded
// for free and nothing is estimated. The Form Score is simply the average of the technique rates we can
// measure today: back to base, high elbow on overheads, lunge on low shots.
import { hasValue } from './coachKpis'

export const FORM_KEYS = ['recovery_pct', 'elbow_up_pct', 'lunge_pct']

export function formScore(kpis) {
  const vals = FORM_KEYS.map(k => kpis?.[k]).filter(hasValue).map(Number)
  if (vals.length < 2) return null
  return Math.round(vals.reduce((a, b) => a + b, 0) / vals.length)
}

export const LEVELS = [
  { min: 0,  name: 'Rookie',     icon: '🌱' },
  { min: 40, name: 'Club Player', icon: '🏸' },
  { min: 60, name: 'Competitor', icon: '⚡' },
  { min: 75, name: 'Advanced',   icon: '🔥' },
  { min: 90, name: 'Elite',      icon: '👑' },
]
export function levelFor(score) {
  if (!hasValue(score)) return null
  let i = 0
  LEVELS.forEach((l, n) => { if (score >= l.min) i = n })
  const next = LEVELS[i + 1] || null
  return { ...LEVELS[i], index: i, next, toNext: next ? next.min - score : 0 }
}

// Form Score per analysed match, oldest first (matches without enough data are skipped).
export function scoreSeries(points) {
  return (points || []).map(p => ({ at: p.at, video_id: p.video_id, score: formScore(p.kpis) })).filter(p => p.score !== null)
}

// Consecutive most-recent matches in which the Form Score went up.
export function risingStreak(points) {
  const s = scoreSeries(points)
  let n = 0
  for (let i = s.length - 1; i > 0 && s[i].score > s[i - 1].score; i--) n++
  return n
}

const pct = (v, target) => hasValue(v) ? Math.max(0, Math.min(1, Number(v) / target)) : 0

// Badges: each returns { earned, progress 0..1 } from the real points.
export function badges(points) {
  const pts = points || []
  const k = pts[pts.length - 1]?.kpis || {}
  const s = scoreSeries(pts)
  const latest = s[s.length - 1]?.score
  const best = s.length ? Math.max(...s.map(x => x.score)) : null
  const streak = risingStreak(pts)
  const list = [
    { id: 'first',    icon: '🎬', name: 'First analysis',  hint: 'Analyse your first match',                         progress: Math.min(1, pts.length / 1) },
    { id: 'regular',  icon: '📅', name: 'Regular',         hint: 'Analyse 3 matches',                                progress: Math.min(1, pts.length / 3) },
    { id: 'devoted',  icon: '🏅', name: 'Dedicated',       hint: 'Analyse 10 matches',                               progress: Math.min(1, pts.length / 10) },
    { id: 'base50',   icon: '🏠', name: 'Home base',       hint: 'Get back to base on 50% of strokes',               progress: pct(k.recovery_pct, 50) },
    { id: 'base70',   icon: '🛡️', name: 'Court guardian',  hint: 'Get back to base on 70% of strokes',               progress: pct(k.recovery_pct, 70) },
    { id: 'lunge60',  icon: '🦵', name: 'Low and strong',  hint: 'Lunge on 60% of low shots',                        progress: pct(k.lunge_pct, 60) },
    { id: 'elbow90',  icon: '💪', name: 'High elbow',      hint: 'High elbow on 90% of overheads (5 or more played)', progress: Number(k.overhead) >= 5 ? pct(k.elbow_up_pct, 90) : Math.min(0.9, pct(k.elbow_up_pct, 90) * Math.min(1, Number(k.overhead || 0) / 5)) },
    { id: 'rising',   icon: '📈', name: 'On the rise',     hint: 'Improve your Form Score two matches in a row',     progress: Math.min(1, streak / 2) },
    { id: 'best',     icon: '⭐', name: 'Personal best',   hint: 'Set your best Form Score yet',                     progress: s.length >= 2 && latest === best && latest > Math.max(...s.slice(0, -1).map(x => x.score)) ? 1 : 0 },
  ]
  return list.map(b => ({ ...b, earned: b.progress >= 1 }))
}

// The closest badge not yet earned — the "next target".
export function nextBadge(points) {
  return badges(points).filter(b => !b.earned && b.id !== 'best').sort((a, b) => b.progress - a.progress)[0] || null
}
