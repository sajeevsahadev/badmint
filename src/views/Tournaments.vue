<script setup>
import { ref, computed, onMounted } from 'vue'
import { useRouter, useRoute } from 'vue-router'
import { supabase } from '../lib/supabase'
import { useAuth } from '../composables/useAuth'
import { useClub } from '../composables/useClub'
import PageHeader from '../components/PageHeader.vue'
import DateField from '../components/DateField.vue'

const router = useRouter()
const route  = useRoute()
const { user } = useAuth()
const { currentClub } = useClub()
const cur = computed(() => currentClub.value?.clubs?.currency || 'AED')

// Only app admins (super admins) may create tournaments.
const isAppAdmin = ref(false)
async function loadRoles() {
  const { data } = await supabase.rpc('get_my_roles')
  isAppAdmin.value = (data ?? []).some(r => r.role === 'app_admin')
  // Deep-link from a play day's Game Plan → open the create sheet (admins only).
  if (user.value && route.query.create) {
    if (/^\d{4}-\d{2}-\d{2}$/.test(route.query.date || '')) {
      form.value.start_date = route.query.date
      form.value.registration_end = route.query.date
    }
    showCreate.value = true
  }
}

const drawLabel = t => ({
  knockout: 'Knock-out', round_robin: 'Round-robin', groups_knockout: 'Groups + KO',
}[t.draw_type] || (t.format === 'round_robin' ? 'Round-robin' : 'Knock-out'))
const catLabel = v => ({ mens_doubles: "Men's Doubles", womens_doubles: "Women's Doubles", mixed_doubles: 'Mixed Doubles' }[v] || null)
const skillLabel = v => v ? v.charAt(0).toUpperCase() + v.slice(1) : null

const tournaments = ref([])
const loading     = ref(true)
const loadErr     = ref('')
const filterStatus = ref('all')
const showCreate  = ref(false)

// Create form
const form = ref({
  name: '', draw_type: 'knockout', max_teams: 8, courts: 1, is_public: true,
  entry_fee: '', currency: '', prize_info: '', venue: '', venue_address: '', maps_url: '', region: '',
  category: '', skill_level: '', best_of_3: false,
  registration_end: '', start_date: '', description: ''
})
const creating = ref(false)
const createErr = ref('')

// Metadata options (shared with settings labels)
const categories = [
  { v: '', l: 'Open (any)' },
  { v: 'mens_doubles',   l: "Men's Doubles" },
  { v: 'womens_doubles', l: "Women's Doubles" },
  { v: 'mixed_doubles',  l: 'Mixed Doubles' },
]
const skillLevels = [
  { v: '', l: 'All levels' },
  { v: 'beginner',     l: 'Beginner' },
  { v: 'intermediate', l: 'Intermediate' },
  { v: 'advanced',     l: 'Advanced' },
]
const currencyList = ['AED','USD','EUR','GBP','INR','SAR','QAR','OMR','BHD','KWD','PKR','LKR','PHP','MYR','SGD','AUD','CAD']
const uaeEmirates = ['Abu Dhabi','Dubai','Sharjah','Ajman','Umm Al Quwain','Ras Al Khaimah','Fujairah']

const statusOptions = [
  { v: 'all',               l: 'All',         admin: false },
  { v: 'draft',             l: 'Draft',       admin: true  },  // unpublished — admins only
  { v: 'registration_open', l: 'Registering', admin: false },  // sign-ups open
  { v: 'live',              l: 'Live',        admin: false },  // matches being played
  { v: 'completed',         l: 'Finished',    admin: false },  // results are in
]
// Draft (unpublished) tournaments are only visible to app admins.
const visibleStatuses = computed(() => statusOptions.filter(o => !o.admin || !!user.value))


async function load() {
  loading.value = true
  loadErr.value = ''
  const { data, error } = await supabase.rpc('get_tournaments', {
    p_club_id: null,
    p_status:  filterStatus.value === 'all' ? null : filterStatus.value,
    p_emirate: null,
  })
  if (error) {
    loadErr.value = error.message
  } else {
    tournaments.value = data ?? []
  }
  loading.value = false
}

onMounted(() => {
  load()
  loadRoles()
})

const filtered = computed(() => tournaments.value)

async function create() {
  createErr.value = ''
  if (!form.value.name.trim()) { createErr.value = 'Tournament name is required'; return }
  if (!currentClub.value) { createErr.value = 'Select a club first'; return }
  creating.value = true
  const { data, error } = await supabase.rpc('create_tournament', {
    p_club_id:         currentClub.value.club_id,
    p_name:            form.value.name.trim(),
    p_draw_type:       form.value.draw_type,
    p_max_teams:       Number(form.value.max_teams) || 8,
    p_courts:          Number(form.value.courts) || 1,
    p_is_public:       form.value.is_public,
    p_maps_url:        form.value.maps_url || null,
    p_description:     form.value.description || null,
    p_entry_fee:       form.value.entry_fee ? Number(form.value.entry_fee) : null,
    p_prize_info:      form.value.prize_info || null,
    p_venue:           form.value.venue || null,
    p_venue_address:   form.value.venue_address || null,
    p_emirate:         form.value.region || null,
    p_registration_end: form.value.registration_end || null,
    p_start_date:      form.value.start_date || null,
    p_best_of_3:       form.value.best_of_3,
    p_category:        form.value.category || null,
    p_skill_level:     form.value.skill_level || null,
    p_currency:        form.value.currency || cur.value || null,
  })
  creating.value = false
  if (error) { createErr.value = error.message; return }
  showCreate.value = false
  await load()
  router.push('/tournament/' + data + '/manage')
}

const statusLabel = s => ({
  draft: 'Draft', registration_open: 'Registering',
  registration_closed: 'Registration closed', live: '🔴 Live now',
  completed: 'Finished', cancelled: 'Cancelled'
}[s] ?? s)

const statusClass = s => ({
  draft: 'badge-pending',
  registration_open: 'badge-approved',
  live: 'badge bg-rose-50 text-rose-600 border border-rose-200',
  completed: 'badge bg-slate-100 text-slate-500 border border-slate-200',
  cancelled: 'badge bg-slate-100 text-slate-400 border border-slate-200',
}[s] ?? 'badge-pending')

const fmtDate = d => d ? new Date(d).toLocaleDateString('en-AE', { day:'numeric', month:'short' }) : '—'
</script>

<template>
  <div class="mx-auto max-w-2xl px-4 pb-4" :class="user ? 'pt-[calc(env(safe-area-inset-top,0px)+3.75rem)]' : 'pt-5'">
    <PageHeader icon="🏆" title="Tournaments" subtitle="Doubles elimination & round-robin events">
      <template #help>
        <div class="text-xs space-y-1.5">
          <p><strong>Registration Open</strong> — players can join, director manages registrations.</p>
          <p><strong>Live</strong> — bracket is generated, matches being played.</p>
          <p><strong>Create</strong> — any member can run a tournament for their club.</p>
        </div>
      </template>
    </PageHeader>

    <!-- Status filter — underline tabs -->
    <div class="flex items-center gap-6 border-b border-slate-200 mb-4 overflow-x-auto fade-up">
      <button v-for="opt in visibleStatuses" :key="opt.v"
        class="relative shrink-0 pb-2.5 text-sm font-semibold whitespace-nowrap transition-colors"
        :class="filterStatus === opt.v ? 'text-slate-900' : 'text-slate-400 hover:text-slate-600'"
        @click="filterStatus = opt.v; load()">
        {{ opt.l }}
        <span v-if="filterStatus === opt.v"
          class="absolute left-0 right-0 -bottom-px h-0.5 rounded-full bg-gradient-to-r from-cyan-500 to-violet-500" />
      </button>
    </div>

    <!-- Create (super admins only) -->
    <button v-if="user"
      class="w-full mb-4 rounded-2xl py-3 text-sm font-bold text-white flex items-center justify-center gap-2
             bg-gradient-to-r from-cyan-500 to-violet-500 shadow hover:shadow-lg active:scale-[0.99] transition-all"
      @click="showCreate = true">
      <span class="text-lg leading-none">＋</span> Create Tournament
    </button>

    <!-- Loading -->
    <div v-if="loading" class="space-y-3">
      <div v-for="i in 4" :key="i" class="h-24 shimmer rounded-2xl" />
    </div>

    <!-- Error (e.g. SQL migration not yet run) -->
    <div v-else-if="loadErr" class="card p-5 fade-up border-rose-200">
      <p class="text-sm font-semibold text-rose-600 mb-1">Could not load tournaments</p>
      <p class="text-xs text-slate-500 font-mono">{{ loadErr }}</p>
      <p class="text-xs text-slate-400 mt-2">
        Make sure <code class="bg-slate-100 px-1 rounded">v14_schema.sql</code> has been run
        in the Supabase SQL Editor.
      </p>
    </div>

    <!-- Empty -->
    <div v-else-if="!filtered.length" class="card p-10 text-center fade-up">
      <div class="text-4xl mb-3">🏆</div>
      <p class="font-bold text-slate-600 text-lg mb-1">
        {{ filterStatus === 'all' ? 'No tournaments yet' : 'No ' + filterStatus.replace('_',' ') + ' tournaments' }}
      </p>
      <p class="text-slate-400 text-sm mb-3">
        {{ filterStatus !== 'all' ? 'Try the "All" filter to see other tournaments.' : user ? 'Create the first tournament for your club.' : 'Sign in to create a tournament, or check back soon.' }}
      </p>
    </div>

    <!-- List -->
    <div v-else class="space-y-3 fade-up">
      <div v-for="t in filtered" :key="t.id"
        class="card p-4 cursor-pointer hover:border-cyan-400/40 transition-all active:scale-[0.99]"
        @click="router.push('/tournaments/' + (t.slug || t.id))">

        <div class="flex items-start justify-between gap-2">
          <div class="flex-1 min-w-0">
            <div class="flex items-center gap-2 flex-wrap mb-1">
              <span :class="statusClass(t.status)">{{ statusLabel(t.status) }}</span>
              <span class="badge bg-violet-50 text-violet-700 border border-violet-200">{{ drawLabel(t) }}</span>
              <span v-if="catLabel(t.category)" class="badge bg-cyan-50 text-cyan-700 border border-cyan-200">{{ catLabel(t.category) }}</span>
              <span v-if="skillLabel(t.skill_level)" class="badge bg-slate-100 text-slate-500 border border-slate-200">{{ skillLabel(t.skill_level) }}</span>
              <span v-if="t.best_of_3" class="badge bg-amber-50 text-amber-700 border border-amber-200">Best of 3</span>
            </div>
            <h3 class="font-display font-bold text-slate-800 text-base truncate">{{ t.name }}</h3>
            <p class="text-xs text-slate-500 mt-0.5 truncate">{{ t.club_name }}</p>
          </div>
          <!-- Teams count -->
          <div class="shrink-0 text-right">
            <div class="text-lg font-extrabold text-neon">{{ t.confirmed_teams }}</div>
            <div class="text-[10px] text-slate-400">/ {{ t.max_teams }}<br>teams</div>
          </div>
        </div>

        <div class="mt-3 flex items-center gap-4 text-xs text-slate-500 flex-wrap">
          <span v-if="t.start_date">📅 {{ fmtDate(t.start_date) }}</span>
          <span v-if="t.venue">📍 {{ t.venue }}</span>
          <span v-if="t.emirate">🌍 {{ t.emirate }}</span>
          <span v-if="t.entry_fee">💰 {{ t.currency || cur }} {{ t.entry_fee }}</span>
          <span v-if="t.registration_end && t.status === 'registration_open'"
            class="text-amber-600">
            Reg. closes {{ fmtDate(t.registration_end) }}
          </span>
        </div>

        <div v-if="t.winner_team_name" class="mt-2 text-xs text-amber-600 font-semibold">
          🥇 Winner: {{ t.winner_team_name }}
        </div>
      </div>
    </div>
  </div>

  <!-- ── Create Tournament Sheet ── -->
  <Teleport to="body">
    <div v-if="showCreate"
      class="fixed inset-0 z-50 flex items-end sm:items-center justify-center"
      style="background:rgba(0,0,0,.55); backdrop-filter:blur(4px)"
      @click.self="showCreate = false">
      <div class="w-full max-w-lg rounded-t-3xl sm:rounded-3xl p-6 overflow-y-auto max-h-[90vh]"
        style="background:#f8fafc; border:1px solid rgba(0,168,204,.25)">

        <div class="flex items-center justify-between mb-5">
          <h2 class="font-display text-xl font-bold gradient-text">New Tournament</h2>
          <button class="text-slate-400 hover:text-slate-700 text-xl" @click="showCreate = false">✕</button>
        </div>

        <div class="space-y-4">
          <div>
            <label class="label">Tournament Name *</label>
            <input v-model="form.name" class="input" placeholder="e.g. Ramadan Doubles Cup 2026" />
          </div>

          <div class="grid grid-cols-2 gap-3">
            <div>
              <label class="label">Draw type</label>
              <select v-model="form.draw_type" class="input">
                <option value="knockout">Knock-out (eliminator)</option>
                <option value="groups_knockout">Round-robin + knock-out</option>
                <option value="round_robin">Round-robin only</option>
              </select>
            </div>
            <div>
              <label class="label">Max Teams</label>
              <select v-model="form.max_teams" class="input">
                <option v-for="n in [4,8,12,16,24,32]" :key="n" :value="n">{{ n }}</option>
              </select>
            </div>
          </div>

          <div class="grid grid-cols-2 gap-3">
            <div>
              <label class="label">Courts (parallel)</label>
              <input v-model="form.courts" type="number" min="1" max="12" class="input" />
            </div>
            <div>
              <label class="label">Visibility</label>
              <select v-model="form.is_public" class="input">
                <option :value="true">🌍 Public page</option>
                <option :value="false">🔒 Private (link only)</option>
              </select>
            </div>
          </div>

          <div class="grid grid-cols-2 gap-3">
            <div>
              <label class="label">Category</label>
              <select v-model="form.category" class="input">
                <option v-for="c in categories" :key="c.v" :value="c.v">{{ c.l }}</option>
              </select>
            </div>
            <div>
              <label class="label">Skill level</label>
              <select v-model="form.skill_level" class="input">
                <option v-for="s in skillLevels" :key="s.v" :value="s.v">{{ s.l }}</option>
              </select>
            </div>
          </div>

          <!-- Scoring -->
          <label class="flex items-center justify-between gap-3 rounded-xl border border-slate-200 px-3.5 py-2.5 cursor-pointer">
            <span>
              <span class="text-sm font-semibold text-slate-700">Best of 3 games</span>
              <span class="block text-[11px] text-slate-400">Championship scoring (e.g. 21–18, 19–21, 21–15). Off = single score.</span>
            </span>
            <input type="checkbox" v-model="form.best_of_3" class="w-5 h-5 accent-cyan-600 shrink-0" />
          </label>

          <div class="grid grid-cols-2 gap-3">
            <div>
              <label class="label">Entry Fee</label>
              <input v-model="form.entry_fee" type="number" min="0" class="input" placeholder="0" />
            </div>
            <div>
              <label class="label">Currency</label>
              <input v-model="form.currency" list="tourCurrencies" class="input" :placeholder="cur" />
              <datalist id="tourCurrencies"><option v-for="c in currencyList" :key="c" :value="c" /></datalist>
            </div>
          </div>

          <div>
            <label class="label">City / Region</label>
            <input v-model="form.region" list="tourRegions" class="input" placeholder="e.g. Dubai, London, Bengaluru" />
            <datalist id="tourRegions"><option v-for="e in uaeEmirates" :key="e" :value="e" /></datalist>
          </div>

          <div>
            <label class="label">Venue</label>
            <input v-model="form.venue" class="input" placeholder="Sports complex, court name…" />
          </div>
          <div>
            <label class="label">Address</label>
            <input v-model="form.venue_address" class="input" placeholder="Street / area, city" />
          </div>
          <div>
            <label class="label">Google Maps link (location) <span class="text-slate-400 font-normal">— optional</span></label>
            <input v-model="form.maps_url" class="input" placeholder="Paste the Google Maps share link" />
            <p class="text-[11px] text-slate-400 mt-1">In Google Maps: search the venue → Share → Copy link → paste here. Players get a “Get directions” button.</p>
          </div>

          <div class="grid grid-cols-2 gap-3">
            <div>
              <label class="label">Reg. Closes</label>
              <DateField v-model="form.registration_end" />
            </div>
            <div>
              <label class="label">Start Date</label>
              <DateField v-model="form.start_date" />
            </div>
          </div>

          <div>
            <label class="label">Prize Info</label>
            <input v-model="form.prize_info" class="input" :placeholder="`1st: ${cur} 500, 2nd: ${cur} 250…`" />
          </div>

          <div>
            <label class="label">Description</label>
            <textarea v-model="form.description" class="input resize-none" rows="2"
              placeholder="Rules, format notes, WhatsApp group link…" />
          </div>
        </div>

        <p v-if="createErr" class="mt-3 text-sm text-rose-500">{{ createErr }}</p>

        <div class="flex gap-3 mt-6">
          <button class="btn-ghost flex-1" @click="showCreate = false">Cancel</button>
          <button class="btn-primary flex-1" :disabled="creating" @click="create">
            {{ creating ? 'Creating…' : 'Create Tournament' }}
          </button>
        </div>
      </div>
    </div>
  </Teleport>
</template>
