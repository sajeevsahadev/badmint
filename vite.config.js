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
        importScripts: ['sw-push.js']
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
