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
      includeAssets: ['favicon.svg', 'icon-192.png', 'icon-512.png', 'sw-push.js'],
      workbox: {
        clientsClaim: true,
        importScripts: ['sw-push.js']
      },
      manifest: {
        name: 'Badminton 360 – Club Manager & Rankings',
        short_name: 'B360',
        description: 'Free app for badminton clubs worldwide. Elo rankings, match tracking, expense splitting and tournaments.',
        theme_color: '#00e5ff',
        background_color: '#050d1a',
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
            src: 'icon-512.png',
            sizes: '512x512',
            type: 'image/png',
            form_factor: 'narrow',
            label: 'Badminton 360 – Club Leaderboard & Match Tracker'
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
