// Post-build prerender for public content pages (SEO + social share previews).
// Generates real static HTML for /blog and each /blog/<slug> into dist/, plus a
// fresh sitemap.xml. Vercel serves these files directly (filesystem is checked
// before the SPA rewrite), so crawlers and social scrapers get full <head> meta
// + article content without JS. The SPA still boots and takes over for users.
//
// SAFE BY DESIGN: additive files only; any failure is swallowed and the build
// still succeeds (exit 0).
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'fs'

const BASE = 'https://badminton360.app'

function loadEnv() {
  const env = { ...process.env }
  if (!env.VITE_SUPABASE_URL || !env.VITE_SUPABASE_ANON_KEY) {
    try {
      for (const line of readFileSync('.env', 'utf8').split(/\r?\n/)) {
        const m = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*)\s*$/)
        if (m) env[m[1]] = m[2].replace(/^["']|["']$/g, '')
      }
    } catch { /* no .env — rely on process.env */ }
  }
  return env
}

const escAttr = s => String(s ?? '').replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;')
const escHtml = s => String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')

function headBlock({ title, description, keywords, image, url, type = 'website', jsonLd }) {
  const img = image || `${BASE}/icon-512.png`
  const m = []
  m.push(`<meta name="description" content="${escAttr(description)}">`)
  if (keywords) m.push(`<meta name="keywords" content="${escAttr(keywords)}">`)
  m.push(`<link rel="canonical" href="${escAttr(url)}">`)
  m.push(`<meta property="og:title" content="${escAttr(title)}">`)
  m.push(`<meta property="og:description" content="${escAttr(description)}">`)
  m.push(`<meta property="og:type" content="${type}">`)
  m.push(`<meta property="og:url" content="${escAttr(url)}">`)
  m.push(`<meta property="og:image" content="${escAttr(img)}">`)
  m.push(`<meta property="og:site_name" content="Badminton 360">`)
  m.push(`<meta name="twitter:card" content="summary_large_image">`)
  m.push(`<meta name="twitter:title" content="${escAttr(title)}">`)
  m.push(`<meta name="twitter:description" content="${escAttr(description)}">`)
  m.push(`<meta name="twitter:image" content="${escAttr(img)}">`)
  if (jsonLd) m.push(`<script type="application/ld+json">${JSON.stringify(jsonLd)}</script>`)
  return m.join('\n    ')
}

// Take the built shell and swap in per-page <title>, meta and pre-rendered body.
function renderPage(shell, { title, head, appHtml }) {
  let html = shell
  // strip the tags we override so there are no duplicates
  html = html.replace(/<meta[^>]*(?:name|property)=["'](?:description|keywords|og:title|og:description|og:image|og:url|og:type|og:site_name|twitter:card|twitter:title|twitter:description|twitter:image)["'][^>]*>\s*/gi, '')
  html = html.replace(/<link[^>]*rel=["']canonical["'][^>]*>\s*/gi, '')
  html = html.replace(/<script[^>]*type=["']application\/ld\+json["'][^>]*>[\s\S]*?<\/script>\s*/gi, '')
  html = html.replace(/<title>[\s\S]*?<\/title>/i, `<title>${escHtml(title)}</title>`)
  html = html.replace(/<\/head>/i, `    ${head}\n  </head>`)
  // inject crawlable content into the mount node (Vue replaces it on mount)
  html = html.replace(/<div id="app">\s*<\/div>/i, `<div id="app">${appHtml}</div>`)
  return html
}

async function main() {
  const env = loadEnv()
  const URL = env.VITE_SUPABASE_URL, KEY = env.VITE_SUPABASE_ANON_KEY
  if (!URL || !KEY) { console.log('[prerender] no Supabase env — skipping'); return }
  if (!existsSync('dist/index.html')) { console.log('[prerender] no dist/index.html — skipping'); return }
  const shell = readFileSync('dist/index.html', 'utf8')

  // RLS (anon) already hides future-dated posts (publish_at > now), so only
  // currently-live posts are returned and prerendered.
  const res = await fetch(`${URL}/rest/v1/blog_posts?select=slug,title,excerpt,cover_url,body,meta_description,keywords,author,publish_at,updated_at&published=eq.true&order=publish_at.desc`, {
    headers: { apikey: KEY, Authorization: `Bearer ${KEY}` },
  })
  const posts = res.ok ? await res.json() : []
  console.log(`[prerender] ${posts.length} posts`)

  // /blog list
  const listItems = posts.map(p => `
      <article>
        ${p.cover_url ? `<img src="${escAttr(p.cover_url)}" alt="${escAttr(p.title)}" width="480" height="270" loading="lazy">` : ''}
        <h2><a href="/blog/${escAttr(p.slug)}">${escHtml(p.title)}</a></h2>
        <p>${escHtml(p.excerpt || '')}</p>
      </article>`).join('\n')
  const blogListHtml = `<main><h1>The Badminton 360 Blog</h1><p>Tips, scoring guides and smarter ways to track matches, rank players and run your club.</p>${listItems}</main>`
  const blogListPage = renderPage(shell, {
    title: 'Badminton Blog — tips, scoring & match tracking | Badminton 360',
    head: headBlock({
      title: 'Badminton Blog — tips, scoring & match tracking | Badminton 360',
      description: 'Badminton tips, scoring guides and match-tracking ideas for clubs and players. Learn to track scores, rank players with Elo, and run your badminton club better.',
      keywords: 'badminton, shuttle, badminton apps, badminton match tracking, badminton score tracking, badminton tips, badminton club',
      url: `${BASE}/blog`,
      jsonLd: { '@context': 'https://schema.org', '@type': 'Blog', name: 'Badminton 360 Blog', url: `${BASE}/blog` },
    }),
    appHtml: blogListHtml,
  })
  mkdirSync('dist/blog', { recursive: true })
  writeFileSync('dist/blog/index.html', blogListPage)

  // each post
  for (const p of posts) {
    const url = `${BASE}/blog/${p.slug}`
    const desc = p.meta_description || p.excerpt || ''
    const appHtml = `<article><h1>${escHtml(p.title)}</h1>${p.cover_url ? `<img src="${escAttr(p.cover_url)}" alt="${escAttr(p.title)}" width="1200" height="630">` : ''}<div>${p.body}</div></article>`
    const page = renderPage(shell, {
      title: `${p.title} | Badminton 360`,
      head: headBlock({
        title: `${p.title} | Badminton 360`,
        description: desc,
        keywords: p.keywords || 'badminton, shuttle, badminton apps, badminton match tracking, badminton score tracking',
        image: p.cover_url,
        url, type: 'article',
        jsonLd: {
          '@context': 'https://schema.org', '@type': 'BlogPosting', headline: p.title,
          description: desc, image: p.cover_url ? [p.cover_url] : undefined,
          author: { '@type': 'Organization', name: p.author || 'Badminton 360' },
          publisher: { '@type': 'Organization', name: 'Badminton 360', logo: { '@type': 'ImageObject', url: `${BASE}/icon-512.png` } },
          datePublished: p.publish_at, dateModified: p.updated_at, mainEntityOfPage: url,
        },
      }),
      appHtml,
    })
    mkdirSync(`dist/blog/${p.slug}`, { recursive: true })
    writeFileSync(`dist/blog/${p.slug}/index.html`, page)
  }

  // sitemap
  const urls = [
    { loc: `${BASE}/`, freq: 'weekly', pri: '1.0' },
    { loc: `${BASE}/explore`, freq: 'daily', pri: '0.9' },
    { loc: `${BASE}/blog`, freq: 'weekly', pri: '0.8' },
    ...posts.map(p => ({ loc: `${BASE}/blog/${p.slug}`, freq: 'monthly', pri: '0.7', lastmod: (p.updated_at || p.publish_at || '').slice(0, 10) })),
    { loc: `${BASE}/login`, freq: 'monthly', pri: '0.6' },
  ]
  const sitemap = `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${urls.map(u => `  <url>\n    <loc>${u.loc}</loc>${u.lastmod ? `\n    <lastmod>${u.lastmod}</lastmod>` : ''}\n    <changefreq>${u.freq}</changefreq>\n    <priority>${u.pri}</priority>\n  </url>`).join('\n')}\n</urlset>\n`
  writeFileSync('dist/sitemap.xml', sitemap)
  console.log('[prerender] wrote blog pages + sitemap')
}

main().catch(err => { console.warn('[prerender] skipped:', err?.message || err) }).finally(() => process.exit(0))
