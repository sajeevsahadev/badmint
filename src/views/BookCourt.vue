<script setup>
import { ref, computed, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { supabase } from '../lib/supabase'
import { useAuth } from '../composables/useAuth'
import PageHeader from '../components/PageHeader.vue'

const router = useRouter()
const { user } = useAuth()

const facilities = ref([])
const loading    = ref(true)
const search     = ref('')
const emirate    = ref('')
const selected   = ref(null)   // facility being booked
const detail     = ref(null)   // full facility detail
const detailLoading = ref(false)

// Booking form
const bookForm = ref({ date: new Date().toISOString().slice(0,10), courts: 1, team_name: '', notes: '' })
const bookBusy = ref(false)
const bookStep = ref('form')   // form | payment | done

const emirates = ['Abu Dhabi','Dubai','Sharjah','Ajman','Umm Al Quwain','Ras Al Khaimah','Fujairah']

async function load() {
  loading.value = true
  const { data } = await supabase.rpc('get_facilities', {
    p_emirate: emirate.value || null,
    p_search:  search.value.trim() || null,
  })
  facilities.value = data ?? []
  loading.value = false
}

onMounted(load)

async function openBooking(f) {
  selected.value = f
  detailLoading.value = true
  bookStep.value = 'form'
  bookForm.value = { date: new Date().toISOString().slice(0,10), courts: 1, team_name: '', notes: '' }
  const { data } = await supabase.rpc('get_facility_detail', { p_facility_id: f.id })
  detail.value = data ?? null
  detailLoading.value = false
}

function proceedToPay() {
  if (!bookForm.value.team_name.trim()) return
  bookStep.value = 'payment'
}

const schedule = computed(() => detail.value?.schedule ?? [])
const dayNames = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat']

const weekdaySlots = computed(() => {
  const days = {}
  schedule.value.forEach(s => {
    const d = dayNames[s.day_of_week] ?? s.day_of_week
    if (!days[d]) days[d] = []
    days[d].push(s)
  })
  return Object.entries(days)
})
</script>

<template>
  <div>
    <PageHeader icon="🏢" title="Book a Court" subtitle="Find and request a badminton court near you">
      <template #help>
        <div class="text-xs space-y-1.5">
          <p>Browse courts and submit a booking request.</p>
          <p>The facility will confirm your booking. Online payment is coming soon — fees are paid directly to the facility for now.</p>
        </div>
      </template>
    </PageHeader>

    <!-- Search + emirate filter -->
    <div class="space-y-2 mb-4">
      <div class="flex gap-2">
        <input v-model="search" class="input flex-1" placeholder="Search courts by name…"
          @keyup.enter="load" />
        <button class="btn-primary px-4 shrink-0" @click="load">Go</button>
      </div>
      <div class="flex gap-1.5 overflow-x-auto pb-1">
        <button
          class="shrink-0 px-3 py-1.5 rounded-full text-xs font-semibold border transition-all"
          :class="!emirate ? 'bg-cyan-600 text-white border-cyan-600' : 'border-slate-200 text-slate-500'"
          @click="emirate = ''; load()">All Emirates</button>
        <button v-for="e in emirates" :key="e"
          class="shrink-0 px-3 py-1.5 rounded-full text-xs font-semibold border transition-all"
          :class="emirate === e ? 'bg-cyan-600 text-white border-cyan-600' : 'border-slate-200 text-slate-500'"
          @click="emirate = e; load()">{{ e }}</button>
      </div>
    </div>

    <!-- Loading -->
    <div v-if="loading" class="space-y-3">
      <div v-for="i in 4" :key="i" class="h-24 shimmer rounded-2xl" />
    </div>

    <!-- Empty -->
    <div v-else-if="!facilities.length" class="card p-10 text-center fade-up">
      <div class="text-4xl mb-3">🏢</div>
      <p class="font-bold text-slate-600 text-lg mb-1">No courts found</p>
      <p class="text-slate-400 text-sm">Try a different search or emirate filter.</p>
    </div>

    <!-- Facility list -->
    <div v-else class="space-y-3 fade-up">
      <div v-for="f in facilities" :key="f.id"
        class="card p-4 cursor-pointer hover:border-cyan-400/40 transition-all active:scale-[0.99]">

        <div class="flex items-start gap-3">
          <!-- Icon / image -->
          <div class="w-14 h-14 rounded-xl bg-slate-100 flex items-center justify-center text-2xl shrink-0 overflow-hidden">
            <img v-if="f.image_url" :src="f.image_url" class="w-full h-full object-cover" />
            <span v-else>🏢</span>
          </div>

          <div class="flex-1 min-w-0">
            <h3 class="font-bold text-slate-800 text-sm">{{ f.name }}</h3>
            <p class="text-xs text-slate-400 mt-0.5">
              <span v-if="f.emirate">{{ f.emirate }}</span>
              <span v-if="f.address" class="ml-1">· {{ f.address }}</span>
            </p>
            <p v-if="f.description" class="text-xs text-slate-500 mt-1 line-clamp-2">{{ f.description }}</p>
          </div>
        </div>

        <!-- Action row -->
        <div class="flex items-center justify-between mt-3 pt-3 border-t border-slate-100">
          <div class="flex gap-3 text-xs text-slate-400">
            <span v-if="f.courts_count">🏸 {{ f.courts_count }} courts</span>
            <span v-if="f.total_bookings">📅 {{ f.total_bookings }} bookings</span>
          </div>
          <div class="flex gap-2">
            <button class="btn-ghost text-xs px-3 py-1.5"
              @click="router.push('/facility/' + f.id)">
              View →
            </button>
            <button class="btn-primary text-xs px-3 py-1.5"
              @click="openBooking(f)">
              Request Booking
            </button>
          </div>
        </div>
      </div>
    </div>
  </div>

  <!-- ── Booking Sheet ── -->
  <Teleport to="body">
    <div v-if="selected"
      class="fixed inset-0 z-50 flex items-end sm:items-center justify-center"
      style="background:rgba(0,0,0,.55); backdrop-filter:blur(4px)"
      @click.self="selected = null">

      <div class="w-full max-w-lg rounded-t-3xl sm:rounded-3xl overflow-y-auto max-h-[90vh]"
        style="background:#f8fafc; border:1px solid rgba(0,168,204,.25)">

        <!-- Header -->
        <div class="flex items-center justify-between px-5 py-4 border-b border-slate-100">
          <div>
            <h3 class="font-display font-bold text-slate-800">{{ selected.name }}</h3>
            <p class="text-xs text-slate-400">{{ selected.emirate }}</p>
          </div>
          <button class="text-slate-400 hover:text-slate-700 text-xl" @click="selected = null">✕</button>
        </div>

        <!-- Loading detail -->
        <div v-if="detailLoading" class="p-6">
          <div class="space-y-2">
            <div v-for="i in 3" :key="i" class="h-10 shimmer rounded-xl" />
          </div>
        </div>

        <!-- Step: form -->
        <div v-else-if="bookStep === 'form'" class="p-5 space-y-4">
          <!-- Schedule info -->
          <div v-if="weekdaySlots.length" class="rounded-xl px-3 py-2.5"
            style="background:rgba(0,168,204,.06); border:1px solid rgba(0,168,204,.2)">
            <p class="text-[10px] uppercase tracking-widest text-neon font-bold mb-2">Available Schedule</p>
            <div class="flex flex-wrap gap-1.5">
              <span v-for="[day, slots] in weekdaySlots" :key="day"
                class="text-[10px] font-medium bg-white border border-cyan-200 text-cyan-700 rounded-full px-2 py-0.5">
                {{ day }} · {{ slots.length }} slot{{ slots.length > 1 ? 's' : '' }}
              </span>
            </div>
          </div>

          <div>
            <label class="label">Preferred Date</label>
            <input v-model="bookForm.date" type="date" class="input" />
          </div>
          <div>
            <label class="label">Number of Courts</label>
            <select v-model="bookForm.courts" class="input">
              <option v-for="n in 4" :key="n" :value="n">{{ n }} court{{ n > 1 ? 's' : '' }}</option>
            </select>
          </div>
          <div>
            <label class="label">Team / Group Name *</label>
            <input v-model="bookForm.team_name" class="input" placeholder="e.g. Dubai Smashers" />
          </div>
          <div>
            <label class="label">Additional Notes</label>
            <textarea v-model="bookForm.notes" class="input resize-none" rows="2"
              placeholder="Preferred time, number of players, special requests…" />
          </div>

          <div class="flex gap-3">
            <button class="btn-ghost flex-1" @click="selected = null">Cancel</button>
            <button class="btn-primary flex-1"
              :disabled="!bookForm.team_name.trim()"
              @click="proceedToPay">
              Continue →
            </button>
          </div>
        </div>

        <!-- Step: payment placeholder -->
        <div v-else-if="bookStep === 'payment'" class="p-5">
          <div class="text-center mb-5">
            <div class="w-16 h-16 rounded-2xl flex items-center justify-center text-3xl mx-auto mb-3"
              style="background:rgba(251,191,36,.12); border:1px solid rgba(251,191,36,.3)">
              💳
            </div>
            <h3 class="font-display font-bold text-slate-800 text-lg">Payment Gateway</h3>
          </div>

          <!-- Booking summary -->
          <div class="rounded-xl p-4 mb-4 space-y-2 text-sm"
            style="background:rgba(0,168,204,.05); border:1px solid rgba(0,168,204,.15)">
            <div class="flex justify-between">
              <span class="text-slate-500">Court</span>
              <span class="font-semibold text-slate-800">{{ selected.name }}</span>
            </div>
            <div class="flex justify-between">
              <span class="text-slate-500">Date</span>
              <span class="font-semibold text-slate-800">{{ bookForm.date }}</span>
            </div>
            <div class="flex justify-between">
              <span class="text-slate-500">Courts</span>
              <span class="font-semibold text-slate-800">{{ bookForm.courts }}</span>
            </div>
            <div class="flex justify-between">
              <span class="text-slate-500">Team</span>
              <span class="font-semibold text-slate-800 truncate ml-4">{{ bookForm.team_name }}</span>
            </div>
          </div>

          <!-- Not enabled notice -->
          <div class="rounded-2xl p-5 text-center"
            style="background:rgba(251,191,36,.08); border:2px dashed rgba(251,191,36,.35)">
            <div class="text-2xl mb-2">🚧</div>
            <p class="font-bold text-amber-700 text-base mb-2">
              Online Payment Not Yet Available
            </p>
            <p class="text-xs text-slate-600 leading-relaxed mb-3">
              Payment gateway integration is coming soon.<br>
              To confirm your booking, please contact the facility directly:
            </p>
            <p v-if="selected.phone" class="font-semibold text-slate-800 text-sm">
              📞 {{ selected.phone }}
            </p>
            <p v-if="selected.email" class="font-semibold text-slate-800 text-sm mt-1">
              ✉️ {{ selected.email }}
            </p>
            <p v-if="!selected.phone && !selected.email"
              class="text-xs text-slate-400 italic">
              Contact details not listed. View the facility profile for more info.
            </p>
          </div>

          <div class="flex gap-3 mt-5">
            <button class="btn-ghost flex-1" @click="bookStep = 'form'">← Back</button>
            <button class="btn-primary flex-1"
              @click="router.push('/facility/' + selected.id); selected = null">
              View Facility →
            </button>
          </div>
        </div>

      </div>
    </div>
  </Teleport>
</template>
