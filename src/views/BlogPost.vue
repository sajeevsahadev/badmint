<script setup>
import { ref, computed, onMounted, watch } from 'vue'
import { useRoute, RouterLink } from 'vue-router'
import { supabase } from '../lib/supabase'
import { applySeo, setJsonLd, SEO_BASE } from '../lib/seo'

const route   = useRoute()
const post    = ref(null)
const related = ref([])
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

  // Related reads — internal links on every post (live posts only)
  supabase
    .from('blog_posts')
    .select('slug, title, excerpt, cover_url')
    .eq('published', true)
    .neq('slug', route.params.slug)
    .lte('publish_at', new Date().toISOString())
    .order('publish_at', { ascending: false })
    .limit(4)
    .then(({ data: rel }) => { related.value = rel ?? [] })

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

// ── Share ───────────────────────────────────────────────────────────────
const copied = ref(false)
const canNativeShare = typeof navigator !== 'undefined' && !!navigator.share
const shareUrl = computed(() => post.value ? `${SEO_BASE}/blog/${post.value.slug}` : SEO_BASE)
async function nativeShare() {
  if (!navigator.share) return copyUrl()
  try { await navigator.share({ title: post.value?.title, text: post.value?.excerpt || '', url: shareUrl.value }) } catch { /* cancelled */ }
}
async function copyUrl() {
  try {
    await navigator.clipboard.writeText(shareUrl.value)
    copied.value = true; setTimeout(() => { copied.value = false }, 1800)
  } catch { /* clipboard blocked */ }
}
const shareLinks = computed(() => {
  const u = encodeURIComponent(shareUrl.value)
  const t = encodeURIComponent(post.value?.title || 'Badminton 360')
  return {
    whatsapp: `https://wa.me/?text=${t}%20${u}`,
    x:        `https://twitter.com/intent/tweet?text=${t}&url=${u}`,
    facebook: `https://www.facebook.com/sharer/sharer.php?u=${u}`,
    telegram: `https://t.me/share/url?url=${u}&text=${t}`,
    linkedin: `https://www.linkedin.com/sharing/share-offsite/?url=${u}`,
  }
})
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

          <!-- Share bar -->
          <div class="flex flex-wrap items-center gap-2 mb-5 pb-5 border-b border-slate-100">
            <button v-if="canNativeShare" class="btn-primary text-xs px-3 py-2 gap-1.5" @click="nativeShare">
              <svg viewBox="0 0 24 24" class="w-4 h-4" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="18" cy="5" r="3"/><circle cx="6" cy="12" r="3"/><circle cx="18" cy="19" r="3"/><path d="M8.6 13.5 15.4 17M15.4 7 8.6 10.5"/></svg>
              Share
            </button>
            <button class="btn-ghost text-xs px-3 py-2" @click="copyUrl">{{ copied ? '✅ Copied!' : '🔗 Copy link' }}</button>
            <span class="w-px h-5 bg-slate-200 mx-0.5" aria-hidden="true"></span>
            <a :href="shareLinks.whatsapp" target="_blank" rel="noopener" aria-label="Share on WhatsApp" class="w-9 h-9 rounded-full flex items-center justify-center text-white shrink-0 hover:opacity-90 active:scale-95 transition" style="background:#25D366">
              <svg viewBox="0 0 24 24" class="w-4 h-4" fill="currentColor"><path d="M17.5 14.4c-.3-.15-1.7-.83-2-.93-.26-.1-.46-.14-.65.15-.19.28-.74.92-.9 1.11-.17.19-.33.21-.62.07-.29-.15-1.23-.45-2.34-1.44-.86-.77-1.45-1.72-1.62-2-.17-.29-.02-.44.13-.59.13-.13.29-.33.43-.5.14-.17.19-.29.29-.48.1-.19.05-.36-.02-.5-.07-.15-.65-1.57-.9-2.15-.24-.57-.48-.49-.65-.5h-.56c-.19 0-.5.07-.77.36-.26.29-1 .98-1 2.38s1.03 2.76 1.17 2.95c.14.19 2.02 3.08 4.9 4.32.68.29 1.22.47 1.63.6.69.22 1.31.19 1.8.11.55-.08 1.7-.69 1.94-1.36.24-.67.24-1.24.17-1.36-.07-.12-.26-.19-.55-.33ZM12 2a10 10 0 0 0-8.55 15.15L2 22l4.98-1.3A10 10 0 1 0 12 2Z"/></svg>
            </a>
            <a :href="shareLinks.x" target="_blank" rel="noopener" aria-label="Share on X" class="w-9 h-9 rounded-full flex items-center justify-center text-white shrink-0 hover:opacity-90 active:scale-95 transition" style="background:#000">
              <svg viewBox="0 0 24 24" class="w-3.5 h-3.5" fill="currentColor"><path d="M18 2h3l-7.1 8.1L22.5 22H16l-5-6.6L5.2 22H2.1l7.6-8.7L1.5 2H8l4.6 6.1L18 2Zm-1.1 18h1.7L7.2 3.7H5.4L16.9 20Z"/></svg>
            </a>
            <a :href="shareLinks.facebook" target="_blank" rel="noopener" aria-label="Share on Facebook" class="w-9 h-9 rounded-full flex items-center justify-center text-white shrink-0 hover:opacity-90 active:scale-95 transition" style="background:#1877F2">
              <svg viewBox="0 0 24 24" class="w-4 h-4" fill="currentColor"><path d="M13 22v-8h2.7l.4-3.1H13V8.9c0-.9.25-1.5 1.55-1.5H16V4.6c-.29-.04-1.28-.12-2.44-.12-2.42 0-4.06 1.47-4.06 4.18v2.34H6.8V14H9.5v8H13Z"/></svg>
            </a>
            <a :href="shareLinks.telegram" target="_blank" rel="noopener" aria-label="Share on Telegram" class="w-9 h-9 rounded-full flex items-center justify-center text-white shrink-0 hover:opacity-90 active:scale-95 transition" style="background:#229ED9">
              <svg viewBox="0 0 24 24" class="w-4 h-4" fill="currentColor"><path d="M21.9 4.3 18.7 20c-.24 1.06-.87 1.32-1.76.82l-4.87-3.6-2.35 2.26c-.26.26-.48.48-.98.48l.35-4.96 9.03-8.16c.4-.35-.09-.55-.61-.2L6.75 12.6l-4.8-1.5c-1.04-.33-1.06-1.04.22-1.54L20.6 2.8c.87-.32 1.63.2 1.3 1.5Z"/></svg>
            </a>
            <a :href="shareLinks.linkedin" target="_blank" rel="noopener" aria-label="Share on LinkedIn" class="w-9 h-9 rounded-full flex items-center justify-center text-white shrink-0 hover:opacity-90 active:scale-95 transition" style="background:#0A66C2">
              <svg viewBox="0 0 24 24" class="w-4 h-4" fill="currentColor"><path d="M4.98 3.5A2.5 2.5 0 1 0 5 8.5a2.5 2.5 0 0 0 0-5ZM3 9h4v12H3V9Zm6 0h3.8v1.65h.05c.53-.95 1.83-1.95 3.77-1.95 4.03 0 4.78 2.5 4.78 5.75V21h-4v-5.35c0-1.28-.02-2.92-1.78-2.92-1.78 0-2.05 1.39-2.05 2.83V21H9V9Z"/></svg>
            </a>
          </div>

          <!-- Post body (trusted admin-authored HTML) -->
          <div class="blog-content" v-html="post.body"></div>

          <!-- CTA -->
          <div class="card-neon p-5 text-center mt-8">
            <p class="font-display font-bold gradient-text">Put this into practice — free</p>
            <p class="text-sm text-slate-500 mt-1 mb-3">Track scores, get automatic Elo rankings and run your club in one app.</p>
            <RouterLink to="/login" class="btn-primary inline-flex px-6 py-2.5">Start free →</RouterLink>
          </div>

          <!-- Related reads — internal links -->
          <div v-if="related.length" class="mt-10">
            <h2 class="font-display text-lg font-bold text-slate-800 mb-3">Related badminton reads</h2>
            <div class="grid sm:grid-cols-2 gap-3">
              <RouterLink v-for="r in related" :key="r.slug" :to="'/blog/' + r.slug"
                class="card p-4 flex gap-3 items-center hover:border-neon/40 transition-all active:scale-[0.99] no-underline">
                <img v-if="r.cover_url" :src="r.cover_url" :alt="r.title" class="w-16 h-16 rounded-lg object-cover shrink-0" loading="lazy" />
                <div class="min-w-0">
                  <p class="text-sm font-semibold text-slate-800 line-clamp-2">{{ r.title }}</p>
                  <p class="text-xs text-slate-400 line-clamp-1 mt-0.5">{{ r.excerpt }}</p>
                </div>
              </RouterLink>
            </div>
          </div>
        </div>

        <div class="text-center py-8">
          <RouterLink to="/blog" class="text-sm font-semibold text-neon">← More badminton reads</RouterLink>
        </div>
      </div>
    </article>
  </div>
</template>
