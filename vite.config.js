import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import { VitePWA } from 'vite-plugin-pwa'

export default defineConfig({
  test: {
    environment: 'jsdom',
    globals: true,
    coverage: {
      provider: 'v8',
      reporter: ['text', 'html'],
      include: ['src/utils/**'],
    },
  },
  plugins: [
    vue(),
    VitePWA({
      registerType: 'prompt',
      includeAssets: ['favicon.svg', 'icon-192.png', 'icon-512.png', 'badge.png', 'sw-push.js'],
      workbox: {
        clientsClaim: true,
        cleanupOutdatedCaches: true,
        importScripts: ['sw-push.js'],
        // Offline viewing: cache images and the last-seen data GETs so rankings,
        // best pairs, players and photos still show with no signal. (Writes and
        // RPC/POST reads still need a connection — see the offline banner.)
        runtimeCaching: [
          {
            urlPattern: ({ url }) => url.hostname === 'images.badminton360.app',
            handler: 'CacheFirst',
            options: { cacheName: 'b360-images', expiration: { maxEntries: 400, maxAgeSeconds: 2592000 }, cacheableResponse: { statuses: [0, 200] } },
          },
          {
            urlPattern: ({ url }) => /\.supabase\.co$/.test(url.hostname) && url.pathname.startsWith('/storage/'),
            handler: 'CacheFirst',
            options: { cacheName: 'b360-avatars', expiration: { maxEntries: 300, maxAgeSeconds: 2592000 }, cacheableResponse: { statuses: [0, 200] } },
          },
          {
            urlPattern: ({ url, request }) => /\.supabase\.co$/.test(url.hostname) && url.pathname.startsWith('/rest/v1/') && request.method === 'GET',
            handler: 'NetworkFirst',
            options: { cacheName: 'b360-data', networkTimeoutSeconds: 4, expiration: { maxEntries: 250, maxAgeSeconds: 86400 }, cacheableResponse: { statuses: [0, 200] } },
          },
          {
            urlPattern: ({ url }) => url.hostname === 'fonts.googleapis.com' || url.hostname === 'fonts.gstatic.com',
            handler: 'StaleWhileRevalidate',
            options: { cacheName: 'b360-fonts', expiration: { maxEntries: 30, maxAgeSeconds: 31536000 } },
          },
        ],
      },
      manifest: {
        name: 'Badminton 360 – Rankings & Payment Splits',
        short_name: 'B360',
        description: 'Free app for badminton clubs worldwide. Elo rankings, match tracking, expense splitting and tournaments.',
        theme_color: '#eef4ff',
        background_color: '#eef4ff',
        display: 'standalone',
        orientation: 'portrait',
        id: '/',
        start_url: '/',
        scope: '/',
        lang: 'en',
        categories: ['sports', 'utilities'],
        icons: [
          { src: 'icon-192.png', sizes: '192x192', type: 'image/png', purpose: 'any' },
          { src: 'icon-512.png', sizes: '512x512', type: 'image/png', purpose: 'any' },
          { src: 'icon-512.png', sizes: '512x512', type: 'image/png', purpose: 'maskable' }
        ],
        screenshots: [
          {
            src: 'screenshots/screenshot-1.jpeg',
            sizes: '738x1477',
            type: 'image/jpeg',
            form_factor: 'narrow',
            label: 'Club leaderboard — Elo ratings, win %, and days played, ranked live'
          },
          {
            src: 'screenshots/screenshot-2.jpeg',
            sizes: '738x1477',
            type: 'image/jpeg',
            form_factor: 'narrow',
            label: 'Match history — every doubles result, newest first'
          },
          {
            src: 'screenshots/screenshot-3.jpeg',
            sizes: '738x1475',
            type: 'image/jpeg',
            form_factor: 'narrow',
            label: 'Schedule — plan match days and see who\'s coming'
          },
          {
            src: 'screenshots/screenshot-4.jpeg',
            sizes: '738x1474',
            type: 'image/jpeg',
            form_factor: 'narrow',
            label: 'Split Pay — track and split court costs equally among players'
          },
          {
            src: 'screenshots/screenshot-5.jpeg',
            sizes: '738x1476',
            type: 'image/jpeg',
            form_factor: 'narrow',
            label: 'Shared wallet — pre-fund court fees and settle up automatically'
          },
          {
            src: 'screenshots/screenshot-6.jpeg',
            sizes: '738x1480',
            type: 'image/jpeg',
            form_factor: 'narrow',
            label: 'Add an expense and split it across the players who played'
          }
        ],
        related_applications: [
          {
            platform: 'webapp',
            url: 'https://badminton360.app/manifest.webmanifest'
          }
        ],
        prefer_related_applications: false
      }
    })
  ]
})
