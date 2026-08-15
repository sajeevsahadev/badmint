<script setup>
import { ref, onMounted, watch } from 'vue'
import { useRoute, RouterLink } from 'vue-router'
import { supabase } from '../lib/supabase'
import { applySeo, setJsonLd, SEO_BASE } from '../lib/seo'

const route   = useRoute()
const post    = ref(null)
const loading = ref(true)
const notFound = ref(false)

const fmtDate = ts => new Date(ts).toLocaleDateString('en', { day: 'numeric', month: 'short', year: 'numeric' })

async function load() {
  loading.value = true; notFound.value = false; post.value = null
  const { data } = await supabase
    .from('blog_posts')
    .select('slug, title, excerpt, cover_url, body, meta_description, keywords, author, publish_at, updated_at')
    .eq('slug', route.params.slug)
    .eq('published', true)
    .maybeSingle()
  loading.value = false
  if (!data) { notFound.value = true; return }
  post.value = data

  applySeo({
    title: `${data.title} | Badminton 360`,
    description: data.meta_description || data.excerpt,
    keywords: data.keywords || 'badminton, shuttle, badminton apps, badminton match tracking, badminton score tracking',
    image: data.cover_url,
    path: `/blog/${data.slug}`,
    type: 'article',
  })
  setJsonLd('ld-article', {
    '@context': 'https://schema.org',
    '@type': 'BlogPosting',
    headline: data.title,
    description: data.meta_description || data.excerpt,
    image: data.cover_url ? [data.cover_url] : undefined,
    author: { '@type': 'Organization', name: data.author || 'Badminton 360' },
    publisher: { '@type': 'Organization', name: 'Badminton 360', logo: { '@type': 'ImageObject', url: `${SEO_BASE}/icon-512.png` } },
    datePublished: data.publish_at,
    dateModified: data.updated_at,
    mainEntityOfPage: `${SEO_BASE}/blog/${data.slug}`,
  })
}

onMounted(load)
watch(() => route.params.slug, load)
</script>

<template>
  <div class="min-h-screen" style="background:#eef4ff;">
    <div v-if="loading" class="max-w-2xl mx-auto px-5 py-10 space-y-4">
      <div class="h-8 w-2/3 shimmer rounded-lg" />
      <div class="h-64 shimmer rounded-2xl" />
      <div class="h-4 shimmer rounded" /><div class="h-4 w-5/6 shimmer rounded" />
    </div>

    <div v-else-if="notFound" class="max-w-2xl mx-auto px-5 py-20 text-center">
      <div class="text-5xl mb-3">🤔</div>
      <p class="font-bold text-slate-700 mb-2">Post not found</p>
      <RouterLink to="/blog" class="btn-primary inline-flex px-5 py-2.5">← Back to blog</RouterLink>
    </div>

    <article v-else-if="post">
      <!-- Cover (responsive fixed height so it always spans full width) -->
      <header class="relative">
        <div class="w-full h-44 sm:h-64 md:h-80 overflow-hidden bg-slate-900">
          <img v-if="post.cover_url" :src="post.cover_url" :alt="post.title" class="w-full h-full object-cover" />
        </div>
      </header>

      <div class="max-w-2xl mx-auto px-5 -mt-16 relative">
        <div class="card p-6 sm:p-8">
          <RouterLink to="/blog" class="inline-flex items-center gap-1.5 text-sm text-slate-400 hover:text-neon transition mb-4">‹ Blog</RouterLink>
          <p class="text-xs text-slate-400 mb-2">{{ fmtDate(post.publish_at) }} · {{ post.author }}</p>
          <h1 class="font-display text-2xl sm:text-3xl font-extrabold text-slate-800 leading-tight mb-4">{{ post.title }}</h1>
          <!-- Post body (trusted admin-authored HTML) -->
          <div class="blog-content" v-html="post.body"></div>

          <!-- CTA -->
          <div class="card-neon p-5 text-center mt-8">
            <p class="font-display font-bold gradient-text">Put this into practice — free</p>
            <p class="text-sm text-slate-500 mt-1 mb-3">Track scores, get automatic Elo rankings and run your club in one app.</p>
            <RouterLink to="/login" class="btn-primary inline-flex px-6 py-2.5">Start free →</RouterLink>
          </div>
        </div>

        <div class="text-center py-8">
          <RouterLink to="/blog" class="text-sm font-semibold text-neon">← More badminton reads</RouterLink>
        </div>
      </div>
    </article>
  </div>
</template>
