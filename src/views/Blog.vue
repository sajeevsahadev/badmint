<script setup>
import { ref, onMounted } from 'vue'
import { RouterLink } from 'vue-router'
import { supabase } from '../lib/supabase'
import { applySeo, setJsonLd } from '../lib/seo'

const posts   = ref([])
const loading = ref(true)

const fmtDate = ts => new Date(ts).toLocaleDateString('en', { day: 'numeric', month: 'short', year: 'numeric' })

onMounted(async () => {
  applySeo({
    title: 'Badminton Blog — tips, scoring & match tracking | Badminton 360',
    description: 'Badminton tips, scoring guides and match-tracking ideas for clubs and players. Learn to track scores, rank players with Elo, and run your badminton club better.',
    keywords: 'badminton, shuttle, badminton apps, badminton match tracking, badminton score tracking, badminton tips, badminton club',
    path: '/blog',
    type: 'website',
  })
  setJsonLd('ld-blog', {
    '@context': 'https://schema.org',
    '@type': 'Blog',
    name: 'Badminton 360 Blog',
    url: 'https://badminton360.app/blog',
    description: 'Badminton tips, scoring guides and match-tracking ideas for clubs and players.',
  })

  const { data } = await supabase
    .from('blog_posts')
    .select('slug, title, excerpt, cover_url, author, publish_at')
    .eq('published', true)
    .order('publish_at', { ascending: false })
  posts.value = data ?? []
  loading.value = false
})
</script>

<template>
  <div class="min-h-screen" style="background:#eef4ff;">
    <!-- Hero -->
    <header class="relative overflow-hidden text-white"
      style="background:linear-gradient(135deg,#0b1220 0%,#0f2a4a 55%,#0a5b74 100%);">
      <div class="absolute inset-0 opacity-20" aria-hidden="true"
        style="background-image:radial-gradient(circle at 20% 30%, #22d3ee55, transparent 40%), radial-gradient(circle at 80% 20%, #a855f755, transparent 40%);"></div>
      <div class="relative max-w-6xl mx-auto px-5 sm:px-8 pb-10 pt-[calc(env(safe-area-inset-top,0px)+3.25rem)] sm:pt-8">
        <RouterLink to="/" class="inline-flex items-center gap-1.5 text-sm text-white/70 hover:text-white transition mb-6">‹ Badminton 360</RouterLink>
        <img src="/icon-192.png" alt="Badminton 360" class="w-14 h-14 rounded-2xl mb-3 shadow-lg" />
        <h1 class="font-display text-3xl sm:text-4xl font-extrabold leading-tight">The Badminton 360 Blog</h1>
        <p class="text-white/70 mt-2 max-w-xl">Tips, scoring guides and smarter ways to track matches, rank players and run your club.</p>
      </div>
    </header>

    <main class="max-w-6xl mx-auto px-5 sm:px-8 py-8">
      <div v-if="loading" class="grid gap-5 sm:grid-cols-2 lg:grid-cols-3">
        <div v-for="i in 6" :key="i" class="h-64 shimmer rounded-2xl" />
      </div>

      <div v-else-if="!posts.length" class="card p-10 text-center">
        <div class="text-4xl mb-2">✍️</div>
        <p class="font-bold text-slate-700">No posts yet</p>
        <p class="text-sm text-slate-400">Check back soon for badminton tips and guides.</p>
      </div>

      <div v-else class="grid gap-5 sm:grid-cols-2 lg:grid-cols-3">
        <RouterLink v-for="p in posts" :key="p.slug" :to="`/blog/${p.slug}`"
          class="card overflow-hidden hover:-translate-y-0.5 hover:shadow-lg transition-all group">
          <div class="aspect-[16/9] bg-slate-100 overflow-hidden">
            <img v-if="p.cover_url" :src="p.cover_url" :alt="p.title" loading="lazy" decoding="async"
              class="w-full h-full object-cover group-hover:scale-[1.03] transition-transform duration-300" />
            <div v-else class="w-full h-full grid place-items-center text-4xl">🏸</div>
          </div>
          <div class="p-4">
            <p class="text-[11px] text-slate-400 mb-1">{{ fmtDate(p.publish_at) }} · {{ p.author }}</p>
            <h2 class="font-display font-bold text-slate-800 leading-snug group-hover:text-neon transition">{{ p.title }}</h2>
            <p v-if="p.excerpt" class="text-sm text-slate-500 mt-1.5 line-clamp-2">{{ p.excerpt }}</p>
            <span class="inline-block mt-3 text-xs font-semibold text-neon">Read more →</span>
          </div>
        </RouterLink>
      </div>

      <!-- Soft CTA -->
      <div class="card-neon p-6 text-center mt-8">
        <p class="font-display font-bold gradient-text text-lg">Track your own matches, free</p>
        <p class="text-sm text-slate-500 mt-1 mb-4">Elo rankings, score tracking, club chat and expense splitting — all in one free app.</p>
        <RouterLink to="/login" class="btn-primary inline-flex px-6 py-3">Start free →</RouterLink>
      </div>
    </main>
  </div>
</template>
