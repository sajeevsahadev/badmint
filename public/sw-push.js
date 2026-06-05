// Push notification handler — imported by the generated service worker
// via workbox.importScripts in vite.config.js

self.addEventListener('push', (event) => {
  if (!event.data) return
  let data = {}
  try { data = event.data.json() } catch { data = { title: 'Badmint', body: event.data.text() } }

  event.waitUntil(
    self.registration.showNotification(data.title || 'Badmint', {
      body:    data.body  || 'You have a new update.',
      icon:    '/icon-192.png',
      badge:   '/icon-192.png',
      data:    { url: data.url || '/' },
      tag:     data.tag  || 'badmint',
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
