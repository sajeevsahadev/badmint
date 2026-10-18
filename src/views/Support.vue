<script setup>
import { ref, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { useAuth } from '../composables/useAuth'
import QRCode from 'qrcode'

const router = useRouter()
const { user } = useAuth()

// Crowdfunding link (Buy Me a Coffee). Single source of truth.
const BMC_URL = 'https://buymeacoffee.com/sajeev'

const qr = ref('')
const shared = ref('')

onMounted(async () => {
  try {
    qr.value = await QRCode.toDataURL(BMC_URL, {
      width: 220, margin: 1, color: { dark: '#0b1220', light: '#ffffff' },
    })
  } catch { /* QR is a nice-to-have; the button still works */ }
})

async function share() {
  shared.value = ''
  const data = { title: 'Support Badminton 360', text: 'Keep Badminton 360 free for every club 🏸☕', url: BMC_URL }
  try {
    if (navigator.share) { await navigator.share(data); return }
    await navigator.clipboard.writeText(BMC_URL)
    shared.value = 'Link copied!'
  } catch { /* user cancelled share — ignore */ }
}
</script>

<template>
  <div class="max-w-xl mx-auto px-4 pb-6"
       :class="user ? 'pb-28 pt-[calc(env(safe-area-inset-top,0px)+3.25rem)]' : 'pt-6'">
    <button class="flex items-center gap-1.5 text-sm text-slate-500 hover:text-cyan-700 transition mb-6"
            @click="router.back()">‹ Back</button>

    <!-- Hero -->
    <div class="text-center mb-7 fade-up">
      <div class="text-5xl mb-3">☕</div>
      <h1 class="font-display text-2xl font-extrabold gradient-text mb-2">Support Badminton 360</h1>
      <p class="text-sm text-slate-500 leading-relaxed">
        Badminton 360 is <b>free for every club</b>, with no ads. If it's saved your group some hassle,
        a coffee helps keep the servers running and new features coming. 🏸
      </p>
    </div>

    <!-- Buy Me a Coffee button -->
    <a :href="BMC_URL" target="_blank" rel="noopener noreferrer"
       class="flex items-center justify-center gap-2.5 w-full py-4 rounded-2xl font-extrabold text-[17px]
              text-[#0d0c0c] transition active:scale-[.99] shadow-sm hover:shadow-md fade-up"
       style="background:#FFDD00;">
      <span class="text-xl">☕</span> Buy me a coffee
    </a>
    <p class="text-center text-[11px] text-slate-400 mt-2">
      Opens Buy Me a Coffee · one-time or monthly, any amount
    </p>

    <!-- QR + share -->
    <div class="card p-5 mt-6 flex flex-col items-center fade-up">
      <p class="text-xs font-semibold text-slate-500 uppercase tracking-widest mb-3">Scan to support</p>
      <img v-if="qr" :src="qr" alt="Buy Me a Coffee QR code" width="200" height="200"
           class="rounded-xl border border-slate-100" />
      <div v-else class="w-[200px] h-[200px] rounded-xl shimmer" />
      <p class="text-[11px] text-slate-400 mt-3 break-all text-center">buymeacoffee.com/sajeev</p>
      <button class="btn-ghost mt-4 text-sm px-5" @click="share">🔗 Share this</button>
      <p v-if="shared" class="text-xs text-emerald-600 mt-2">{{ shared }}</p>
    </div>

    <!-- What it funds -->
    <div class="card p-5 mt-5 fade-up">
      <p class="text-sm font-bold text-slate-800 mb-3">What your support keeps running</p>
      <ul class="space-y-2 text-sm text-slate-600">
        <li class="flex gap-2"><span>🏆</span><span>Live Elo rankings, match history &amp; stats for every club</span></li>
        <li class="flex gap-2"><span>💰</span><span>Split Pay &amp; shared Wallet — fair cost splitting, no chasing</span></li>
        <li class="flex gap-2"><span>📅</span><span>Schedules, polls, chat and tournaments</span></li>
        <li class="flex gap-2"><span>🌍</span><span>Free forever, for badminton clubs everywhere</span></li>
      </ul>
    </div>

    <p class="text-center text-xs text-slate-400 mt-6">
      Thank you for being part of the Badminton 360 community. 💙
    </p>
  </div>
</template>
