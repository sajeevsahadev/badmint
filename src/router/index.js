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
  { path: '/manage',    component: () => import('../views/Manage.vue') }
]

const router = createRouter({ history: createWebHistory(), routes })

router.beforeEach(async (to) => {
  const { data } = await supabase.auth.getSession()
  const loggedIn = !!data.session
  if (!to.meta.public && !loggedIn) return '/login'
  if (to.path === '/login' && loggedIn) return '/dashboard'
})

export default router
