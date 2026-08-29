// App-level feature flags. Flip a flag to true to re-enable a feature app-wide.
//
// TOURNAMENTS_ENABLED — the tournament module (list, brackets, registration) is
// not fully built yet, so its entry points are hidden from members. Set to true
// once it's ready to ship. The /tournaments pages still exist; this only hides
// the links that surface them to users.
export const TOURNAMENTS_ENABLED = false
