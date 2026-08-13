// Lightweight per-page SEO for the SPA — sets <title>, description, keywords,
// canonical, Open Graph + Twitter tags, and JSON-LD. Call applySeo() on each
// page (and again after async data loads).
const BASE = 'https://badminton360.app'

function upsertMeta(attr, key, content) {
  if (content == null || content === '') return
  let el = document.head.querySelector(`meta[${attr}="${key}"]`)
  if (!el) {
    el = document.createElement('meta')
    el.setAttribute(attr, key)
    document.head.appendChild(el)
  }
  el.setAttribute('content', content)
}

function upsertLink(rel, href) {
  let el = document.head.querySelector(`link[rel="${rel}"]`)
  if (!el) {
    el = document.createElement('link')
    el.setAttribute('rel', rel)
    document.head.appendChild(el)
  }
  el.setAttribute('href', href)
}

export function applySeo({ title, description, keywords, image, path, type = 'website' } = {}) {
  if (typeof document === 'undefined') return
  const pagePath = path || (typeof location !== 'undefined' ? location.pathname : '/')
  const url = BASE + pagePath
  const img = image || `${BASE}/icon-512.png`

  if (title) document.title = title
  upsertMeta('name', 'description', description)
  upsertMeta('name', 'keywords', keywords)
  upsertLink('canonical', url)

  upsertMeta('property', 'og:title', title)
  upsertMeta('property', 'og:description', description)
  upsertMeta('property', 'og:type', type)
  upsertMeta('property', 'og:url', url)
  upsertMeta('property', 'og:image', img)
  upsertMeta('property', 'og:site_name', 'Badminton 360')

  upsertMeta('name', 'twitter:card', 'summary_large_image')
  upsertMeta('name', 'twitter:title', title)
  upsertMeta('name', 'twitter:description', description)
  upsertMeta('name', 'twitter:image', img)
}

// Inject/replace a JSON-LD script by id. Pass obj=null to remove it.
export function setJsonLd(id, obj) {
  if (typeof document === 'undefined') return
  let el = document.getElementById(id)
  if (obj === null) { el?.remove(); return }
  if (!el) {
    el = document.createElement('script')
    el.type = 'application/ld+json'
    el.id = id
    document.head.appendChild(el)
  }
  el.textContent = JSON.stringify(obj)
}

export { BASE as SEO_BASE }
