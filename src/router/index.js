import { createRouter, createWebHistory } from 'vue-router'
import { supabase } from '../lib/supabase'

const routes = [
  { path: '/login',     component: () => import('../views/Login.vue'),        meta: { public: true } },
  { path: '/',          redirect: '/dashboard' },
  { path: '/dashboard', component: () => import('../views/Dashboard.vue') },
  { path: '/match',     component: () => import('../views/AddMatch.vue') },
  { path: '/players',   component: () => import('../views/Players.vue') },
  { path: '/compare',   component: () => import('../views/Compare.vue') },
  { path: '/guide',     component: () => import('../views/RankingGuide.vue') },
  { path: '/manage',    component: () => import('../views/Manage.vue') },
  { path: '/join',      component: () => import('../views/JoinClub.vue') },
]

const router = createRouter({ history: createWebHistory(), routes })

const REDIRECT_KEY = 'bm_after_login'

router.beforeEach(async (to) => {
  const { data } = await supabase.auth.getSession()
  const loggedIn = !!data.session

  // After OAuth login, honour any stored redirect destination
  if (loggedIn) {
    const next = sessionStorage.getItem(REDIRECT_KEY)
    if (next && next !== to.fullPath) {
      sessionStorage.removeItem(REDIRECT_KEY)
      return next
    }
  }

  if (!to.meta.public && !loggedIn) {
    sessionStorage.setItem(REDIRECT_KEY, to.fullPath)
    return '/login'
  }

  if (to.path === '/login' && loggedIn) return '/dashboard'
})

export default router
