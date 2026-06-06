<script setup>
import { ref, computed, watch, onMounted } from 'vue'
import { supabase } from '../lib/supabase'
import { useClub } from '../composables/useClub'
import { useAuth } from '../composables/useAuth'
import PageHeader from '../components/PageHeader.vue'

const { currentClub } = useClub()
const { user } = useAuth()

// ── Constants ──────────────────────────────────────────────────────────
const CURRENCY = 'AED'
const CATEGORIES = [
  { value: 'facility',  label: 'Court Rent',  icon: '🏟️' },
  { value: 'food',      label: 'Food / Snacks', icon: '🍔' },
  { value: 'drinks',    label: 'Water / Tea',  icon: '☕' },
  { value: 'equipment', label: 'Cork / Equipment', icon: '🏸' },
  { value: 'transport', label: 'Transport',    icon: '🚗' },
  { value: 'tax',       label: 'Tax / Fees',   icon: '📋' },
  { value: 'other',     label: 'Other',        icon: '💡' },
]
const MONTHS = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec']

const catIcon  = v => CATEGORIES.find(c => c.value === v)?.icon  ?? '💡'
const catLabel = v => CATEGORIES.find(c => c.value === v)?.label ?? v

const aed = n => `${CURRENCY} ${Number(n).toFixed(2)}`
const fmtDate = d => new Date(d + 'T00:00:00').toLocaleDateString('en-AE', { day: 'numeric', month: 'short', year: 'numeric' })
const timeAgo = ts => {
  const mins = Math.floor((Date.now() - new Date(ts)) / 60000)
  if (mins < 1)  return 'just now'
  if (mins < 60) return `${mins}m ago`
  const hrs = Math.floor(mins / 60)
  if (hrs < 24)  return `${hrs}h ago`
  const days = Math.floor(hrs / 24)
  if (days < 7)  return `${days}d ago`
  return new Date(ts).toLocaleDateString('en-AE', { day: 'numeric', month: 'short' })
}

// ── State ──────────────────────────────────────────────────────────────
const expenses       = ref([])
const balances       = ref([])
const players        = ref([])
const notes          = ref([])
const myPlayer       = ref(null)
const loading        = ref(true)
const activeTab      = ref('activities')
const expandedPlayer = ref(null)

// ── Load all data ──────────────────────────────────────────────────────
async function load() {
  if (!currentClub.value || !user.value) return
  loading.value = true
  const cid = currentClub.value.club_id

  const [plRes, expRes, balRes, noteRes, myPlRes] = await Promise.all([
    supabase.rpc('get_club_players', { p_club_id: cid }),
    supabase.rpc('get_expenses', { p_club_id: cid }),
    supabase.rpc('get_balance_summary', { p_club_id: cid }),
    supabase.from('paysplit_notes')
      .select('id, content, created_at, created_by')
      .eq('club_id', cid).order('created_at', { ascending: false }),
    supabase.from('players')
      .select('id, display_name, user_id')
      .eq('club_id', cid).eq('user_id', user.value.id).maybeSingle()
  ])

  players.value  = plRes.data  ?? []
  expenses.value = expRes.data ?? []
  balances.value = balRes.data ?? []
  myPlayer.value = myPlRes.data

  const noteData = noteRes.data ?? []
  notes.value = noteData.map(n => ({
    ...n,
    author: players.value.find(p => p.user_id === n.created_by)?.display_name ?? 'Member'
  }))

  loading.value = false
}

onMounted(load)
watch(currentClub, () => { expandedPlayer.value = null; load() })

// ── My balance summary (header card) ──────────────────────────────────
const myBalance = computed(() => {
  const mid = myPlayer.value?.id
  if (!mid) return null
  const owe  = []
  const gets = []
  balances.value.forEach(b => {
    if (b.from_player_id === mid) owe.push({ name: b.to_name,   amount: Number(b.net_amount) })
    else if (b.to_player_id === mid) gets.push({ name: b.from_name, amount: Number(b.net_amount) })
  })
  const totalOwe  = owe.reduce((s, x)  => s + x.amount, 0)
  const totalGets = gets.reduce((s, x) => s + x.amount, 0)
  return { owe, gets, totalOwe, totalGets, net: totalGets - totalOwe }
})

// ── My contribution per expense ────────────────────────────────────────
function myContrib(exp) {
  const mid = myPlayer.value?.id
  if (!mid) return null
  const isPayer = exp.paid_player_id === mid
  const part    = exp.participants?.find(p => p.player_id === mid)
  if (!isPayer && !part) return null
  if (isPayer && !part)  return { type: 'paid', net: Number(exp.amount) }
  if (isPayer &&  part)  return { type: 'paid', net: Number(exp.amount) - Number(part.share) }
  return { type: 'split', net: -Number(part.share) }
}

// ── Balance tab: net position per player ───────────────────────────────
const playerBalanceList = computed(() => {
  const map = {}
  players.value.forEach(p => {
    map[p.id] = { id: p.id, name: p.display_name, owes: [], gets: [], net: 0 }
  })
  balances.value.forEach(b => {
    const amt = Number(b.net_amount)
    if (map[b.from_player_id]) {
      map[b.from_player_id].owes.push({ to: b.to_name, toId: b.to_player_id, amount: amt })
      map[b.from_player_id].net -= amt
    }
    if (map[b.to_player_id]) {
      map[b.to_player_id].gets.push({ from: b.from_name, fromId: b.from_player_id, amount: amt })
      map[b.to_player_id].net += amt
    }
  })
  return Object.values(map)
    .filter(p => Math.abs(p.net) >= 0.01)
    .sort((a, b) => {
      if (myPlayer.value?.id === a.id) return -1
      if (myPlayer.value?.id === b.id) return 1
      return Math.abs(b.net) - Math.abs(a.net)
    })
})

// ── Totals tab computeds ───────────────────────────────────────────────
const allTimeTotal = computed(() =>
  expenses.value.reduce((s, e) => s + Number(e.amount), 0)
)
const currentYear = new Date().getFullYear()
const yearTotal = computed(() =>
  expenses.value
    .filter(e => e.expense_date?.startsWith(String(currentYear)))
    .reduce((s, e) => s + Number(e.amount), 0)
)
const last3Months = computed(() => {
  const now = new Date()
  return [2, 1, 0].map(offset => {
    const d   = new Date(now.getFullYear(), now.getMonth() - offset, 1)
    const key = `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}`
    const total = expenses.value
      .filter(e => e.expense_date?.startsWith(key))
      .reduce((s, e) => s + Number(e.amount), 0)
    return { label: MONTHS[d.getMonth()], key, total }
  }).reverse()
})
const barMax = computed(() => Math.max(...last3Months.value.map(m => m.total), 1))

const monthlyTrend = computed(() => {
  const map = {}
  expenses.value.forEach(e => {
    if (!e.expense_date) return
    const key = e.expense_date.slice(0, 7)
    map[key] = (map[key] ?? 0) + Number(e.amount)
  })
  return Object.entries(map)
    .sort((a, b) => b[0].localeCompare(a[0]))
    .map(([key, total]) => {
      const [y, m] = key.split('-').map(Number)
      return { key, label: `${MONTHS[m-1]} ${y}`, total }
    })
})

// ── Add / Edit expense form ────────────────────────────────────────────
const showForm   = ref(false)
const editingId  = ref(null)
const formError  = ref(null)
const formSaving = ref(false)

const blankForm = () => ({
  title: '', category: 'other', amount: '',
  paid_player_id: myPlayer.value?.id ?? '',
  expense_date: new Date().toISOString().slice(0, 10),
  notes: '',
  participant_ids: players.value.filter(p => p.is_active).map(p => p.id)
})

const form = ref(blankForm())

function openAddForm() {
  editingId.value = null
  form.value      = blankForm()
  formError.value = null
  showForm.value  = true
}

function openEditForm(exp) {
  editingId.value = exp.id
  form.value = {
    title:           exp.title,
    category:        exp.category,
    amount:          String(exp.amount),
    paid_player_id:  exp.paid_player_id,
    expense_date:    exp.expense_date,
    notes:           exp.notes ?? '',
    participant_ids: (exp.participants ?? []).map(p => p.player_id)
  }
  formError.value = null
  showForm.value  = true
}

function toggleParticipant(pid) {
  const ids = form.value.participant_ids
  form.value.participant_ids = ids.includes(pid) ? ids.filter(x => x !== pid) : [...ids, pid]
}

async function saveExpense() {
  formError.value = null
  const amt = parseFloat(form.value.amount)
  if (!form.value.title.trim())          { formError.value = 'Title is required'; return }
  if (!amt || amt <= 0)                  { formError.value = 'Enter a valid amount'; return }
  if (!form.value.paid_player_id)        { formError.value = 'Select who paid'; return }
  if (!form.value.participant_ids.length){ formError.value = 'Select at least one participant'; return }

  formSaving.value = true
  const params = {
    p_club_id:        currentClub.value.club_id,
    p_title:          form.value.title.trim(),
    p_category:       form.value.category,
    p_amount:         amt,
    p_paid_player_id: form.value.paid_player_id,
    p_expense_date:   form.value.expense_date,
    p_participant_ids: form.value.participant_ids,
    p_notes:          form.value.notes.trim() || null
  }

  const { error } = editingId.value
    ? await supabase.rpc('update_expense', { p_expense_id: editingId.value, ...params })
    : await supabase.rpc('add_expense', params)

  formSaving.value = false
  if (error) { formError.value = error.message; return }
  showForm.value = false
  await load()
}

// ── Delete expense ─────────────────────────────────────────────────────
const confirmDelId = ref(null)
const deletingId   = ref(null)

async function doDelete() {
  const id = confirmDelId.value
  if (!id) return
  confirmDelId.value = null
  deletingId.value   = id
  await supabase.rpc('delete_expense', { p_expense_id: id })
  deletingId.value = null
  await load()
}

// ── Notes ──────────────────────────────────────────────────────────────
const noteText   = ref('')
const noteSaving = ref(false)

async function addNote() {
  if (!noteText.value.trim()) return
  noteSaving.value = true
  await supabase.from('paysplit_notes').insert({
    club_id:    currentClub.value.club_id,
    content:    noteText.value.trim(),
    created_by: user.value.id
  })
  noteText.value   = ''
  noteSaving.value = false
  await load()
}

async function deleteNote(id) {
  await supabase.from('paysplit_notes').delete().eq('id', id)
  notes.value = notes.value.filter(n => n.id !== id)
}

// Per-share live preview
const perShare = computed(() => {
  const amt = parseFloat(form.value.amount)
  const n   = form.value.participant_ids.length
  if (!amt || !n) return null
  return (amt / n).toFixed(2)
})

const isMe = id => myPlayer.value?.id === id
</script>

<template>
  <div v-if="loading" class="space-y-3">
    <div v-for="i in 4" :key="i" class="h-20 shimmer rounded-2xl" />
  </div>

  <template v-else>
    <PageHeader icon="💰" title="PaySplits" subtitle="Track & split court costs equally among players">
      <template #help>
        <div class="text-xs space-y-1.5">
          <p><strong class="text-slate-800">Add Expense</strong> — Record any shared cost (rent, tea, cork). Select who paid and who splits it.</p>
          <p><strong class="text-slate-800">Activities</strong> — Full expense list with your contribution per item.</p>
          <p><strong class="text-slate-800">Balance</strong> — Who owes whom across all expenses. Tap a name to see the breakdown.</p>
          <p><strong class="text-slate-800">Totals</strong> — Monthly spending charts and all-time summary.</p>
          <p><strong class="text-slate-800">Notes</strong> — Shared notepad for payment reminders or group agreements.</p>
        </div>
      </template>
    </PageHeader>

    <!-- ── Summary card ── -->
    <div class="card-neon p-4 mb-4 fade-up">
      <div class="text-[10px] uppercase tracking-widest text-slate-500 mb-2">Your Balance</div>
      <template v-if="myBalance">
        <div class="flex items-baseline gap-2 mb-1">
          <span class="text-2xl font-extrabold"
            :class="myBalance.net > 0.01 ? 'text-emerald-400' : myBalance.net < -0.01 ? 'text-rose-400' : 'text-slate-400'">
            {{ myBalance.net >= 0 ? '+' : '' }}{{ aed(myBalance.net) }}
          </span>
        </div>
        <div class="text-xs text-slate-500 mb-3">
          {{ myBalance.net > 0.01 ? 'Overall you get back' : myBalance.net < -0.01 ? 'Overall you owe' : '🎉 All settled up!' }}
        </div>
        <div class="space-y-1.5">
          <div v-for="g in myBalance.gets" :key="g.name"
            class="flex items-center justify-between text-xs">
            <span class="text-slate-400">{{ g.name }} owes you</span>
            <span class="font-semibold text-emerald-400">+{{ aed(g.amount) }}</span>
          </div>
          <div v-for="o in myBalance.owe" :key="o.name"
            class="flex items-center justify-between text-xs">
            <span class="text-slate-400">You owe {{ o.name }}</span>
            <span class="font-semibold text-rose-400">-{{ aed(o.amount) }}</span>
          </div>
          <div v-if="!myBalance.owe.length && !myBalance.gets.length"
            class="text-xs text-slate-600">No outstanding balances in this club</div>
        </div>
      </template>
      <div v-else class="text-sm text-slate-500">
        No player record found for your account in this club yet.
      </div>
    </div>

    <!-- ── Tab bar ── -->
    <div class="flex gap-1 mb-4 rounded-2xl p-1" style="background:rgba(255,255,255,.05); border:1px solid rgba(255,255,255,.07)">
      <button v-for="t in [
          { key: 'activities', label: 'Activities' },
          { key: 'balance',    label: 'Balance' },
          { key: 'totals',     label: 'Totals' },
          { key: 'notes',      label: 'Notes' }
        ]" :key="t.key"
        @click="activeTab = t.key"
        class="flex-1 py-2 rounded-xl text-xs font-semibold transition-all duration-200"
        :class="activeTab === t.key ? 'text-slate-950' : 'text-slate-500 hover:text-slate-300'"
        :style="activeTab === t.key ? 'background:linear-gradient(135deg,#00e5ff,#0099cc)' : ''">
        {{ t.label }}
      </button>
    </div>

    <!-- ══════════════════════════════ ACTIVITIES ══════════════════════════ -->
    <div v-if="activeTab === 'activities'" class="fade-up">
      <button class="btn-primary w-full py-3 mb-4 text-sm" @click="openAddForm">
        ➕ Add Expense
      </button>

      <div v-if="!expenses.length" class="card p-10 text-center text-slate-400">
        <div class="text-4xl mb-3">💸</div>
        <p class="font-semibold mb-1">No expenses yet</p>
        <p class="text-sm">Record the first shared cost for this club.</p>
      </div>

      <div class="space-y-3">
        <div v-for="exp in expenses" :key="exp.id" class="card p-4">
          <!-- Header row -->
          <div class="flex items-start justify-between gap-3 mb-3">
            <div class="flex items-center gap-2.5 min-w-0">
              <div class="w-10 h-10 rounded-xl flex items-center justify-center text-xl shrink-0"
                style="background:rgba(255,255,255,.06)">
                {{ catIcon(exp.category) }}
              </div>
              <div class="min-w-0">
                <div class="font-semibold text-sm text-slate-100 truncate">{{ exp.title }}</div>
                <div class="text-[10px] text-slate-500 mt-0.5">
                  {{ catLabel(exp.category) }} · {{ fmtDate(exp.expense_date) }}
                </div>
              </div>
            </div>
            <div class="text-right shrink-0">
              <div class="font-bold text-slate-100">{{ aed(exp.amount) }}</div>
              <div class="text-[10px] text-slate-500">{{ exp.paid_name }} paid</div>
            </div>
          </div>

          <!-- My contribution pill -->
          <div v-if="myContrib(exp)"
            class="flex items-center justify-between rounded-lg px-3 py-2 mb-2 text-xs"
            style="background:rgba(255,255,255,.04); border:1px solid rgba(255,255,255,.06)">
            <span class="text-slate-400">
              {{ myContrib(exp).type === 'paid' ? 'You paid · gets back' : 'Your share' }}
            </span>
            <span class="font-bold"
              :class="myContrib(exp).net >= 0 ? 'text-emerald-400' : 'text-rose-400'">
              {{ myContrib(exp).net >= 0 ? '+' : '' }}{{ aed(myContrib(exp).net) }}
            </span>
          </div>

          <!-- Split summary -->
          <div class="text-[10px] text-slate-600 mb-3">
            Split equally among {{ exp.participants?.length ?? 0 }} people
            <span v-if="exp.participants?.length">
              · {{ aed(Number(exp.amount) / exp.participants.length) }} each
            </span>
          </div>

          <!-- Actions -->
          <div class="flex items-center gap-2 pt-2 border-t border-white/[0.05]">
            <button class="text-[11px] text-slate-500 hover:text-neon transition"
              @click="openEditForm(exp)">✏️ Edit</button>
            <button class="text-[11px] text-rose-500/60 hover:text-rose-400 transition ml-auto"
              :disabled="deletingId === exp.id"
              @click="confirmDelId = exp.id">
              {{ deletingId === exp.id ? '⏳ Deleting…' : '🗑️ Delete' }}
            </button>
          </div>
        </div>
      </div>
    </div>

    <!-- ══════════════════════════════ BALANCE ═════════════════════════════ -->
    <div v-else-if="activeTab === 'balance'" class="fade-up">
      <div v-if="!playerBalanceList.length" class="card p-10 text-center text-slate-400">
        <div class="text-4xl mb-3">⚖️</div>
        <p class="font-semibold mb-1">All settled!</p>
        <p class="text-sm">No outstanding balances in this club.</p>
      </div>

      <div class="space-y-2">
        <div v-for="p in playerBalanceList" :key="p.id"
          class="card overflow-hidden"
          :class="isMe(p.id) ? 'card-neon' : ''">

          <!-- Player row (click to expand) -->
          <button class="w-full flex items-center justify-between px-4 py-3.5 text-left"
            @click="expandedPlayer = expandedPlayer === p.id ? null : p.id">
            <div class="min-w-0">
              <span class="font-semibold text-sm"
                :class="isMe(p.id) ? 'text-neon' : 'text-slate-200'">
                {{ isMe(p.id) ? 'You' : p.name }}
              </span>
              <span v-if="isMe(p.id)" class="text-[10px] text-slate-500 ml-1.5">· {{ p.name }}</span>
            </div>
            <div class="flex items-center gap-2 shrink-0">
              <div class="text-right">
                <div class="text-xs font-bold"
                  :class="p.net > 0.01 ? 'text-emerald-400' : 'text-rose-400'">
                  {{ p.net > 0.01 ? 'Gets back' : 'Owes' }} {{ aed(Math.abs(p.net)) }}
                </div>
              </div>
              <span class="text-slate-500 text-xs transition-transform duration-200"
                :style="expandedPlayer === p.id ? 'transform:rotate(180deg)' : ''">▾</span>
            </div>
          </button>

          <!-- Expanded breakdown -->
          <div v-if="expandedPlayer === p.id"
            class="border-t border-white/[0.06] px-4 py-3 space-y-2">
            <div v-for="o in p.owes" :key="o.toId" class="flex items-center justify-between text-xs">
              <span class="text-slate-400">
                {{ isMe(p.id) ? 'You owe' : p.name + ' owes' }}
                <span class="text-slate-300 font-medium">{{ o.to }}</span>
              </span>
              <span class="text-rose-400 font-semibold shrink-0 ml-3">-{{ aed(o.amount) }}</span>
            </div>
            <div v-for="g in p.gets" :key="g.fromId" class="flex items-center justify-between text-xs">
              <span class="text-slate-400">
                {{ isMe(p.id) ? 'You get back from' : p.name + ' gets back from' }}
                <span class="text-slate-300 font-medium">{{ g.from }}</span>
              </span>
              <span class="text-emerald-400 font-semibold shrink-0 ml-3">+{{ aed(g.amount) }}</span>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- ══════════════════════════════ TOTALS ══════════════════════════════ -->
    <div v-else-if="activeTab === 'totals'" class="fade-up">
      <!-- Summary tiles -->
      <div class="grid grid-cols-2 gap-3 mb-5">
        <div class="card p-4 text-center">
          <div class="text-[10px] uppercase tracking-widest text-slate-500 mb-1.5">All-time spent</div>
          <div class="text-xl font-extrabold text-gold">{{ aed(allTimeTotal) }}</div>
          <div class="text-[10px] text-slate-600 mt-1">{{ expenses.length }} expenses</div>
        </div>
        <div class="card p-4 text-center">
          <div class="text-[10px] uppercase tracking-widest text-slate-500 mb-1.5">{{ currentYear }} total</div>
          <div class="text-xl font-extrabold text-neon">{{ aed(yearTotal) }}</div>
          <div class="text-[10px] text-slate-600 mt-1">this year</div>
        </div>
      </div>

      <!-- Bar chart: last 3 months -->
      <div class="card p-4 mb-5">
        <div class="text-xs font-semibold text-slate-300 mb-5">Last 3 Months</div>
        <div class="flex items-end justify-around gap-3" style="height:130px">
          <div v-for="m in last3Months" :key="m.key"
            class="flex-1 flex flex-col items-center gap-1.5">
            <div class="text-[10px] text-slate-400 font-semibold text-center leading-tight">
              <span v-if="m.total > 0">{{ aed(m.total) }}</span>
              <span v-else class="opacity-40">—</span>
            </div>
            <div class="w-full rounded-t-xl transition-all duration-700 min-h-[4px]"
              :style="{
                height: Math.max((m.total / barMax) * 80, m.total > 0 ? 6 : 2) + 'px',
                background: m.total > 0
                  ? 'linear-gradient(180deg,#00e5ff,#0099cc)'
                  : 'rgba(255,255,255,.08)'
              }" />
            <div class="text-[11px] font-medium" :class="m.total > 0 ? 'text-slate-300' : 'text-slate-600'">
              {{ m.label }}
            </div>
          </div>
        </div>
      </div>

      <!-- Monthly breakdown list -->
      <div class="card overflow-hidden">
        <div class="px-4 py-3 border-b border-white/[0.06]">
          <div class="text-xs font-semibold text-slate-300">Monthly Breakdown</div>
        </div>
        <div v-if="!monthlyTrend.length" class="px-4 py-6 text-center text-sm text-slate-500">
          No expenses recorded yet.
        </div>
        <div v-for="m in monthlyTrend" :key="m.key"
          class="flex items-center justify-between px-4 py-3 border-b border-white/[0.04] last:border-0">
          <span class="text-sm text-slate-300">{{ m.label }}</span>
          <span class="font-bold text-slate-100">{{ aed(m.total) }}</span>
        </div>
      </div>
    </div>

    <!-- ══════════════════════════════ NOTES ═══════════════════════════════ -->
    <div v-else-if="activeTab === 'notes'" class="fade-up">
      <!-- Add note -->
      <div class="card p-4 mb-4">
        <div class="text-[10px] uppercase tracking-widest text-slate-500 mb-2">Add a Note</div>
        <textarea v-model="noteText" rows="3" class="input resize-none w-full mb-3"
          placeholder="Payment reminders, group agreements, reimbursements to track…" />
        <button class="btn-primary w-full py-2.5 text-sm"
          :disabled="!noteText.trim() || noteSaving"
          @click="addNote">
          {{ noteSaving ? 'Saving…' : '📝 Post Note' }}
        </button>
      </div>

      <!-- Notes list -->
      <div v-if="!notes.length" class="card p-10 text-center text-slate-400">
        <div class="text-4xl mb-3">📝</div>
        <p class="font-semibold mb-1">No notes yet</p>
        <p class="text-sm">Post payment reminders or agreements for the group to see.</p>
      </div>

      <div class="space-y-3">
        <div v-for="n in notes" :key="n.id" class="card p-4">
          <p class="text-sm text-slate-200 leading-relaxed whitespace-pre-wrap mb-3">{{ n.content }}</p>
          <div class="flex items-center justify-between">
            <div class="text-[10px] text-slate-500">
              <span class="font-medium text-slate-400">{{ n.author }}</span>
              · {{ timeAgo(n.created_at) }}
            </div>
            <button class="text-[11px] text-rose-500/60 hover:text-rose-400 transition"
              @click="deleteNote(n.id)">Delete</button>
          </div>
        </div>
      </div>
    </div>

    <!-- ══════════════════════════ ADD / EDIT FORM ═════════════════════════ -->
    <Teleport to="body">
      <div v-if="showForm" class="fixed inset-0 z-50">
        <div class="absolute inset-0 bg-black/70" @click="showForm = false" />
        <div class="absolute bottom-0 left-0 right-0 rounded-t-2xl overflow-hidden"
          style="background:#0a1628; border-top:1px solid rgba(255,255,255,.1); max-height:92vh">

          <!-- Sticky handle + title -->
          <div class="sticky top-0 px-4 pt-3 pb-3 z-10" style="background:#0a1628; border-bottom:1px solid rgba(255,255,255,.06)">
            <div class="w-10 h-1 rounded-full bg-white/20 mx-auto mb-3" />
            <div class="flex items-center justify-between">
              <span class="font-semibold text-slate-100">
                {{ editingId ? 'Edit Expense' : 'Add Expense' }}
              </span>
              <button @click="showForm = false" class="text-slate-400 hover:text-slate-200 text-lg">✕</button>
            </div>
          </div>

          <!-- Scrollable form body -->
          <div class="overflow-y-auto px-4 pb-8 space-y-4 pt-4"
            style="max-height: calc(92vh - 72px)">

            <!-- Title -->
            <div>
              <label class="label">Expense Name</label>
              <input v-model="form.title" class="input" placeholder="e.g. Tea break, Court rent, Cork pack" maxlength="60" />
            </div>

            <!-- Category chips -->
            <div>
              <label class="label">Category</label>
              <div class="flex flex-wrap gap-2">
                <button v-for="c in CATEGORIES" :key="c.value"
                  @click="form.category = c.value"
                  class="flex items-center gap-1.5 px-3 py-1.5 rounded-xl text-xs font-medium transition-all"
                  :class="form.category === c.value ? 'text-slate-950 font-bold' : 'text-slate-400 border border-white/10 hover:border-white/25'"
                  :style="form.category === c.value ? 'background:linear-gradient(135deg,#00e5ff,#0099cc)' : ''">
                  {{ c.icon }} {{ c.label }}
                </button>
              </div>
            </div>

            <!-- Amount + Date -->
            <div class="grid grid-cols-2 gap-3">
              <div>
                <label class="label">Amount (AED)</label>
                <input v-model="form.amount" type="number" min="0.01" step="0.01" class="input"
                  placeholder="0.00" />
              </div>
              <div>
                <label class="label">Date</label>
                <input v-model="form.expense_date" type="date" class="input" />
              </div>
            </div>

            <!-- Paid by -->
            <div>
              <label class="label">Paid by</label>
              <select v-model="form.paid_player_id" class="input">
                <option value="" disabled>Who paid?</option>
                <option v-for="p in players" :key="p.id" :value="p.id">
                  {{ p.display_name }}{{ isMe(p.id) ? ' (you)' : '' }}
                </option>
              </select>
            </div>

            <!-- Participants -->
            <div>
              <div class="flex items-center justify-between mb-2">
                <label class="label mb-0">Split Among</label>
                <div class="flex gap-3">
                  <button class="text-[10px] text-neon"
                    @click="form.participant_ids = players.map(p => p.id)">All</button>
                  <button class="text-[10px] text-slate-500"
                    @click="form.participant_ids = []">None</button>
                  <button class="text-[10px] text-slate-500"
                    @click="form.participant_ids = players.filter(p => p.is_active).map(p => p.id)">
                    Active only
                  </button>
                </div>
              </div>

              <!-- Per-share preview -->
              <div v-if="perShare && form.participant_ids.length"
                class="text-[11px] text-neon mb-2 font-semibold">
                AED {{ perShare }} per person ({{ form.participant_ids.length }} selected)
              </div>

              <div class="grid grid-cols-2 gap-1.5 max-h-44 overflow-y-auto pr-1">
                <label v-for="p in players" :key="p.id"
                  class="flex items-center gap-2 px-3 py-2 rounded-xl cursor-pointer transition-all text-sm select-none"
                  :class="form.participant_ids.includes(p.id)
                    ? 'text-slate-100 font-medium'
                    : 'text-slate-500 border border-white/10'"
                  :style="form.participant_ids.includes(p.id)
                    ? 'background:rgba(0,229,255,.12); border:1px solid rgba(0,229,255,.28)'
                    : ''"
                  @click="toggleParticipant(p.id)">
                  <span class="text-xs w-3 shrink-0">{{ form.participant_ids.includes(p.id) ? '✓' : '' }}</span>
                  <span class="truncate">{{ p.display_name }}{{ isMe(p.id) ? ' (you)' : '' }}</span>
                </label>
              </div>
            </div>

            <!-- Notes -->
            <div>
              <label class="label">Notes <span class="text-slate-600">(optional)</span></label>
              <input v-model="form.notes" class="input" placeholder="Any extra details…" maxlength="120" />
            </div>

            <!-- Error -->
            <p v-if="formError" class="text-xs text-rose-400 px-1">{{ formError }}</p>

            <!-- Submit -->
            <button class="btn-primary w-full py-3" :disabled="formSaving" @click="saveExpense">
              {{ formSaving ? 'Saving…' : editingId ? '✓ Update Expense' : '➕ Add Expense' }}
            </button>
          </div>
        </div>
      </div>
    </Teleport>

    <!-- ══════════════════════════ DELETE CONFIRM ══════════════════════════ -->
    <Teleport to="body">
      <div v-if="confirmDelId"
        class="fixed inset-0 z-50 flex items-center justify-center px-5"
        style="background:rgba(0,0,0,.75); backdrop-filter:blur(6px)"
        @click.self="confirmDelId = null">
        <div class="w-full max-w-sm rounded-2xl p-6"
          style="background:#0d1a2e; border:1px solid rgba(244,63,94,.25); box-shadow:0 0 40px rgba(244,63,94,.12)">
          <div class="text-center mb-4">
            <div class="inline-flex w-14 h-14 rounded-2xl items-center justify-center text-3xl mb-3"
              style="background:rgba(244,63,94,.12); border:1px solid rgba(244,63,94,.25)">🗑️</div>
            <h3 class="font-display text-lg font-bold text-slate-100">Delete Expense?</h3>
            <p class="text-sm text-slate-400 mt-1">Balances will be recalculated for all members.</p>
          </div>
          <div class="flex gap-3">
            <button class="flex-1 py-3 rounded-xl text-sm font-semibold text-slate-300
                           border border-white/10 hover:border-white/25 hover:text-white transition"
              @click="confirmDelId = null">Cancel</button>
            <button class="flex-1 py-3 rounded-xl text-sm font-bold text-white transition active:scale-[.97]"
              style="background:rgba(220,38,38,.85); border:1px solid rgba(244,63,94,.4)"
              @click="doDelete">Yes, Delete</button>
          </div>
        </div>
      </div>
    </Teleport>

  </template>
</template>
