// AI Match Analysis — the MOVEMENT LIBRARY and the logic that ties it to measured data.
//
//  • MOVES: reference movements and drills as keyframed poses for the animated coach figure
//    (CoachFigure.vue). Each technique has a ✓ correct and a ✗ common-mistake version so a player can
//    SEE the difference. New movements are added here (one entry) and picked up by keyword matching.
//  • Issue helpers: map a coach focus area to a measured issue, find the player's OWN strokes that
//    show it (for the "watch my mistake" clips), and say whether it was corrected since last match.
//  • staminaCheck: first half vs second half of the match, from the same measured strokes.
// Nothing here estimates: every number comes from analysis_shots.technique / kpis.

// ── Skeleton ───────────────────────────────────────────────────────────────────────────────────
// Angles in degrees, measured from "straight down", positive = towards the net (the way she faces).
// arm: [upper-arm angle, elbow bend]   leg: [thigh angle, knee bend]   air: lift off the floor.
const LEN = { torso: 40, uArm: 19, fArm: 18, thigh: 28, shin: 28, racket: 20, head: 12 }
const rad = (d) => (d * Math.PI) / 180
const seg = (p, ang, len) => ({ x: p.x + Math.sin(rad(ang)) * len, y: p.y + Math.cos(rad(ang)) * len })

export const READY = { x: 0, lean: 8, air: 0, face: 1, armR: [45, 75], armL: [35, 60], legF: [16, 24], legB: [-12, 14] }
const P = (o = {}) => ({ ...READY, ...o })

// Forward kinematics → joint positions in the figure's viewBox (240 × 190, floor at y = 165).
export function fk(pose, ground = 165, cx = 120) {
  const o = { x: 0, y: 0 }
  const kneeF = seg(o, pose.legF[0], LEN.thigh), footF = seg(kneeF, pose.legF[0] - pose.legF[1], LEN.shin)
  const kneeB = seg(o, pose.legB[0], LEN.thigh), footB = seg(kneeB, pose.legB[0] - pose.legB[1], LEN.shin)
  const hip = { x: cx + pose.x, y: ground - Math.max(footF.y, footB.y) - (pose.air || 0) }
  const f = pose.face < 0 ? -1 : 1
  const at = (p) => ({ x: hip.x + f * p.x, y: hip.y + p.y })
  const neck = { x: Math.sin(rad(pose.lean)) * LEN.torso, y: -Math.cos(rad(pose.lean)) * LEN.torso }
  const head = { x: neck.x + Math.sin(rad(pose.lean)) * LEN.head, y: neck.y - Math.cos(rad(pose.lean)) * LEN.head }
  const elbowR = seg(neck, pose.armR[0], LEN.uArm), handR = seg(elbowR, pose.armR[0] + pose.armR[1], LEN.fArm)
  const tipR = seg(handR, pose.armR[0] + pose.armR[1], LEN.racket)
  const elbowL = seg(neck, pose.armL[0], LEN.uArm), handL = seg(elbowL, pose.armL[0] + pose.armL[1], LEN.fArm)
  return {
    face: f, hip, neck: at(neck), head: at(head),
    kneeF: at(kneeF), footF: at(footF), kneeB: at(kneeB), footB: at(footB),
    elbowR: at(elbowR), handR: at(handR), tipR: at(tipR), elbowL: at(elbowL), handL: at(handL),
  }
}

const lerp = (a, b, u) => a + (b - a) * u
const ease = (u) => (u < 0.5 ? 2 * u * u : 1 - Math.pow(-2 * u + 2, 2) / 2)
function mix(a, b, u) {
  const pair = (k) => [lerp(a[k][0], b[k][0], u), lerp(a[k][1], b[k][1], u)]
  return { x: lerp(a.x, b.x, u), lean: lerp(a.lean, b.lean, u), air: lerp(a.air || 0, b.air || 0, u),
    face: u < 0.5 ? a.face : b.face, armR: pair('armR'), armL: pair('armL'), legF: pair('legF'), legB: pair('legB') }
}

export const moveDuration = (move) => move.frames.reduce((s, f) => s + f.ms, 0)

// Pose + cue at time t (ms). Each frame glides to the next over its `ms`; `cut` holds, then snaps.
export function samplePose(move, tMs) {
  const total = moveDuration(move)
  let t = ((tMs % total) + total) % total
  for (let i = 0; i < move.frames.length; i++) {
    const fr = move.frames[i]
    if (t < fr.ms) {
      const next = move.frames[(i + 1) % move.frames.length]
      return { pose: fr.cut ? fr.p : mix(fr.p, next.p, ease(t / fr.ms)), cue: fr.cue, index: i }
    }
    t -= fr.ms
  }
  return { pose: move.frames[0].p, cue: move.frames[0].cue, index: 0 }
}

// ── Poses ──────────────────────────────────────────────────────────────────────────────────────
const HIT_WIDE   = P({ x: 40, lean: 14, armR: [95, 10], legF: [55, 55], legB: [-40, 8] })
const LUNGE      = P({ x: 42, lean: 10, armR: [80, 5], armL: [-70, 10], legF: [72, 78], legB: [-58, 6] })
const SPLIT_AIR  = P({ air: 9, legF: [22, 20], legB: [-22, 20] })
const SPLIT_LAND = P({ lean: 12, legF: [26, 45], legB: [-26, 45] })
const OH_PREP    = P({ lean: -8, armR: [240, -60], armL: [150, 10], legF: [20, 15], legB: [-25, 30] })
const OH_HIT     = P({ lean: 6, air: 4, armR: [186, 0], armL: [60, 60] })
const OH_FOLLOW  = P({ lean: 16, armR: [70, 25], armL: [20, 60] })
const DRIVE_UP   = P({ armR: [70, 95] })
const DRIVE_HIT  = P({ armR: [95, 15], lean: 12 })

// ── The library ────────────────────────────────────────────────────────────────────────────────
// kind: 'good' (correct technique) · 'bad' (the common mistake) · 'drill'
export const MOVES = {
  recover_good: { title: 'Hit, then straight back to base', kind: 'good', base: true, frames: [
    { p: READY, ms: 500, cue: 'Ready at base' },
    { p: HIT_WIDE, ms: 450, cue: 'Play the shot' },
    { p: P({ x: 28, lean: 2, armR: [50, 70], legF: [30, 45], legB: [-20, 35] }), ms: 400, cue: 'Push off the front foot — straight away' },
    { p: P({ x: 8, legF: [20, 35], legB: [-18, 30] }), ms: 300, cue: 'Back to base…' },
    { p: SPLIT_AIR, ms: 220, cue: '…small hop (split-step)' },
    { p: SPLIT_LAND, ms: 700, cue: 'Ready for the next shot ✓' },
  ] },
  recover_bad: { title: 'Hit and watch', kind: 'bad', base: true, frames: [
    { p: READY, ms: 500, cue: 'Ready at base' },
    { p: HIT_WIDE, ms: 450, cue: 'Play the shot' },
    { p: P({ x: 38, lean: 0, armR: [20, 20], armL: [10, 10], legF: [8, 6], legB: [-8, 6] }), ms: 1400, cue: 'Stands and watches the shot ✗' },
    { p: P({ x: 38, lean: 0, armR: [20, 20], armL: [10, 10], legF: [8, 6], legB: [-8, 6] }), ms: 800, cut: true, cue: 'Base is empty — the next shot is a scramble' },
  ] },
  lunge_good: { title: 'Deep lunge to a low shuttle', kind: 'good', frames: [
    { p: READY, ms: 450, cue: 'Ready' },
    { p: P({ x: 22, armR: [70, 40], legF: [40, 30], legB: [-25, 10] }), ms: 300, cue: 'Big step in, heel first' },
    { p: LUNGE, ms: 750, cue: 'Front knee bent, back straight, arm reaches ✓' },
    { p: P({ x: 22, legF: [35, 45], legB: [-20, 25] }), ms: 400, cue: 'Push back off the front heel' },
  ] },
  lunge_bad: { title: 'Bending from the waist', kind: 'bad', frames: [
    { p: READY, ms: 450, cue: 'Ready' },
    { p: P({ x: 14 }), ms: 300, cue: 'Small step…' },
    { p: P({ x: 22, lean: 62, armR: [60, 5], armL: [20, 10], legF: [14, 4], legB: [-12, 4] }), ms: 1300, cue: 'Bends at the waist, legs straight ✗' },
    { p: P({ x: 22, lean: 62, armR: [60, 5], armL: [20, 10], legF: [14, 4], legB: [-12, 4] }), ms: 700, cut: true, cue: 'Slow to get back up — and hard on the back' },
  ] },
  elbow_good: { title: 'Overhead with a high elbow', kind: 'good', frames: [
    { p: READY, ms: 400, cue: 'Ready' },
    { p: OH_PREP, ms: 450, cue: 'Turn side-on, elbow up and back' },
    { p: OH_HIT, ms: 220, cue: 'Hit high — arm straight above the shoulder ✓' },
    { p: OH_FOLLOW, ms: 450, cue: 'Follow through across the body' },
  ] },
  elbow_bad: { title: 'Overhead with a low elbow', kind: 'bad', frames: [
    { p: READY, ms: 400, cue: 'Ready' },
    { p: P({ lean: 0, armR: [-50, 100] }), ms: 450, cue: 'Elbow stays low' },
    { p: P({ lean: 4, armR: [80, 35] }), ms: 300, cue: 'Pushes the shuttle from below the shoulder ✗' },
    { p: P({ lean: 4, armR: [80, 35] }), ms: 900, cut: true, cue: 'Less power, flatter shot' },
  ] },
  drive_good: { title: 'Compact drive', kind: 'good', frames: [
    { p: DRIVE_UP, ms: 300, cue: 'Racket up in front of the chest' },
    { p: P({ armR: [60, 110] }), ms: 150, cue: 'Tiny backswing' },
    { p: DRIVE_HIT, ms: 150, cue: 'Short punch from the forearm ✓' },
    { p: DRIVE_UP, ms: 500, cue: 'Racket straight back up' },
  ] },
  drive_bad: { title: 'Big swing on a drive', kind: 'bad', frames: [
    { p: P({ armR: [20, 20] }), ms: 350, cue: 'Racket hanging low' },
    { p: P({ lean: -5, armR: [-70, 60] }), ms: 450, cue: 'Big backswing' },
    { p: P({ armR: [100, 10], lean: 14 }), ms: 300, cue: 'Late contact ✗' },
    { p: P({ armR: [20, 20] }), ms: 700, cut: true, cue: 'Not ready for the reply' },
  ] },

  // ── Drills ──
  shadow_footwork: { title: 'Shadow footwork: hit and recover', kind: 'drill', base: true, frames: [
    { p: SPLIT_LAND, ms: 350, cue: 'Start at base' },
    { p: LUNGE, ms: 500, cue: 'Front corner — lunge and “hit”' },
    { p: P({ x: 10, legF: [20, 35], legB: [-18, 30] }), ms: 380, cue: 'Push straight back' },
    { p: SPLIT_AIR, ms: 200, cue: 'Split-step at base' },
    { p: P({ ...OH_PREP, x: -42 }), ms: 480, cue: 'Back corner — elbow up' },
    { p: P({ ...OH_HIT, x: -42 }), ms: 220, cue: 'Overhead “hit”' },
    { p: P({ x: -12, legF: [20, 35], legB: [-18, 30] }), ms: 380, cue: 'Back to base again' },
    { p: SPLIT_AIR, ms: 200, cue: 'Split-step — repeat' },
  ] },
  multi_lunge: { title: 'Repeated lunges', kind: 'drill', frames: [
    { p: P({ x: 10 }), ms: 300, cue: 'Start one step back' },
    { p: LUNGE, ms: 500, cue: 'Lunge — heel first, knee bent' },
    { p: P({ x: 14, legF: [30, 40], legB: [-18, 25] }), ms: 380, cue: 'Push back' },
    { p: LUNGE, ms: 500, cue: 'And again — stay low' },
    { p: P({ x: 14, legF: [30, 40], legB: [-18, 25] }), ms: 380, cue: 'Same leg strength every rep' },
  ] },
  overhead_shadow: { title: 'Overhead shadow swings', kind: 'drill', frames: [
    { p: OH_PREP, ms: 420, cue: 'Elbow up and back' },
    { p: OH_HIT, ms: 220, cue: 'Reach high' },
    { p: OH_FOLLOW, ms: 380, cue: 'Follow through' },
    { p: READY, ms: 300, cue: 'Reset — 10 in a row' },
  ] },
  drive_wall: { title: 'Fast drives against a wall', kind: 'drill', frames: [
    { p: DRIVE_UP, ms: 180, cue: 'Racket up' },
    { p: DRIVE_HIT, ms: 140, cue: 'Punch' },
    { p: DRIVE_UP, ms: 180, cue: 'Up again' },
    { p: DRIVE_HIT, ms: 140, cue: 'Punch — keep it short and quick' },
  ] },
  split_step: { title: 'Split-step timing', kind: 'drill', base: true, frames: [
    { p: READY, ms: 350, cue: 'Watch the hitter' },
    { p: SPLIT_AIR, ms: 200, cue: 'Small hop as they hit' },
    { p: SPLIT_LAND, ms: 450, cue: 'Land wide and low' },
    { p: P({ x: 30, legF: [45, 35], legB: [-30, 10] }), ms: 350, cue: 'Explode to the shuttle' },
  ] },
  skipping: { title: 'Skipping intervals', kind: 'drill', frames: [
    { p: P({ lean: 2, armR: [25, 70], armL: [25, 70], legF: [4, 6], legB: [-4, 6] }), ms: 170, cue: 'Light, quick skips' },
    { p: P({ lean: 2, air: 10, armR: [35, 80], armL: [35, 80], legF: [6, 14], legB: [-2, 14] }), ms: 170, cue: 'Stay on your toes' },
    { p: P({ lean: 2, armR: [25, 70], armL: [25, 70], legF: [4, 6], legB: [-4, 6] }), ms: 170, cue: 'Breathe steadily' },
    { p: P({ lean: 2, air: 10, armR: [35, 80], armL: [35, 80], legF: [6, 14], legB: [-2, 14] }), ms: 170, cue: '30 s on, 30 s off' },
  ] },
  shuttle_runs: { title: 'Line-to-line sprints', kind: 'drill', frames: [
    { p: P({ x: 40, lean: 40, armR: [40, 5], legF: [50, 60], legB: [-30, 20] }), ms: 300, cue: 'Touch the line' },
    { p: P({ x: 20, lean: 20, face: -1, armR: [60, 80], armL: [-30, 80], legF: [45, 50], legB: [-35, 60] }), ms: 420, cue: 'Sprint across' },
    { p: P({ x: -40, lean: 40, face: -1, armR: [40, 5], legF: [50, 60], legB: [-30, 20] }), ms: 300, cue: 'Touch the other line' },
    { p: P({ x: -20, lean: 20, armR: [60, 80], armL: [-30, 80], legF: [45, 50], legB: [-35, 60] }), ms: 420, cue: 'And back — full speed' },
  ] },
}

// ── Issues: a coach focus area → something we actually measured ────────────────────────────────
export const ISSUES = {
  recovery: { key: 'recovery', kpi: 'recovery_pct', good: 'recover_good', bad: 'recover_bad', drill: 'shadow_footwork',
    label: 'Getting back to base', words: /recover|base|split|watch(ing)? (your|the) shot/gi,
    mistake: (t) => t?.off_base === true && t?.recovered === false,
    right:   (t) => t?.off_base === true && t?.recovered === true && !t?.late_recovery,
    seen: 'you stayed where you hit from', window: [1, 4] },
  lunge: { key: 'lunge', kpi: 'lunge_pct', good: 'lunge_good', bad: 'lunge_bad', drill: 'multi_lunge',
    label: 'Lunging on low shots', words: /lung|low (shot|ball|stroke|return|shuttle)|forecourt|\bnet\b/gi,
    mistake: (t) => t?.height === 'low' && t?.lunge === false,
    right:   (t) => t?.height === 'low' && t?.lunge === true,
    seen: 'you reached down without bending the front knee', window: [2.5, 2.5] },
  elbow: { key: 'elbow', kpi: 'elbow_up_pct', good: 'elbow_good', bad: 'elbow_bad', drill: 'overhead_shadow',
    label: 'High elbow on overheads', words: /elbow|overhead|rear[- ]court|clear|smash/gi,
    mistake: (t) => t?.height === 'overhead' && t?.elbow_up === false,
    right:   (t) => t?.height === 'overhead' && t?.elbow_up === true,
    seen: 'your elbow was below your shoulder at contact', window: [2.5, 2.5] },
  drive: { key: 'drive', kpi: null, good: 'drive_good', bad: 'drive_bad', drill: 'drive_wall',
    label: 'Compact mid-court drives', words: /drive|mid-?court|compact|backswing|racket (head )?up|reset/gi,
    mistake: () => false, right: () => false, seen: '', window: [2.5, 2.5] },
}

const hits = (re, s) => (String(s || '').match(re) || []).length

// Which measured issue is this focus area about? Title words count triple. null when nothing fits.
export function matchIssue(focus) {
  let best = null, bestScore = 0
  for (const is of Object.values(ISSUES)) {
    const score = hits(is.words, focus?.title) * 3 + hits(is.words, focus?.why) + hits(is.words, focus?.how)
    if (score > bestScore) { best = is; bestScore = score }
  }
  return best
}

const DRILL_WORDS = [
  ['multi_lunge',     /lung|low feed|forecourt|\bnet\b/gi],
  ['shadow_footwork', /shadow|recover|footwork|corner|base/gi],
  ['overhead_shadow', /overhead|elbow|clear|smash|rear/gi],
  ['drive_wall',      /drive|wall|compact|flat|mid-?court/gi],
  ['split_step',      /split/gi],
  ['skipping',        /skip|rope|stamina|endurance/gi],
  ['shuttle_runs',    /sprint|shuttle run|interval|line/gi],
]
// Which library drill animates this coach drill? Name counts triple. null when nothing fits.
export function matchDrill(drill) {
  let best = null, bestScore = 0
  for (const [id, re] of DRILL_WORDS) {
    const score = hits(re, drill?.name) * 3 + hits(re, drill?.how)
    if (score > bestScore) { best = id; bestScore = score }
  }
  return best
}

// The player's own strokes for an issue: mistakes (to learn from) and ones done right (to copy).
export function examplesFor(shots, tagId, issue) {
  const mine = (shots || []).filter(s => s.tag_id === tagId && s.technique)
  const pick = (fn) => mine.filter(s => fn(s.technique)).sort((a, b) => Number(a.t_s) - Number(b.t_s))
  return { mistakes: issue ? pick(issue.mistake) : [], rights: issue ? pick(issue.right) : [] }
}

// Seconds of video to show around a stroke (≈5 s).
export function clipWindow(issue, tS, duration = Infinity) {
  const [before, after] = issue?.window || [2.5, 2.5]
  const start = Math.max(0, Number(tS) - before)
  return { start, end: Math.min(duration, Number(tS) + after) }
}

// Has this issue been corrected since the previous analysed match? Uses the measured rate only.
export function repeatStatus(issue, kpis, prevKpis) {
  const k = issue?.kpi
  const cur = Number(kpis?.[k]), prev = Number(prevKpis?.[k])
  if (!k || !Number.isFinite(cur) || !Number.isFinite(prev)) return null
  const diff = Math.round(cur - prev)
  if (diff >= 5) return { state: 'improving', diff, cur, prev }
  if (cur >= 70) return { state: 'ok', diff, cur, prev }
  return { state: diff <= -5 ? 'worse' : 'repeated', diff, cur, prev }
}

// Stamina: did the player's recovery fade in the second half of THEIR strokes? Needs enough strokes
// away from base in each half to be meaningful; returns null otherwise.
export function staminaCheck(shots, tagId, minPerHalf = 6) {
  const mine = (shots || []).filter(s => s.tag_id === tagId && s.technique?.off_base === true)
    .sort((a, b) => Number(a.t_s) - Number(b.t_s))
  const half = Math.floor(mine.length / 2)
  if (half < minPerHalf) return null
  const rate = (arr) => Math.round((arr.filter(s => s.technique.recovered === true).length / arr.length) * 100)
  const first = rate(mine.slice(0, half)), second = rate(mine.slice(half))
  const drop = first - second
  return { first, second, drop, n: mine.length, state: drop >= 15 ? 'fade' : drop <= -15 ? 'strong_finish' : 'steady' }
}
