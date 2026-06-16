<script setup>
import { ref, computed, onMounted } from 'vue'
import { useRoute, useRouter, RouterLink } from 'vue-router'
import { supabase } from '../lib/supabase'
import { useAuth } from '../composables/useAuth'

const route  = useRoute()
const router = useRouter()
const { user } = useAuth()

const facilityId = route.params.id
const data     = ref(null)   // { facility, schedule, bookings, clubs }
const loading  = ref(true)
const editing  = ref(false)
const saving   = ref(false)
const saveNote = ref(null)

// Edit form
const form = ref({})
const EMIRATES = ['Abu Dhabi','Dubai','Sharjah','Ajman','Umm Al Quwain','Ras Al Khaimah','Fujairah']
const DAYS     = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat']
const DAYS_FULL = ['Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday']

// Add slot form
const newSlot = ref({ day: 5, start: '06:00', end: '08:00', label: '' })
const addingSlot = ref(false)

const facility = computed(() => data.value?.facility)
const schedule = computed(() => data.value?.schedule ?? [])
const bookings = computed(() => data.value?.bookings ?? [])
const clubs    = computed(() => data.value?.clubs    ?? [])
const isOwner  = computed(() => user.value && facility.value?.created_by === user.value.id)

// Group schedule by day
const scheduleByDay = computed(() => {
  const m = {}
  schedule.value.forEach(s => {
    if (!m[s.day_of_week]) m[s.day_of_week] = []
    m[s.day_of_week].push(s)
  })
  return m
})

// Group bookings: today + next 14 days
const upcomingBookings = computed(() => {
  const today = new Date().toISOString().slice(0, 10)
  const future = bookings.value.filter(b => b.booked_date >= today)
  // Group by date
  const grouped = {}
  future.forEach(b => {
    if (!grouped[b.booked_date]) grouped[b.booked_date] = []
    grouped[b.booked_date].push(b)
  })
  return Object.entries(grouped)
    .sort((a, b) => a[0].localeCompare(b[0]))
    .slice(0, 14)
})

const pastBookings = computed(() => {
  const today = new Date().toISOString().slice(0, 10)
  return bookings.value.filter(b => b.booked_date < today).slice(0, 10)
})

async function load() {
  loading.value = true
  const { data: raw, error } = await supabase.rpc('get_facility_detail', {
    p_facility_id: facilityId
  })
  if (!error && raw) {
    data.value = raw
    form.value = { ...raw.facility }
  }
  loading.value = false
}
onMounted(load)

async function saveEdit() {
  saving.value = true; saveNote.value = null
  const { error } = await supabase.rpc('update_facility', {
    p_id:          facilityId,
    p_name:        form.value.name        || null,
    p_address:     form.value.address     || null,
    p_emirate:     form.value.emirate     || null,
    p_maps_url:    form.value.maps_url    || null,
    p_description: form.value.description || null,
    p_image_url:   form.value.image_url   || null,
    p_phone:       form.value.phone       || null,
    p_website:     form.value.website     || null,
  })
  saving.value = false
  if (error) { saveNote.value = { ok: false, t: error.message }; return }
  saveNote.value = { ok: true, t: '✅ Facility updated.' }
  editing.value = false
  await load()
}

async function addSlot() {
  addingSlot.value = true
  const { error } = await supabase.rpc('add_facility_slot', {
    p_facility_id: facilityId,
    p_day:         Number(newSlot.value.day),
    p_start:       newSlot.value.start,
    p_end:         newSlot.value.end,
    p_label:       newSlot.value.label || null,
  })
  addingSlot.value = false
  if (!error) {
    newSlot.value = { day: 5, start: '06:00', end: '08:00', label: '' }
    await load()
  }
}

const confirmDelSlotId = ref(null)

async function deleteSlot() {
  const id = confirmDelSlotId.value
  confirmDelSlotId.value = null
  if (!id) return
  await supabase.rpc('delete_facility_slot', { p_slot_id: id })
  await load()
}

const fmt = d => new Date(d + 'T00:00:00').toLocaleDateString('en-AE', { weekday:'short', day:'numeric', month:'short' })
const fmtTime = t => t ? t.slice(0, 5) : ''
const initials = n => (n ?? '?').split(' ').map(w => w[0]).slice(0, 2).join('').toUpperCase()
</script>

<template>
  <div v-if="loading" class="space-y-3">
    <div v-for="i in 4" :key="i" class="h-24 shimmer rounded-2xl" />
  </div>

  <div v-else-if="!facility" class="card p-8 text-center text-slate-400">
    <p class="font-semibold mb-2">Facility not found</p>
    <button class="btn-ghost px-6 text-sm mt-2" @click="router.back()">← Back</button>
  </div>

  <template v-else>
    <button class="flex items-center gap-1.5 text-xs text-slate-500 hover:text-neon transition mb-4"
      @click="router.back()">← Back</button>

    <!-- ── Hero image ── -->
    <div class="relative rounded-2xl overflow-hidden mb-4 fade-up"
      style="height:180px">
      <img v-if="facility.image_url" :src="facility.image_url" :alt="facility.name"
        class="w-full h-full object-cover" />
      <div v-else class="w-full h-full flex items-center justify-center text-5xl font-black text-slate-950"
        style="background:linear-gradient(135deg,#00e5ff 0%,#a855f7 50%,#f59e0b 100%)">
        {{ initials(facility.name) }}
      </div>
      <!-- Overlay badge -->
      <div class="absolute bottom-3 left-3 right-3 flex items-end justify-between">
        <div>
          <div class="text-white font-display text-2xl font-extrabold drop-shadow-lg">{{ facility.name }}</div>
          <span v-if="facility.emirate" class="badge-member text-[9px] mt-1">{{ facility.emirate }}</span>
        </div>
        <button v-if="isOwner" class="btn-ghost text-xs py-1.5 px-3 bg-black/40 border-white/20"
          @click="editing = !editing">
          {{ editing ? 'Cancel' : '✏️ Edit' }}
        </button>
      </div>
    </div>

    <!-- ── Edit form ── -->
    <div v-if="editing" class="card p-4 mb-4 fade-up">
      <div class="label">Edit Facility Info</div>
      <div class="space-y-2">
        <input v-model="form.name" class="input" placeholder="Facility name *" />
        <input v-model="form.address" class="input" placeholder="Address" />
        <select v-model="form.emirate" class="input">
          <option value="">— Select Emirate —</option>
          <option v-for="e in EMIRATES" :key="e" :value="e">{{ e }}</option>
        </select>
        <input v-model="form.maps_url" class="input" placeholder="Google Maps URL" />
        <input v-model="form.image_url" class="input" placeholder="Image URL (paste a photo link)" />
        <input v-model="form.phone" class="input" placeholder="Phone number" />
        <input v-model="form.website" class="input" placeholder="Website URL" />
        <textarea v-model="form.description" class="input resize-none" rows="2" placeholder="Description" />
      </div>
      <p v-if="saveNote" class="mt-2 text-xs"
        :class="saveNote.ok ? 'text-emerald-400' : 'text-rose-400'">{{ saveNote.t }}</p>
      <button class="btn-primary w-full mt-3" :disabled="saving" @click="saveEdit">
        {{ saving ? 'Saving…' : 'Save Changes' }}
      </button>
    </div>

    <!-- ── Facility details ── -->
    <div class="card p-4 mb-4 fade-up">
      <div v-if="facility.description" class="text-sm text-slate-300 mb-3 leading-relaxed">
        {{ facility.description }}
      </div>
      <div class="space-y-1.5 text-xs text-slate-400">
        <div v-if="facility.address" class="flex items-start gap-2">
          <span class="shrink-0">📍</span>
          <span>{{ facility.address }}</span>
        </div>
        <div v-if="facility.phone" class="flex items-center gap-2">
          <span>📞</span>
          <a :href="'tel:' + facility.phone" class="hover:text-neon transition">{{ facility.phone }}</a>
        </div>
        <div v-if="facility.website" class="flex items-center gap-2">
          <span>🌐</span>
          <a :href="facility.website" target="_blank" rel="noopener" class="hover:text-neon transition truncate">
            {{ facility.website }}
          </a>
        </div>
      </div>
      <a v-if="facility.maps_url" :href="facility.maps_url" target="_blank" rel="noopener"
        class="mt-3 inline-flex items-center gap-2 text-xs text-neon border border-cyan-500/20 rounded-xl px-3 py-2 hover:opacity-80 transition">
        🗺️ Open in Google Maps
      </a>
    </div>

    <!-- ── Stats row ── -->
    <div class="grid grid-cols-3 gap-2 mb-4 fade-up">
      <div class="card p-3 text-center">
        <div class="text-xl font-extrabold text-neon">{{ clubs.length }}</div>
        <div class="text-[9px] text-slate-600 uppercase tracking-wider mt-0.5">Clubs</div>
      </div>
      <div class="card p-3 text-center">
        <div class="text-xl font-extrabold text-violet">{{ schedule.length }}</div>
        <div class="text-[9px] text-slate-600 uppercase tracking-wider mt-0.5">Slots/week</div>
      </div>
      <div class="card p-3 text-center">
        <div class="text-xl font-extrabold text-gold">{{ upcomingBookings.length }}</div>
        <div class="text-[9px] text-slate-600 uppercase tracking-wider mt-0.5">Upcoming</div>
      </div>
    </div>

    <!-- ── Weekly schedule ── -->
    <div class="card p-4 mb-4 fade-up">
      <div class="flex items-center justify-between mb-3">
        <div class="label mb-0">📅 Weekly Schedule</div>
        <button v-if="isOwner" class="text-xs text-neon hover:opacity-75 transition"
          @click="addingSlot = !addingSlot">
          {{ addingSlot ? 'Cancel' : '+ Add Slot' }}
        </button>
      </div>

      <!-- Add slot form -->
      <div v-if="addingSlot && isOwner" class="card p-3 mb-3" style="border-color:rgba(168,85,247,.25)">
        <div class="grid grid-cols-2 gap-2 mb-2">
          <div>
            <label class="label">Day</label>
            <select v-model="newSlot.day" class="input text-sm">
              <option v-for="(d, i) in DAYS_FULL" :key="i" :value="i">{{ d }}</option>
            </select>
          </div>
          <div>
            <label class="label">Label (optional)</label>
            <input v-model="newSlot.label" class="input text-sm" placeholder="e.g. Morning" />
          </div>
          <div>
            <label class="label">Start</label>
            <input v-model="newSlot.start" type="time" class="input text-sm" />
          </div>
          <div>
            <label class="label">End</label>
            <input v-model="newSlot.end" type="time" class="input text-sm" />
          </div>
        </div>
        <button class="btn-violet w-full text-sm py-2" :disabled="addingSlot && !newSlot.start"
          @click="addSlot">Add Slot</button>
      </div>

      <!-- No schedule yet -->
      <div v-if="!schedule.length" class="text-xs text-slate-500 text-center py-3">
        No schedule set yet.{{ isOwner ? ' Add slots above.' : '' }}
      </div>

      <!-- Schedule grid -->
      <div v-else class="space-y-1.5">
        <div v-for="day in 7" :key="day - 1">
          <div v-if="scheduleByDay[day - 1]?.length" class="flex items-start gap-2">
            <span class="text-[10px] font-bold text-slate-500 w-8 shrink-0 mt-0.5">
              {{ DAYS[day - 1] }}
            </span>
            <div class="flex flex-wrap gap-1.5 flex-1">
              <div v-for="s in scheduleByDay[day - 1]" :key="s.id"
                class="flex items-center gap-1.5 text-xs bg-[rgba(15,23,42,0.04)] border border-[rgba(15,23,42,0.08)] rounded-lg px-2 py-1">
                <span class="text-neon font-semibold">{{ fmtTime(s.start_time) }}–{{ fmtTime(s.end_time) }}</span>
                <span v-if="s.slot_label" class="text-slate-500">{{ s.slot_label }}</span>
                <button v-if="isOwner" class="text-slate-700 hover:text-rose-400 transition ml-1"
                  @click="confirmDelSlotId = s.id">✕</button>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- ── Upcoming bookings ── -->
    <div class="card overflow-hidden mb-4 fade-up">
      <div class="px-4 py-3 border-b border-[rgba(15,23,42,0.06)]">
        <span class="text-xs font-bold text-slate-200">🏸 Upcoming Sessions</span>
      </div>
      <div v-if="!upcomingBookings.length" class="px-4 py-5 text-center text-sm text-slate-500">
        No upcoming bookings.
      </div>
      <div v-for="[date, entries] in upcomingBookings" :key="date"
        class="px-4 py-3 border-b border-[rgba(15,23,42,0.04)] last:border-0">
        <div class="text-[10px] text-slate-500 font-semibold mb-1.5">{{ fmt(date) }}</div>
        <div v-for="e in entries" :key="e.id"
          class="flex items-center justify-between text-sm">
          <RouterLink :to="'/club/' + e.club_id"
            class="font-semibold text-slate-100 hover:text-neon transition truncate">
            {{ e.club_name }}
          </RouterLink>
          <span v-if="e.start_time !== '00:00:00'" class="text-xs text-neon shrink-0 ml-2">
            {{ fmtTime(e.start_time) }}{{ e.end_time ? '–' + fmtTime(e.end_time) : '' }}
          </span>
        </div>
      </div>
    </div>

    <!-- ── Past sessions ── -->
    <div v-if="pastBookings.length" class="card overflow-hidden mb-4 fade-up">
      <div class="px-4 py-3 border-b border-[rgba(15,23,42,0.06)]">
        <span class="text-xs font-bold text-slate-200">Recent Sessions</span>
      </div>
      <div v-for="b in pastBookings" :key="b.id"
        class="flex items-center justify-between px-4 py-2.5 border-b border-[rgba(15,23,42,0.04)] last:border-0">
        <RouterLink :to="'/club/' + b.club_id"
          class="text-sm font-semibold text-slate-300 hover:text-neon transition">
          {{ b.club_name }}
        </RouterLink>
        <span class="text-xs text-slate-500">{{ fmt(b.booked_date) }}</span>
      </div>
    </div>

    <!-- ── Clubs at this facility ── -->
    <div v-if="clubs.length" class="card p-4 fade-up">
      <div class="label">Clubs Playing Here</div>
      <div v-for="c in clubs" :key="c.id"
        class="flex items-center gap-3 py-2 border-b border-[rgba(15,23,42,0.05)] last:border-0">
        <div class="w-8 h-8 rounded-xl flex items-center justify-center text-xs font-black text-slate-950 shrink-0"
          style="background:linear-gradient(135deg,#00e5ff,#a855f7)">
          {{ initials(c.name) }}
        </div>
        <RouterLink :to="'/club/' + c.id"
          class="text-sm font-semibold text-slate-100 hover:text-neon transition flex-1 truncate">
          {{ c.name }}
        </RouterLink>
        <span v-if="c.emirates" class="badge-member text-[9px] shrink-0">{{ c.emirates }}</span>
      </div>
    </div>

  </template>

  <!-- Delete slot confirm -->
  <Teleport to="body">
    <div v-if="confirmDelSlotId" class="fixed inset-0 z-50 flex items-center justify-center px-5"
      style="background:rgba(0,0,0,.75);backdrop-filter:blur(6px)"
      @click.self="confirmDelSlotId = null">
      <div class="w-full max-w-sm rounded-2xl p-6"
        style="background:#0d1a2e; border:1px solid rgba(244,63,94,.25); box-shadow:0 0 40px rgba(244,63,94,.12)">
        <div class="text-center mb-4">
          <div class="text-3xl mb-2">🗑️</div>
          <p class="font-semibold text-slate-100 mb-1">Remove this schedule slot?</p>
          <p class="text-xs text-slate-400">This removes the weekly time slot from the facility schedule.</p>
        </div>
        <div class="flex gap-3">
          <button class="flex-1 py-3 rounded-xl text-sm font-semibold text-slate-300 border border-white/10 hover:border-white/25 hover:text-white transition"
            @click="confirmDelSlotId = null">Cancel</button>
          <button class="flex-1 py-3 rounded-xl text-sm font-bold text-white transition active:scale-[.97]"
            style="background:rgba(220,38,38,.85); border:1px solid rgba(244,63,94,.4)"
            @click="deleteSlot">Yes, Remove</button>
        </div>
      </div>
    </div>
  </Teleport>
</template>
