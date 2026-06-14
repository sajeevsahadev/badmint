<script setup>
import { ref, computed, watch, onMounted, onUnmounted } from 'vue'
import { supabase } from '../lib/supabase'
import { withNicknames } from '../lib/playerNames'
import { useClub } from '../composables/useClub'
import { useAuth } from '../composables/useAuth'
import { usePushNotifications } from '../composables/usePushNotifications'
import PageHeader from '../components/PageHeader.vue'

const { currentClub } = useClub()
const { user } = useAuth()
const { isSupported: pushSupported, subscribe: subscribePush, isSubscribed, getPermission } = usePushNotifications()

// ── Calendar state ──
const today    = new Date()
const todayStr = fmtDate(today)
const viewYear  = ref(today.getFullYear())
const viewMonth = ref(today.getMonth() + 1)
const selectedDate  = ref(null)
const showDateModal = ref(false)

const MONTHS = ['January','February','March','April','May','June','July','August','September','October','November','December']
const DAYS   = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat']

function fmtDate(d) {
  return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`
}

// ── Schedule data ──
const monthSchedules  = ref([])
const loadingSchedules = ref(false)

const scheduleMap = computed(() => {
  const m = {}
  monthSchedules.value.forEach(s => { m[s.scheduled_date] = s })
  return m
})

const selectedSchedule = computed(() => selectedDate.value ? scheduleMap.value[selectedDate.value] : null)

// ── Calendar grid ──
const calendarDays = computed(() => {
  const y = viewYear.value
  const mo = viewMonth.value
  const firstDow  = new Date(y, mo - 1, 1).getDay()
  const lastDay   = new Date(y, mo, 0).getDate()
  const cells = []
  for (let i = 0; i < firstDow; i++) cells.push(null)
  for (let d = 1; d <= lastDay; d++) {
    const ds = `${y}-${String(mo).padStart(2,'0')}-${String(d).padStart(2,'0')}`
    cells.push({ dateStr: ds, day: d, isToday: ds === todayStr })
  }
  return cells
})

const selectedDateLabel = computed(() => {
  if (!selectedDate.value) return ''
  const [y, m, d] = selectedDate.value.split('-').map(Number)
  const dt = new Date(y, m - 1, d)
  return `${MONTHS[m-1].slice(0,3)} ${d} ${DAYS[dt.getDay()]}`
})

const scheduleHeader = computed(() => {
  if (!selectedSchedule.value) return ''
  const venue = selectedSchedule.value.fac_name || selectedSchedule.value.facility_name
  return venue ? `Match on ${selectedDateLabel.value} at ${venue}` : `Match on ${selectedDateLabel.value}`
})

// ── Facility picker ──
const facilities      = ref([])
const clubFacilityIds = ref(new Set())
const facilitySearch  = ref('')
const showFacilityPicker  = ref(false)
const showCreateFacility  = ref(false)
const newFacName          = ref('')
const loadingFacilities   = ref(false)

const filteredFacilities = computed(() => {
  const q = facilitySearch.value.trim().toLowerCase()
  let list = facilities.value
  if (q) list = list.filter(f => f.name.toLowerCase().includes(q) || (f.address || '').toLowerCase().includes(q))
  return [...list].sort((a, b) => {
    const au = clubFacilityIds.value.has(a.id) ? 1 : 0
    const bu = clubFacilityIds.value.has(b.id) ? 1 : 0
    if (bu !== au) return bu - au
    return a.name.localeCompare(b.name)
  })
})

const clubFacilities  = computed(() => filteredFacilities.value.filter(f => clubFacilityIds.value.has(f.id)))
const otherFacilities = computed(() => filteredFacilities.value.filter(f => !clubFacilityIds.value.has(f.id)))

// ── Poll / votes ──
const votes        = ref([])
const votesFilter  = ref('all')
const showVotesModal = ref(false)
const votesLoading = ref(false)
const voting       = ref(null)

const filteredVotes = computed(() => {
  if (votesFilter.value === 'all') return votes.value
  return votes.value.filter(v => v.vote === votesFilter.value)
})

// ── Attendees ──
const allPlayers     = ref([])
const attendeeIds    = ref(new Set())
const savingAttendees = ref(false)
const attendeesDirty  = ref(false)

// ── Invite ──
const showInvitePanel = ref(false)
const copied          = ref(false)
let _copiedTimer = null
onUnmounted(() => clearTimeout(_copiedTimer))
const shareUrl = computed(() =>
  selectedSchedule.value ? `${window.location.origin}/poll/${selectedSchedule.value.id}` : ''
)

// ── Errors ──
const scheduleError = ref(null)

// ── Push subscription ──
const pushSubscribed   = ref(false)
const pushPermission   = ref('default')
const subscribingPush  = ref(false)

// ── Load ──
async function loadMonthSchedules() {
  if (!currentClub.value) return
  loadingSchedules.value = true
  const { data } = await supabase.rpc('get_club_schedule', {
    p_club_id: currentClub.value.club_id,
    p_year:    viewYear.value,
    p_month:   viewMonth.value
  })
  monthSchedules.value = data ?? []
  loadingSchedules.value = false
}

async function loadClubFacilityIds() {
  if (!currentClub.value) return
  const { data } = await supabase
    .from('club_schedule')
    .select('facility_id')
    .eq('club_id', currentClub.value.club_id)
    .not('facility_id', 'is', null)
  clubFacilityIds.value = new Set((data ?? []).map(r => r.facility_id))
}

async function openFacilityPicker() {
  showFacilityPicker.value = true
  facilitySearch.value = ''
  showCreateFacility.value = false
  if (facilities.value.length > 0) return
  loadingFacilities.value = true
  const { data } = await supabase.rpc('get_facilities')
  facilities.value = data ?? []
  loadingFacilities.value = false
}

async function loadVotes(scheduleId) {
  votesLoading.value = true
  const { data, error } = await supabase.rpc('get_schedule_votes', { p_schedule_id: scheduleId })
  if (error) { /* votes are non-critical; silently continue */ }
  votes.value = data ?? []
  votesLoading.value = false
}

async function loadVotesAndAttendees(scheduleId) {
  const [aRes, pRes] = await Promise.all([
    supabase.rpc('get_schedule_attendees', { p_schedule_id: scheduleId }),
    supabase.from('players').select('id, display_name, elo, user_id')
      .eq('club_id', currentClub.value.club_id).eq('is_active', true).order('display_name')
  ])
  await loadVotes(scheduleId)
  attendeeIds.value  = new Set((aRes.data ?? []).map(a => a.player_id))
  allPlayers.value   = await withNicknames(pRes.data ?? [])
  attendeesDirty.value = false
}

// ── Calendar interaction ──
async function selectDate(dateStr) {
  if (selectedDate.value === dateStr) { closeDateModal(); return }
  selectedDate.value = dateStr
  showDateModal.value = true
  showInvitePanel.value = false
  votes.value = []
  attendeeIds.value = new Set()
  if (scheduleMap.value[dateStr]) {
    await loadVotesAndAttendees(scheduleMap.value[dateStr].id)
  }
}

function closeDateModal() {
  showDateModal.value = false
  selectedDate.value  = null
}

// ── Create / update schedule (direct table ops — no RPC) ──
async function createSchedule(facilityId, facilityName) {
  const existing = selectedSchedule.value
  let schedId = existing?.id
  let error

  if (schedId) {
    // Update existing row's venue only
    const res = await supabase
      .from('club_schedule')
      .update({ facility_id: facilityId ?? null, facility_name: facilityName ?? null })
      .eq('id', schedId)
    error = res.error
  } else {
    // Insert new schedule row
    const res = await supabase
      .from('club_schedule')
      .insert({
        club_id:        currentClub.value.club_id,
        scheduled_date: selectedDate.value,
        facility_id:    facilityId ?? null,
        facility_name:  facilityName ?? null,
        created_by:     user.value.id
      })
      .select('id')
      .single()
    error   = res.error
    schedId = res.data?.id
  }

  if (error) { scheduleError.value = error.message; return }
  scheduleError.value = null
  showFacilityPicker.value = false
  const isNew = !existing
  await loadMonthSchedules()
  await loadClubFacilityIds()
  if (schedId) await loadVotesAndAttendees(schedId)

  // Notify subscribers only when a NEW schedule is created (not venue edits)
  if (isNew && schedId) {
    const facName = facilityId
      ? (facilities.value.find(f => f.id === facilityId)?.name ?? 'TBD')
      : (facilityName ?? 'TBD')
    supabase.functions.invoke('send-push', {
      body: {
        schedule_id: schedId,
        title: '🏸 Match Day Planned',
        body: `${selectedDateLabel.value} at ${facName} — vote now!`,
        url: `${window.location.origin}/poll/${schedId}`
      }
    }).catch(() => null)
  }
}

async function pickFacility(fac) {
  await createSchedule(fac.id, null)
}

async function useCustomVenue() {
  const name = newFacName.value.trim()
  if (!name) return

  // Create in the facilities master table first so it appears in Explore → Facilities
  const { data: facId, error: facErr } = await supabase.rpc('create_facility', { p_name: name })
  if (facErr) { scheduleError.value = facErr.message; return }
  scheduleError.value = null

  // Link the schedule to the new facility by ID (not free text)
  await createSchedule(facId, null)
  newFacName.value = ''
  showCreateFacility.value = false
}

// ── Voting ──
async function castVote(option) {
  if (!selectedSchedule.value) return
  voting.value = option
  await supabase.rpc('vote_schedule', {
    p_schedule_id: selectedSchedule.value.id,
    p_vote:        option
  })
  voting.value = null
  await Promise.all([loadMonthSchedules(), loadVotes(selectedSchedule.value.id)])
}

// ── View votes modal ──
async function openVotesModal() {
  votesFilter.value = 'all'
  showVotesModal.value = true
  await loadVotes(selectedSchedule.value.id)
}

// ── Attendees ──
function toggleAttendee(playerId) {
  const next = new Set(attendeeIds.value)
  next.has(playerId) ? next.delete(playerId) : next.add(playerId)
  attendeeIds.value = next
  attendeesDirty.value = true
}

async function saveAttendees() {
  if (!selectedSchedule.value) return
  savingAttendees.value = true
  await supabase.rpc('set_schedule_attendees', {
    p_schedule_id: selectedSchedule.value.id,
    p_player_ids:  [...attendeeIds.value]
  })
  savingAttendees.value = false
  attendeesDirty.value = false
}

// ── Share ──
async function copyLink() {
  await navigator.clipboard.writeText(shareUrl.value)
  copied.value = true
  clearTimeout(_copiedTimer)
  _copiedTimer = setTimeout(() => { copied.value = false }, 2500)
}

function shareWhatsApp() {
  const msg = encodeURIComponent(`Join our match! ${scheduleHeader.value}\nVote here: ${shareUrl.value}`)
  window.open(`https://wa.me/?text=${msg}`, '_blank')
}

// ── Push notifications ──
async function checkPushStatus() {
  if (!pushSupported) return
  pushPermission.value = await getPermission()
  pushSubscribed.value = await isSubscribed()
}

async function handleSubscribePush() {
  subscribingPush.value = true
  try {
    await subscribePush(currentClub.value.club_id)
    pushSubscribed.value = true
    pushPermission.value = 'granted'
  } catch (e) {
    alert(e.message)
  }
  subscribingPush.value = false
}

// ── Month nav ──
function prevMonth() {
  if (viewMonth.value === 1) { viewMonth.value = 12; viewYear.value-- }
  else viewMonth.value--
  selectedDate.value = null
  loadMonthSchedules()
}

function nextMonth() {
  if (viewMonth.value === 12) { viewMonth.value = 1; viewYear.value++ }
  else viewMonth.value++
  selectedDate.value = null
  loadMonthSchedules()
}

// ── Vote timestamp display ──
function timeAgo(ts) {
  const d    = new Date(ts)
  const diff = Date.now() - d.getTime()
  const mins = Math.floor(diff / 60000)
  const hrs  = Math.floor(diff / 3600000)
  const days = Math.floor(diff / 86400000)
  if (mins < 1)  return 'just now'
  if (mins < 60) return `${mins}m ago`
  if (hrs  < 24) return `${hrs}h ago`
  if (days === 1) return 'yesterday'
  if (days < 7)  return d.toLocaleDateString('en-US', { weekday: 'short' })
  return d.toLocaleDateString('en-US', { month: 'short', day: 'numeric' })
}

// ── circle colour for scheduled calendar cell ──
function scheduleBg(schedule) {
  if (!schedule) return ''
  if (schedule.status === 'cancelled')      return 'bg-slate-500 text-white'
  if (schedule.my_vote === 'attending')     return 'bg-emerald-500 text-white'
  if (schedule.my_vote === 'not_attending') return 'bg-rose-500 text-white'
  return 'bg-cyan-400 text-slate-900'
}

// ── Init ──
onMounted(async () => {
  await loadMonthSchedules()
  await loadClubFacilityIds()
  await checkPushStatus()
})

watch(currentClub, async () => {
  selectedDate.value = null
  votes.value = []
  attendeeIds.value = new Set()
  await loadMonthSchedules()
  await loadClubFacilityIds()
})
</script>

<template>
  <div v-if="!currentClub" class="card p-8 text-center">
    <div class="text-3xl mb-3">📅</div>
    <p class="text-sm text-slate-400">Select a club to view the playing schedule.</p>
  </div>

  <template v-else>
    <PageHeader icon="📅" title="Schedule" subtitle="Plan match days, run polls, track who's coming">
      <template #help>
        <div class="text-xs space-y-1.5">
          <p><strong class="text-slate-800">Tap any date</strong> to plan a match or see the existing schedule.</p>
          <p><strong class="text-slate-800">Poll</strong> — Let your team vote Attending / Not Attending before the day.</p>
          <p><strong class="text-slate-800">Invite</strong> — Copy a shareable link or send via WhatsApp. Club members can vote directly from the link.</p>
          <p><strong class="text-slate-800">Attendees</strong> — On match day, tick who actually showed up. These players will appear first when recording a match.</p>
          <p><strong class="text-slate-800">Notifications</strong> — Enable push so the app alerts you when a new match day is posted.</p>
        </div>
      </template>
    </PageHeader>

    <!-- Error banner -->
    <div v-if="scheduleError"
      class="mb-3 px-3 py-2 rounded-xl text-xs font-medium text-rose-300 flex items-center gap-2"
      style="background:rgba(239,68,68,.12); border:1px solid rgba(239,68,68,.25)">
      <span>⚠️</span><span>{{ scheduleError }}</span>
      <button class="ml-auto text-rose-400" @click="scheduleError = null">✕</button>
    </div>

    <!-- Push notification subscribe banner -->
    <div v-if="pushSupported && !pushSubscribed && pushPermission !== 'denied'"
      class="card mb-4 px-4 py-3 flex items-center gap-3">
      <span class="text-xl shrink-0">🔔</span>
      <div class="flex-1 min-w-0">
        <div class="text-xs font-bold text-slate-200">Get match alerts</div>
        <div class="text-[10px] text-slate-500">Push notification when your manager plans a new match day</div>
      </div>
      <button class="btn-ghost text-xs px-3 py-1.5 shrink-0" :disabled="subscribingPush"
        @click="handleSubscribePush">
        {{ subscribingPush ? '…' : 'Enable' }}
      </button>
    </div>

    <!-- Month nav -->
    <div class="flex items-center justify-between mb-3">
      <button class="w-9 h-9 rounded-xl border border-slate-200 flex items-center justify-center text-slate-500 hover:border-slate-400 transition"
        @click="prevMonth">‹</button>
      <div class="font-display font-bold tracking-tight text-slate-800">
        {{ MONTHS[viewMonth - 1] }} {{ viewYear }}
        <span v-if="loadingSchedules" class="text-xs text-slate-400 ml-2 animate-pulse">loading…</span>
      </div>
      <button class="w-9 h-9 rounded-xl border border-slate-200 flex items-center justify-center text-slate-500 hover:border-slate-400 transition"
        @click="nextMonth">›</button>
    </div>

    <!-- Day headers -->
    <div class="grid grid-cols-7 gap-1 mb-1 text-center">
      <span v-for="d in ['Su','Mo','Tu','We','Th','Fr','Sa']" :key="d"
        class="text-[10px] text-slate-600 font-medium">{{ d }}</span>
    </div>

    <!-- Calendar grid -->
    <div class="grid grid-cols-7 gap-1 mb-4">
      <div v-for="(cell, i) in calendarDays" :key="i"
        class="aspect-square"
        :class="!cell ? 'pointer-events-none' : ''">
        <button v-if="cell"
          class="w-full h-full flex items-center justify-center rounded-xl transition hover:bg-white/[0.04]"
          @click="selectDate(cell.dateStr)">
          <span class="w-8 h-8 rounded-full flex items-center justify-center text-sm font-medium transition"
            :class="[
              cell.dateStr === selectedDate
                ? 'bg-cyan-500 text-white font-bold ring-2 ring-cyan-300'
                : scheduleMap[cell.dateStr]
                  ? scheduleBg(scheduleMap[cell.dateStr])
                  : cell.isToday
                    ? 'ring-2 ring-slate-400 text-slate-200 font-bold'
                    : 'text-slate-400'
            ]">
            {{ cell.day }}
          </span>
        </button>
      </div>
    </div>

    <!-- Legend -->
    <div class="flex gap-4 text-[10px] text-slate-600 mb-5">
      <span class="flex items-center gap-1"><span class="w-4 h-4 rounded-full bg-emerald-500 inline-block"></span>You're in</span>
      <span class="flex items-center gap-1"><span class="w-4 h-4 rounded-full bg-rose-500 inline-block"></span>Can't make it</span>
      <span class="flex items-center gap-1"><span class="w-4 h-4 rounded-full bg-cyan-400 inline-block"></span>Planned</span>
    </div>

    <div class="text-center text-xs text-slate-600 py-2">Tap a date to plan or view a match day</div>

    <!-- ── Date detail modal ── -->
    <Teleport to="body">
      <div v-if="showDateModal" class="fixed inset-0 z-50">
        <div class="absolute inset-0 bg-black/70" @click="closeDateModal" />
        <div class="absolute bottom-0 left-0 right-0 rounded-t-2xl overflow-hidden"
          style="background:#0a1628; max-height:90vh; border-top:1px solid rgba(255,255,255,.1)">

          <!-- Sticky header -->
          <div class="sticky top-0 px-4 pt-3 pb-3 z-10"
            style="background:#0a1628; border-bottom:1px solid rgba(255,255,255,.07)">
            <div class="w-10 h-1 rounded-full bg-white/20 mx-auto mb-3" />
            <div class="flex items-center justify-between">
              <span class="font-semibold text-slate-200">{{ selectedDateLabel }}</span>
              <button @click="closeDateModal" class="text-slate-400 hover:text-slate-200 text-lg leading-none">✕</button>
            </div>
          </div>

          <!-- Scrollable content -->
          <div class="overflow-y-auto px-4 pb-28" style="max-height: calc(90vh - 72px)">

            <!-- No schedule: plan prompt -->
            <div v-if="!selectedSchedule" class="pt-8 pb-4 text-center">
              <div class="text-4xl mb-3">🏸</div>
              <div class="font-semibold text-slate-200 text-lg mb-1">Plan a match on {{ selectedDateLabel }}</div>
              <div class="text-xs text-slate-500 mb-6">Pick a venue to create this match day and open the poll.</div>
              <button class="btn-primary w-full py-3" @click="openFacilityPicker">📍 Set Venue &amp; Schedule</button>
            </div>

            <!-- Schedule exists -->
            <div v-else class="space-y-4 pt-4">

              <!-- Header -->
              <div class="card-neon p-4">
                <div class="font-display text-lg font-bold gradient-text leading-snug mb-1">{{ scheduleHeader }}</div>
                <div v-if="selectedSchedule.status === 'cancelled'"
                  class="inline-block text-xs bg-rose-500/20 text-rose-400 rounded px-2 py-0.5">Cancelled</div>

                <div class="flex gap-2 mt-3">
                  <button class="btn-primary flex-1 py-2 text-sm" @click="showInvitePanel = !showInvitePanel">
                    {{ showInvitePanel ? '✕ Close' : '📢 Invite' }}
                  </button>
                  <button class="btn-ghost text-xs px-3" @click="openFacilityPicker">✏️ Edit Venue</button>
                </div>

                <!-- Invite / share panel -->
                <div v-if="showInvitePanel" class="mt-3 pt-3 border-t border-slate-100 space-y-2">
                  <div class="text-xs text-slate-500">Share poll link with your group:</div>
                  <div class="flex gap-2">
                    <input :value="shareUrl" readonly
                      class="flex-1 rounded-lg border border-slate-200 bg-slate-50 px-3 py-2 text-xs font-mono text-slate-500 outline-none truncate" />
                    <button class="btn-ghost text-xs px-3 shrink-0" @click="copyLink">
                      {{ copied ? '✓ Copied' : 'Copy' }}
                    </button>
                  </div>
                  <button class="w-full rounded-xl py-2.5 text-sm font-medium transition"
                    style="background:rgba(37,211,102,.15); border:1px solid rgba(37,211,102,.3); color:#25d366"
                    @click="shareWhatsApp">
                    💬 Share via WhatsApp
                  </button>
                </div>
              </div>

              <!-- Poll -->
              <div class="card p-4">
                <div class="text-[10px] uppercase tracking-widest text-slate-500 mb-3">Match Poll</div>
                <div class="grid grid-cols-2 gap-2 mb-3">
                  <button
                    @click="castVote('attending')"
                    :disabled="voting !== null"
                    class="rounded-xl p-3 flex flex-col items-center gap-1 border transition"
                    :class="selectedSchedule.my_vote === 'attending'
                      ? 'bg-emerald-50 border-emerald-400'
                      : 'border-slate-200 hover:border-slate-300'">
                    <span class="text-2xl">✅</span>
                    <span class="text-xs font-semibold text-slate-700">Attending</span>
                    <span class="text-2xl font-bold text-emerald-400">{{ selectedSchedule.attending_count }}</span>
                  </button>
                  <button
                    @click="castVote('not_attending')"
                    :disabled="voting !== null"
                    class="rounded-xl p-3 flex flex-col items-center gap-1 border transition"
                    :class="selectedSchedule.my_vote === 'not_attending'
                      ? 'bg-rose-50 border-rose-400'
                      : 'border-slate-200 hover:border-slate-300'">
                    <span class="text-2xl">❌</span>
                    <span class="text-xs font-semibold text-slate-700">Not Attending</span>
                    <span class="text-2xl font-bold text-rose-400">{{ selectedSchedule.not_attending_count }}</span>
                  </button>
                </div>

                <div class="flex items-center justify-between text-xs">
                  <span v-if="selectedSchedule.my_vote" :class="selectedSchedule.my_vote === 'attending' ? 'text-emerald-400' : 'text-rose-400'">
                    Your vote: {{ selectedSchedule.my_vote === 'attending' ? 'Attending ✓' : 'Not Attending ✓' }}
                  </span>
                  <span v-else class="text-slate-600">Tap to cast your vote</span>
                  <button class="text-slate-500 underline" @click="openVotesModal">View Votes</button>
                </div>
              </div>

              <!-- Attendees -->
              <div class="card p-4">
                <div class="flex items-center justify-between mb-3">
                  <div>
                    <div class="text-[10px] uppercase tracking-widest text-slate-500">Actual Attendees</div>
                    <div class="text-[10px] text-slate-600 mt-0.5">Who actually showed up — used in Add Match player list</div>
                  </div>
                  <span class="text-[9px] px-2 py-0.5 rounded-full font-bold" style="background:rgba(0,153,184,.12);color:#0077a8">
                    {{ attendeeIds.size }}/{{ allPlayers.length }}
                  </span>
                </div>

                <div v-if="allPlayers.length === 0" class="text-xs text-slate-600 italic py-2">
                  No active players in roster yet.
                </div>

                <div class="space-y-1 mb-3">
                  <label v-for="p in allPlayers" :key="p.id"
                    class="flex items-center gap-3 py-1.5 px-2 rounded-lg cursor-pointer hover:bg-slate-50 transition">
                    <div class="w-5 h-5 rounded border shrink-0 flex items-center justify-center transition"
                      :class="attendeeIds.has(p.id) ? 'bg-emerald-500 border-emerald-500' : 'border-slate-300'"
                      @click="toggleAttendee(p.id)">
                      <span v-if="attendeeIds.has(p.id)" class="text-[10px] text-white font-bold">✓</span>
                    </div>
                    <span class="text-sm flex-1" :class="attendeeIds.has(p.id) ? 'text-slate-900 font-semibold' : 'text-slate-500'"
                      @click="toggleAttendee(p.id)">
                      {{ p.display_name }}
                    </span>
                    <span class="text-[10px] text-slate-400">{{ Math.round(p.elo) }}</span>
                  </label>
                </div>

                <button class="btn-success w-full py-2.5 text-sm"
                  :disabled="!attendeesDirty || savingAttendees"
                  @click="saveAttendees">
                  {{ savingAttendees ? 'Saving…' : `✓ Save Attendees (${attendeeIds.size})` }}
                </button>
                <div v-if="!attendeesDirty && attendeeIds.size > 0" class="text-[10px] text-slate-600 text-center mt-1.5">
                  Saved · Add Match will show only these {{ attendeeIds.size }} players
                </div>
              </div>

            </div>
          </div>
        </div>
      </div>
    </Teleport>

    <!-- ── Facility picker bottom sheet ── -->
    <Teleport to="body">
      <div v-if="showFacilityPicker" class="fixed inset-0 z-[60]">
        <div class="absolute inset-0 bg-black/70" @click="showFacilityPicker = false" />
        <div class="absolute bottom-0 left-0 right-0 rounded-t-2xl overflow-hidden"
          style="background:#0a1628; max-height:82vh; border-top:1px solid rgba(255,255,255,.1)">

          <!-- Sticky header -->
          <div class="sticky top-0 px-4 pt-3 pb-3" style="background:#0a1628">
            <div class="w-10 h-1 rounded-full bg-white/20 mx-auto mb-3" />
            <div class="flex items-center justify-between mb-3">
              <span class="font-semibold">Select Venue — {{ selectedDateLabel }}</span>
              <button @click="showFacilityPicker = false" class="text-slate-400 hover:text-slate-200">✕</button>
            </div>
            <input v-model="facilitySearch" placeholder="Search venues…"
              class="w-full rounded-xl border border-white/10 bg-white/[0.03] px-3 py-2.5 text-sm outline-none focus:border-cyan-500/40 transition" />
          </div>

          <!-- Scrollable list -->
          <div class="overflow-y-auto px-4 pb-8" style="max-height: calc(82vh - 130px)">
            <div v-if="loadingFacilities" class="text-center text-sm text-slate-500 py-6 animate-pulse">
              Loading venues…
            </div>

            <template v-if="!loadingFacilities">
              <!-- Club's facilities first -->
              <template v-if="!facilitySearch && clubFacilities.length">
                <div class="text-[10px] uppercase tracking-widest text-slate-600 mb-2 mt-1">Your Club's Venues</div>
                <div v-for="f in clubFacilities" :key="f.id"
                  class="card px-3 py-3 mb-1.5 cursor-pointer hover:border-cyan-500/40 active:opacity-70 transition"
                  @click="pickFacility(f)">
                  <div class="text-sm font-medium">{{ f.name }}</div>
                  <div v-if="f.address" class="text-[11px] text-slate-500 mt-0.5">{{ f.address }}</div>
                </div>
                <div v-if="otherFacilities.length" class="text-[10px] uppercase tracking-widest text-slate-600 mb-2 mt-4">All Venues</div>
              </template>

              <!-- Other / all facilities -->
              <div v-for="f in (facilitySearch ? filteredFacilities : otherFacilities)" :key="f.id"
                class="card px-3 py-3 mb-1.5 cursor-pointer hover:border-cyan-500/40 active:opacity-70 transition"
                @click="pickFacility(f)">
                <div class="text-sm font-medium">{{ f.name }}</div>
                <div v-if="f.address" class="text-[11px] text-slate-500 mt-0.5">{{ f.address }}</div>
              </div>

              <div v-if="filteredFacilities.length === 0" class="text-sm text-slate-500 text-center py-4">
                No venues found for "{{ facilitySearch }}"
              </div>

              <!-- Custom venue -->
              <div class="mt-4 pt-4 border-t border-white/10">
                <div class="text-xs text-slate-500 mb-2">Venue not listed?</div>
                <div v-if="!showCreateFacility">
                  <button class="btn-ghost w-full text-sm py-2.5" @click="showCreateFacility = true">
                    ➕ Use a custom venue name
                  </button>
                </div>
                <div v-else class="space-y-2">
                  <input v-model="newFacName" placeholder="e.g. Al Nasr Sports Club, Dubai"
                    class="w-full rounded-xl border border-white/10 bg-white/[0.03] px-3 py-2.5 text-sm outline-none focus:border-cyan-500/40" />
                  <div class="flex gap-2">
                    <button class="btn-primary flex-1 py-2 text-sm"
                      :disabled="!newFacName.trim()"
                      @click="useCustomVenue">Use This Venue</button>
                    <button class="btn-ghost text-sm px-4"
                      @click="showCreateFacility = false; newFacName = ''">Cancel</button>
                  </div>
                </div>
              </div>

              <!-- No venue / TBD -->
              <button class="btn-ghost w-full text-sm text-slate-500 mt-2"
                @click="createSchedule(null, null)">
                📅 Schedule without venue (TBD)
              </button>
            </template>
          </div>
        </div>
      </div>
    </Teleport>

    <!-- ── Votes modal ── -->
    <Teleport to="body">
      <div v-if="showVotesModal" class="fixed inset-0 z-50 flex items-end justify-center p-4 pb-8">
        <div class="absolute inset-0 bg-black/70" @click="showVotesModal = false" />
        <div class="relative w-full max-w-sm rounded-2xl overflow-hidden"
          style="background:#0a1628; border:1px solid rgba(255,255,255,.1)">
          <div class="p-4 pb-0">
            <div class="flex items-start justify-between mb-3">
              <div>
                <h3 class="font-semibold text-sm">Poll Votes</h3>
                <div class="text-[11px] text-slate-500">{{ selectedDateLabel }}</div>
              </div>
              <button @click="showVotesModal = false" class="text-slate-400 hover:text-slate-200 text-lg">✕</button>
            </div>

            <!-- Tabs -->
            <div class="flex gap-1 mb-3">
              <button v-for="t in ['all','attending','not_attending']" :key="t"
                @click="votesFilter = t"
                class="rounded-lg px-2.5 py-1.5 text-[11px] font-medium transition"
                :class="votesFilter === t ? 'bg-white/10 text-white' : 'text-slate-500 hover:text-slate-300'">
                {{ t === 'all' ? `All (${votes.length})` : t === 'attending' ? `✅ ${votes.filter(v=>v.vote==='attending').length}` : `❌ ${votes.filter(v=>v.vote==='not_attending').length}` }}
              </button>
            </div>
          </div>

          <div class="px-4 pb-5 overflow-y-auto" style="max-height:320px">
            <div v-if="votesLoading" class="text-center text-sm text-slate-500 animate-pulse py-6">Loading…</div>
            <template v-else>
              <div v-if="filteredVotes.length === 0" class="text-sm text-slate-500 text-center py-6">
                No votes yet.
              </div>
              <div v-for="v in filteredVotes" :key="v.user_id"
                class="flex items-center gap-3 py-2.5 border-b border-white/5 last:border-0">
              <div class="w-8 h-8 rounded-full shrink-0 flex items-center justify-center text-xs font-bold text-slate-950"
                style="background:linear-gradient(135deg,#00e5ff,#a855f7)">
                {{ (v.display_name || '?')[0].toUpperCase() }}
              </div>
              <div class="flex-1 min-w-0">
                <div class="text-sm font-medium text-white truncate">{{ v.display_name || 'Unknown' }}</div>
                <div class="text-[10px] text-slate-500">{{ timeAgo(v.voted_at) }}</div>
              </div>
              <span class="text-lg shrink-0" :class="v.vote === 'attending' ? 'text-emerald-400' : 'text-rose-400'">
                {{ v.vote === 'attending' ? '✅' : '❌' }}
              </span>
            </div>
            </template>
          </div>
        </div>
      </div>
    </Teleport>

  </template>
</template>
