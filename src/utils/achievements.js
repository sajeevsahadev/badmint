// Achievement definitions + evaluator — EloSmash-style badges, computed purely
// from a player's aggregate stats. No DB table: badges are derived on view from
// data PlayerProfile already has, so they show for anyone viewing the profile
// and work offline. (A future phase could persist "earned on" dates + push a
// notification the moment one unlocks — deliberately out of scope for v1.)
//
// ctx shape:
//   { games, wins, winPct, elo,
//     streaks:{ longestWin, current, type },
//     pointsDiff,
//     partnerships:[{ games, winPct }]  // full list, not just top 3
//   }

export const ACHIEVEMENTS = [
  // ── Milestones (volume of play) ─────────────────────────────────────────
  { id: 'first_win',  icon: '🎯', label: 'First Blood',   desc: 'Win your first match',
    category: 'Milestone', goal: c => ({ cur: Math.min(c.wins, 1),  goal: 1 }),   earned: c => c.wins >= 1 },
  { id: 'regular',    icon: '🏸', label: 'Regular Player', desc: 'Play 10 matches',
    category: 'Milestone', goal: c => ({ cur: Math.min(c.games, 10), goal: 10 }),  earned: c => c.games >= 10 },
  { id: 'veteran',    icon: '🎖️', label: 'Veteran',        desc: 'Play 50 matches',
    category: 'Milestone', goal: c => ({ cur: Math.min(c.games, 50), goal: 50 }),  earned: c => c.games >= 50 },
  { id: 'centurion',  icon: '💯', label: 'Centurion',      desc: 'Play 100 matches',
    category: 'Milestone', goal: c => ({ cur: Math.min(c.games, 100), goal: 100 }), earned: c => c.games >= 100 },

  // ── Performance (winning) ───────────────────────────────────────────────
  { id: 'on_fire',      icon: '🔥', label: 'On Fire',            desc: 'Win 3 matches in a row',
    category: 'Performance', goal: c => ({ cur: Math.min(c.streaks.longestWin, 3),  goal: 3 }),  earned: c => c.streaks.longestWin >= 3 },
  { id: 'unstoppable',  icon: '🚀', label: 'Unstoppable',        desc: 'Win 5 matches in a row',
    category: 'Performance', goal: c => ({ cur: Math.min(c.streaks.longestWin, 5),  goal: 5 }),  earned: c => c.streaks.longestWin >= 5 },
  { id: 'juggernaut',   icon: '⚡', label: 'Juggernaut',         desc: 'Win 10 matches in a row',
    category: 'Performance', goal: c => ({ cur: Math.min(c.streaks.longestWin, 10), goal: 10 }), earned: c => c.streaks.longestWin >= 10 },
  { id: 'consistent',   icon: '📈', label: 'Consistent Winner',  desc: '60%+ win rate over 10+ matches',
    category: 'Performance', earned: c => c.games >= 10 && c.winPct >= 60 },
  { id: 'dominator',    icon: '👑', label: 'Dominator',          desc: '75%+ win rate over 20+ matches',
    category: 'Performance', earned: c => c.games >= 20 && c.winPct >= 75 },

  // ── Skill (Elo tiers) ───────────────────────────────────────────────────
  { id: 'reach_gold',     icon: '🟡', label: 'Gold Standard',  desc: 'Reach 1250 Elo',
    category: 'Skill', goal: c => ({ cur: Math.min(c.elo, 1250), goal: 1250 }), earned: c => c.elo >= 1250 },
  { id: 'reach_platinum', icon: '🔵', label: 'Platinum Elite', desc: 'Reach 1450 Elo',
    category: 'Skill', goal: c => ({ cur: Math.min(c.elo, 1450), goal: 1450 }), earned: c => c.elo >= 1450 },
  { id: 'reach_diamond',  icon: '💎', label: 'Diamond Elite',  desc: 'Reach 1650 Elo',
    category: 'Skill', goal: c => ({ cur: Math.min(c.elo, 1650), goal: 1650 }), earned: c => c.elo >= 1650 },

  // ── Chemistry (partnerships) ────────────────────────────────────────────
  { id: 'dynamic_duo', icon: '🤝', label: 'Dynamic Duo', desc: '70%+ win rate with a partner (5+ games)',
    category: 'Chemistry', earned: c => (c.partnerships ?? []).some(p => p.games >= 5 && p.winPct >= 70) },
]

// Evaluate every achievement against a stats context. Returns the full list
// (so locked ones can render greyed with progress), earned-first.
export function evaluateAchievements(ctx) {
  const c = {
    games: 0, wins: 0, winPct: 0, elo: 1000,
    streaks: { longestWin: 0, current: 0, type: null },
    pointsDiff: 0, partnerships: [],
    ...ctx,
  }
  return ACHIEVEMENTS.map(a => {
    const earned = !!a.earned(c)
    const g = a.goal ? a.goal(c) : null
    return {
      id: a.id, icon: a.icon, label: a.label, desc: a.desc, category: a.category,
      earned,
      progress: !earned && g ? g : null,
    }
  }).sort((a, b) => (b.earned - a.earned))
}

// Count of earned achievements — for the "🏆 Achievements (6)" header.
export function earnedCount(list) {
  return list.filter(a => a.earned).length
}
