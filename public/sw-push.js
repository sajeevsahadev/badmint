// Push notification handler — imported by the generated service worker
// via workbox.importScripts in vite.config.js

self.addEventListener('push', (event) => {
  if (!event.data) return
  let data = {}
  try { data = event.data.json() } catch { data = { title: 'Badminton 360', body: event.data.text() } }

  event.waitUntil(
    self.registration.showNotification(data.title || 'Badminton 360', {
      body:    data.body  || 'You have a new update.',
      icon:    data.icon  || '/icon-192.png',   // sender's avatar when provided (WhatsApp-style)
      badge:   '/badge.png',   // monochrome silhouette for the Android status bar
      data:    { url: data.url || '/' },
      tag:     data.tag  || 'b360',
      renotify: true
    })
  )
})

self.addEventListener('notificationclick', (event) => {
  event.notification.close()
  const url = event.notification.data?.url || '/'
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((list) => {
      for (const client of list) {
        if ('focus' in client) {
          client.navigate(url)
          return client.focus()
        }
      }
      return clients.openWindow(url)
    })
  )
})

// ── Web Share Target ──────────────────────────────────────────────────────
// The manifest's share_target POSTs the shared photo here. We stash the file in
// a cache and redirect to the /share receiver page, which reads it back and
// lets the user post it into a club chat. (Enabled by a new AAB build.)
self.addEventListener('fetch', (event) => {
  const url = new URL(event.request.url)
  if (event.request.method === 'POST' && url.pathname === '/share-target') {
    event.respondWith((async () => {
      try {
        const form = await event.request.formData()
        const file = form.get('image')
        if (file && file.size) {
          const cache = await caches.open('b360-share')
          await cache.put('/__shared-image',
            new Response(file, { headers: { 'Content-Type': file.type || 'image/jpeg' } }))
        }
      } catch { /* fall through to the page, which shows an empty-state */ }
      return Response.redirect('/share', 303)
    })())
  }
})
