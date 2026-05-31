import { createRouter, createWebHistory } from 'vue-router'
import { supabase } from '../lib/supabase'

const routes = [
  { path: '/login',     component: () => import('../views/Login.vue'),        meta: { public: true } },
  { path: '/explore',   component: () => import('../views/Explore.vue'),      meta: { public: true } },
  { path: '/',          redirect: '/dashboard' },
  { path: '/dashboard', component: () => import('../views/Dashboard.vue') },
  { path: '/matches',   component: () => import('../views/Matches.vue') },
  { path: '/match',     component: () => import('../views/AddMatch.vue') },
  { path: '/players',   component: () => import('../views/Players.vue') },
  { path: '/compare',   component: () => import('../views/Compare.vue') },
  { path: '/guide',     component: () => import('../views/RankingGuide.vue') },
  { path: '/manage',    component: () => import('../views/Manage.vue') },
  { path: '/join',      component: () => import('../views/JoinClub.vue') },
  { path: '/profile',   component: () => import('../views/Profile.vue') },
  { path: '/player/:id', component: () => import('../views/PlayerProfile.vue') },
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
  }

  if (!to.meta.public && !loggedIn) {
    // Only persist the destination for paths that carry meaningful state
    // (invite links, player profile deep-links). Regular paths like /dashboard
    // don't need to be returned to after login.
    if (to.path === '/join' || to.path.startsWith('/player')) {
      sessionStorage.setItem(REDIRECT_KEY, to.fullPath)
    }
    return '/login'
  }

  if (to.path === '/login' && loggedIn) return '/dashboard'
})

export default router
