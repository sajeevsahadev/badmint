// AI Match Analysis — Head Coach KPIs. One definition per KPI the pose engine measures (counted per
// stroke by generate-commentary → analysis_player_summary.kpis). `better` says which direction is good.
// KPIs that need shuttle tracking are listed as `locked` — shown as "coming next", never estimated.

export const KPI_DEFS = [
  { key: 'no_recovery',      label: "Didn't get back to base", short: 'No recovery', unit: '', better: 'down', group: 'footwork',
    hint: 'Strokes played away from base where you were not back before your next shot.' },
  { key: 'recovery_pct',     label: 'Back to base after a stroke', short: 'Recovery', unit: '%', better: 'up', group: 'footwork',
    hint: 'Of the strokes you played away from base, how often you got back in time.' },
  { key: 'late_recovery',    label: 'Slow to recover (over 1.2 s)', short: 'Slow recovery', unit: '', better: 'down', group: 'footwork',
    hint: 'You got back to base, but slower than 1.2 seconds.' },
  { key: 'avg_recovery_s',   label: 'Average recovery time', short: 'Recovery time', unit: 's', better: 'down', group: 'footwork',
    hint: 'How long it takes you to get back to base after a stroke away from it.' },
  { key: 'off_base',         label: 'Strokes away from base', short: 'Away from base', unit: '', better: null, group: 'footwork',
    hint: 'Strokes you had to move away from your base position to play.' },
  { key: 'elbow_low',        label: 'Overheads with a low elbow', short: 'Low elbow', unit: '', better: 'down', group: 'technique',
    hint: 'Overhead strokes hit with the elbow below the shoulder — less power and control.' },
  { key: 'elbow_up_pct',     label: 'High elbow on overheads', short: 'High elbow', unit: '%', better: 'up', group: 'technique',
    hint: 'Share of overhead strokes with the elbow above the shoulder at contact.' },
  { key: 'low_no_lunge',     label: 'Low shots without a lunge', short: 'No lunge', unit: '', better: 'down', group: 'technique',
    hint: 'Low strokes played standing tall instead of lunging into the shot.' },
  { key: 'lunge_pct',        label: 'Lunge on low shots', short: 'Lunge', unit: '%', better: 'up', group: 'technique',
    hint: 'Share of low strokes where you bent into a proper lunge.' },
  { key: 'fast_pct',         label: 'Fast racket swings', short: 'Fast swings', unit: '%', better: 'up', group: 'power',
    hint: 'Share of strokes with a fast, committed racket swing.' },
  { key: 'movement_per_min', label: 'Court coverage per minute', short: 'Coverage', unit: '', better: 'up', group: 'power',
    hint: 'Ground covered per minute, in body-heights — how active your feet are.' },
  { key: 'strokes',          label: 'Strokes detected', short: 'Strokes', unit: '', better: null, group: 'volume',
    hint: 'Strokes the engine could clearly see you play.' },
]

export const LOCKED_KPIS = [
  { key: 'missed_hits',  label: 'Missed hits' },
  { key: 'out_of_court', label: 'Shots hit out' },
  { key: 'net_errors',   label: 'Shots into the net' },
]

// The headline scoreboard — the coach's priority order.
export const HEADLINE_KEYS = ['no_recovery', 'recovery_pct', 'elbow_low', 'low_no_lunge', 'avg_recovery_s', 'fast_pct']
// Trend charts on the progress view (rates first: they compare fairly across matches of any length).
export const TREND_KEYS = ['recovery_pct', 'no_recovery', 'avg_recovery_s', 'elbow_up_pct', 'lunge_pct', 'fast_pct', 'movement_per_min', 'strokes']

export const kpiDef = (key) => KPI_DEFS.find(d => d.key === key)

export function hasValue(v) { return v !== null && v !== undefined && !Number.isNaN(Number(v)) }

export function fmtKpi(key, v) {
  if (!hasValue(v)) return '—'
  const d = kpiDef(key)
  const n = Number(v)
  if (d?.unit === '%') return `${Math.round(n)}%`
  if (d?.unit === 's') return `${n.toFixed(1)}s`
  return Number.isInteger(n) ? String(n) : n.toFixed(1)
}

// Change from the previous match. better: true = improved, false = slipped, null = neutral / no data.
export function kpiDelta(key, cur, prev) {
  if (!hasValue(cur) || !hasValue(prev)) return null
  const d = kpiDef(key)
  const diff = Math.round((Number(cur) - Number(prev)) * 100) / 100
  if (diff === 0) return { diff: 0, better: null, word: 'same as last time' }
  const better = d?.better ? (d.better === 'up' ? diff > 0 : diff < 0) : null
  const mag = d?.unit === '%' ? `${Math.abs(Math.round(diff))} pts` : d?.unit === 's' ? `${Math.abs(diff).toFixed(1)}s`
            : String(Math.abs(Number.isInteger(diff) ? diff : Number(diff.toFixed(1))))
  return { diff, better, word: `${diff > 0 ? '▲' : '▼'} ${mag}` }
}

// Points for one KPI from get_player_ai_progress().points, oldest first, skipping matches without it.
export function seriesFor(points, key) {
  return (points || []).filter(p => hasValue(p?.kpis?.[key]))
    .map(p => ({ at: p.at, value: Number(p.kpis[key]), video: p.video, video_id: p.video_id, strokes: p.kpis.strokes }))
}
