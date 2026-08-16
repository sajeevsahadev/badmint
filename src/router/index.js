import { createRouter, createWebHistory } from 'vue-router'
import { supabase } from '../lib/supabase'

const routes = [
  { path: '/login',     component: () => import('../views/Login.vue'),        meta: { public: true } },
  { path: '/explore',   component: () => import('../views/Explore.vue'),      meta: { public: true } },
  { path: '/',          component: () => import('../views/Home.vue'),          meta: { public: true } },
  { path: '/poll/:id',  component: () => import('../views/PollView.vue'),  meta: { public: true } },
  { path: '/p/:code',   component: () => import('../views/ShareRedirect.vue'), meta: { public: true } },
  { path: '/dashboard',  component: () => import('../views/Dashboard.vue') },
  { path: '/scoreboard', component: () => import('../views/Scoreboard.vue') },
  { path: '/schedule',  component: () => import('../views/Schedule.vue') },
  { path: '/matches',   component: () => import('../views/Matches.vue') },
  { path: '/match',     component: () => import('../views/AddMatch.vue') },
  { path: '/players',   component: () => import('../views/Players.vue') },
  { path: '/compare',   component: () => import('../views/Compare.vue') },
  { path: '/guide',     component: () => import('../views/RankingGuide.vue') },
  { path: '/manage',    component: () => import('../views/Manage.vue') },
  { path: '/splits',    component: () => import('../views/PaySplits.vue') },
  { path: '/chat',      component: () => import('../views/Chat.vue'), meta: { fullscreen: true } },
  { path: '/join',      component: () => import('../views/JoinClub.vue') },
  { path: '/join/:clubId', component: () => import('../views/JoinClub.vue') },
  { path: '/profile',   component: () => import('../views/Profile.vue') },
  { path: '/settings/email',        component: () => import('../views/settings/EmailSettings.vue') },
  { path: '/settings/notifications', component: () => import('../views/settings/PushSettings.vue') },
  { path: '/settings/security',     component: () => import('../views/settings/SecuritySettings.vue') },
  { path: '/settings/appearance',   component: () => import('../views/settings/AppearanceSettings.vue') },
  { path: '/privacy',   component: () => import('../views/PrivacyPolicy.vue'), meta: { public: true } },
  { path: '/blog',       component: () => import('../views/Blog.vue'),     meta: { public: true } },
  { path: '/blog/:slug', component: () => import('../views/BlogPost.vue'), meta: { public: true } },
  { path: '/player/:id', component: () => import('../views/PlayerProfile.vue') },
  { path: '/club/:id',     component: () => import('../views/ClubProfile.vue') },
  { path: '/facility/:id',          component: () => import('../views/FacilityProfile.vue'),    meta: { public: true } },
  { path: '/tournaments',           component: () => import('../views/Tournaments.vue'),         meta: { public: true } },
  { path: '/tournament/:id',        component: () => import('../views/TournamentView.vue'),      meta: { public: true } },
  { path: '/tournament/:id/manage', component: () => import('../views/ManageTournament.vue') },
  { path: '/clubs',                 component: () => import('../views/MyClubs.vue') },
  { path: '/book',                  component: () => import('../views/BookCourt.vue') },
  { path: '/admin',                 component: () => import('../views/AdminPanel.vue') },
  { path: '/create-club',           component: () => import('../views/CreateClub.vue') },
  { path: '/live/:id',             component: () => import('../views/LiveMatch.vue'), meta: { fullscreen: true } },
]

const router = createRouter({ history: createWebHistory(), routes })

const REDIRECT_KEY = 'bm_after_login'

router.beforeEach(async (to) => {
  const { data } = await supabase.auth.getSession()
  const loggedIn = !!data.session

  // After Google OAuth the browser always lands on '/'.
  // Only check the stored redirect at that moment — NOT on every navigation,
  // which would intercept user-initiated button clicks.
  if (loggedIn && to.path === '/') {
    const next = sessionStorage.getItem(REDIRECT_KEY)
    if (next) {
      sessionStorage.removeItem(REDIRECT_KEY)
      return next
    }
    return '/dashboard'
  }

  if (!to.meta.public && !loggedIn) {
    // Only persist the destination for paths that carry meaningful state
    // (invite links, player profile deep-links). Regular paths like /dashboard
    // don't need to be returned to after login.
    if (to.path.startsWith('/join') || to.path.startsWith('/player') || to.path.startsWith('/poll')) {
      sessionStorage.setItem(REDIRECT_KEY, to.fullPath)
      // Coming in via a club-join or poll link → the person wants to JOIN, not
      // sit through the first-run setup wizard. Suppress the intro this once.
      if (to.path.startsWith('/join') || to.path.startsWith('/poll')) {
        sessionStorage.setItem('bm_skip_intro', '1')
      }
    }
    return '/login'
  }

  if (to.path === '/login' && loggedIn) return '/dashboard'

  // Guard /admin to app_admin role only
  if (to.path === '/admin' && loggedIn) {
    const { data: roles } = await supabase.rpc('get_my_roles')
    if (!(roles ?? []).some(r => r.role === 'app_admin')) return '/dashboard'
  }
})

export default router
