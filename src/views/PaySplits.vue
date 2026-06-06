<script setup>
import { ref, computed, watch, onMounted } from 'vue'
import { supabase } from '../lib/supabase'
import { useClub } from '../composables/useClub'
import { useAuth } from '../composables/useAuth'
import PageHeader from '../components/PageHeader.vue'

const { currentClub, isManager } = useClub()
const { user } = useAuth()

// ── Constants ──────────────────────────────────────────────────────────
const CURRENCY = 'AED'
const CATEGORIES = [
  { value: 'facility',  label: 'Court Rent',      icon: '🏟️' },
  { value: 'food',      label: 'Food / Snacks',    icon: '🍔' },
  { value: 'drinks',    label: 'Water / Tea',      icon: '☕' },
  { value: 'equipment', label: 'Cork / Equipment', icon: '🏸' },
  { value: 'transport', label: 'Transport',        icon: '🚗' },
  { value: 'tax',       label: 'Tax / Fees',       icon: '📋' },
  { value: 'other',     label: 'Other',            icon: '💡' },
]
const MONTHS = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec']

const catIcon  = v => CATEGORIES.find(c => c.value === v)?.icon  ?? '💡'
const catLabel = v => CATEGORIES.find(c => c.value === v)?.label ?? v
const aed      = n => `${CURRENCY} ${Number(n).toFixed(2)}`
const fmtDate  = d => new Date(d + 'T00:00:00').toLocaleDateString('en-AE', { day: 'numeric', month: 'short', year: 'numeric' })
const fmtDatetime = ts => new Date(ts).toLocaleString('en-AE', {
  day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit'
})
const toDatetimeLocal = d => new Date(d).toISOString().slice(0, 16)
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
const walletData     = ref({ contributions: [], wallet_expenses: [], player_balances: [] })
const loading        = ref(true)
const activeTab      = ref('activities')
const expandedPlayer = ref(null)

// ── Load all data ──────────────────────────────────────────────────────
async function load() {
  if (!currentClub.value || !user.value) return
  loading.value = true
  const cid = currentClub.value.club_id

  const [plRes, expRes, balRes, noteRes, myPlRes, wRes] = await Promise.all([
    supabase.rpc('get_club_players', { p_club_id: cid }),
    supabase.rpc('get_expenses', { p_club_id: cid }),
    supabase.rpc('get_balance_summary', { p_club_id: cid }),
    supabase.from('paysplit_notes')
      .select('id, content, created_at, created_by')
      .eq('club_id', cid).order('created_at', { ascending: false }),
    supabase.from('players')
      .select('id, display_name, user_id')
      .eq('club_id', cid).eq('user_id', user.value.id).maybeSingle(),
    supabase.rpc('get_wallet_data', { p_club_id: cid })
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

  if (wRes.data) {
    walletData.value = {
      contributions:   wRes.data.contributions   ?? [],
      wallet_expenses: wRes.data.wallet_expenses ?? [],
      player_balances: wRes.data.player_balances ?? []
    }
  }

  loading.value = false
}

onMounted(load)
watch(currentClub, () => { expandedPlayer.value = null; load() })

// ── Permission helper: creator or club manager/owner ───────────────────
function canModify(item) {
  return item.created_by === user.value?.id || isManager()
}

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

// ── My wallet position ─────────────────────────────────────────────────
const myWalletPosition = computed(() => {
  const mid = myPlayer.value?.id
  if (!mid) return null
  const wb = walletData.value.player_balances.find(p => p.player_id === mid)
  return wb ? { contributed: Number(wb.contributed), expense_share: Number(wb.expense_share), balance: Number(wb.balance) } : null
})

// ── My contribution per expense ────────────────────────────────────────
function myContrib(exp) {
  const mid = myPlayer.value?.id
  if (!mid) return null
  const isPayer = !exp.paid_from_wallet && exp.paid_player_id === mid
  const part    = exp.participants?.find(p => p.player_id === mid)
  if (!isPayer && !part) return null
  if (exp.paid_from_wallet) {
    return part ? { type: 'wallet', net: -Number(part.share) } : null
  }
  if (isPayer && !part) return { type: 'paid', net: Number(exp.amount) }
  if (isPayer &&  part) return { type: 'paid', net: Number(exp.amount) - Number(part.share) }
  return { type: 'split', net: -Number(part.share) }
}

// ── Wallet debt edges: greedy settlement of per-player wallet positions ──
// Each player's wallet balance = contributed − their share of wallet expenses.
// Positive = they over-contributed (others owe them). Negative = they under-contributed (they owe others).
// Greedy matching turns these positions into minimum debt edges (from owers to getters).
const walletDebtEdges = computed(() => {
  const positions = (walletData.value.player_balances ?? [])
    .map(b => ({
      id:        b.player_id,
      name:      b.player_name,
      remaining: Math.round(Number(b.balance) * 100) / 100
    }))
    .filter(b => Math.abs(b.remaining) >= 0.01)

  const getters = positions.filter(b => b.remaining > 0).map(b => ({ ...b })).sort((a, b) => b.remaining - a.remaining)
  const owers   = positions.filter(b => b.remaining < 0).map(b => ({ ...b, remaining: Math.abs(b.remaining) })).sort((a, b) => b.remaining - a.remaining)

  const edges = []
  let gi = 0, oi = 0
  while (gi < getters.length && oi < owers.length) {
    const g = getters[gi], o = owers[oi]
    const amount = Math.round(Math.min(g.remaining, o.remaining) * 100) / 100
    if (amount >= 0.01) {
      edges.push({ from_player_id: o.id, from_name: o.name, to_player_id: g.id, to_name: g.name, net_amount: amount })
    }
    g.remaining = Math.round((g.remaining - amount) * 100) / 100
    o.remaining = Math.round((o.remaining - amount) * 100) / 100
    if (g.remaining < 0.01) gi++
    if (o.remaining < 0.01) oi++
  }
  return edges
})

// ── Balance tab: combined direct-pay + wallet debts, netted per pair ───
const playerBalanceList = computed(() => {
  // Accumulate all edges into a canonical (lo < hi) pair map, then resolve direction
  const pairMap = {}
  const addEdge = (fromId, fromName, toId, toName, amt) => {
    const fwd = fromId < toId
    const lo = fwd ? fromId : toId, hi = fwd ? toId : fromId
    const key = `${lo}|${hi}`
    if (!pairMap[key]) pairMap[key] = { lo, hi, loName: fwd ? fromName : toName, hiName: fwd ? toName : fromName, net: 0 }
    pairMap[key].net += fwd ? amt : -amt
  }

  balances.value.forEach(b => addEdge(b.from_player_id, b.from_name, b.to_player_id, b.to_name, Number(b.net_amount)))
  walletDebtEdges.value.forEach(e => addEdge(e.from_player_id, e.from_name, e.to_player_id, e.to_name, e.net_amount))

  const map = {}
  Object.values(pairMap).forEach(({ lo, hi, loName, hiName, net }) => {
    if (Math.abs(net) < 0.01) return
    const fromId   = net > 0 ? lo : hi
    const fromName = net > 0 ? loName : hiName
    const toId     = net > 0 ? hi : lo
    const toName   = net > 0 ? hiName : loName
    const amount   = Math.round(Math.abs(net) * 100) / 100
    if (!map[fromId]) map[fromId] = { id: fromId, name: fromName, owes: [], gets: [], net: 0 }
    if (!map[toId])   map[toId]   = { id: toId,   name: toName,   owes: [], gets: [], net: 0 }
    map[fromId].owes.push({ to: toName, toId, amount })
    map[fromId].net -= amount
    map[toId].gets.push({ from: fromName, fromId, amount })
    map[toId].net += amount
  })

  return Object.values(map)
    .filter(p => Math.abs(p.net) >= 0.01)
    .sort((a, b) => {
      if (myPlayer.value?.id === a.id) return -1
      if (myPlayer.value?.id === b.id) return 1
      return Math.abs(b.net) - Math.abs(a.net)
    })
})

// ── Wallet: FIFO computation (frontend) ───────────────────────────────
// Oldest contribution depleted first. Returns separate active / consumed lists.
const fifoResult = computed(() => {
  const contribs = [...walletData.value.contributions]
    .sort((a, b) => new Date(a.contributed_at) - new Date(b.contributed_at))

  const wExps = [...walletData.value.wallet_expenses]
    .sort((a, b) => {
      const d = (a.expense_date ?? '').localeCompare(b.expense_date ?? '')
      return d || new Date(a.created_at) - new Date(b.created_at)
    })

  const remaining  = {}
  const consumedBy = {}
  contribs.forEach(c => { remaining[c.id] = Number(c.amount); consumedBy[c.id] = [] })

  wExps.forEach(exp => {
    let toConsume = Number(exp.amount)
    for (const c of contribs) {
      if (remaining[c.id] < 0.005 || toConsume < 0.005) continue
      const take = Math.min(remaining[c.id], toConsume)
      remaining[c.id] = Math.round((remaining[c.id] - take) * 100) / 100
      toConsume       = Math.round((toConsume - take) * 100) / 100
      consumedBy[c.id].push({ expenseId: exp.id, title: exp.title, amount: take })
    }
  })

  const mapped = contribs.map(c => ({
    ...c,
    remaining:  remaining[c.id] ?? 0,
    consumedBy: consumedBy[c.id] ?? []
  }))

  return {
    active:   mapped.filter(c => c.remaining > 0.005),
    consumed: mapped.filter(c => c.remaining <= 0.005 && c.consumedBy.length > 0)
  }
})

const expandedConsumed = ref(null)

// Auto-expand the current user's row when switching to the Balance tab
watch(activeTab, tab => {
  if (tab === 'balance' && myPlayer.value?.id && !expandedPlayer.value) {
    expandedPlayer.value = myPlayer.value.id
  }
})

const walletTotalContributed = computed(() =>
  walletData.value.contributions.reduce((s, c) => s + Number(c.amount), 0)
)
const walletTotalExpenses = computed(() =>
  walletData.value.wallet_expenses.reduce((s, e) => s + Number(e.amount), 0)
)
const walletBalance = computed(() => walletTotalContributed.value - walletTotalExpenses.value)

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
  title:           '',
  category:        'other',
  amount:          '',
  paymentSource:   'person',
  paid_player_id:  myPlayer.value?.id ?? '',
  expense_date:    new Date().toISOString().slice(0, 10),
  notes:           '',
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
    paymentSource:   exp.paid_from_wallet ? 'wallet' : 'person',
    paid_player_id:  exp.paid_player_id ?? '',
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
  if (form.value.paymentSource === 'person' && !form.value.paid_player_id)
                                         { formError.value = 'Select who paid'; return }
  if (!form.value.participant_ids.length){ formError.value = 'Select at least one participant'; return }

  const isWallet = form.value.paymentSource === 'wallet'

  if (isWallet) {
    let available = walletBalance.value
    if (editingId.value) {
      const old = expenses.value.find(e => e.id === editingId.value)
      if (old?.paid_from_wallet) available += Number(old.amount)
    }
    if (amt > available + 0.005) {
      formError.value = `Wallet balance is ${aed(available)} — not enough to cover this expense.`
      return
    }
  }

  formSaving.value = true
  const params = {
    p_club_id:          currentClub.value.club_id,
    p_title:            form.value.title.trim(),
    p_category:         form.value.category,
    p_amount:           amt,
    p_paid_player_id:   isWallet ? null : form.value.paid_player_id,
    p_expense_date:     form.value.expense_date,
    p_participant_ids:  form.value.participant_ids,
    p_notes:            form.value.notes.trim() || null,
    p_paid_from_wallet: isWallet
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

// ── Wallet contribution form ───────────────────────────────────────────
const showWalletForm   = ref(false)
const walletEditId     = ref(null)
const walletFormError  = ref(null)
const walletFormSaving = ref(false)
const confirmDelWallet = ref(null)

const blankWalletForm = () => ({
  player_id:      myPlayer.value?.id ?? (players.value[0]?.id ?? ''),
  amount:         '',
  notes:          '',
  contributed_at: toDatetimeLocal(new Date())
})

const walletForm = ref(blankWalletForm())

function openWalletAddForm() {
  walletEditId.value    = null
  walletForm.value      = blankWalletForm()
  walletFormError.value = null
  showWalletForm.value  = true
}

function openWalletEditForm(contrib) {
  walletEditId.value = contrib.id
  walletForm.value = {
    player_id:      contrib.player_id,
    amount:         String(contrib.amount),
    notes:          contrib.notes ?? '',
    contributed_at: toDatetimeLocal(new Date(contrib.contributed_at))
  }
  walletFormError.value = null
  showWalletForm.value  = true
}

async function saveContrib() {
  walletFormError.value = null
  const amt = parseFloat(walletForm.value.amount)
  if (!walletForm.value.player_id) { walletFormError.value = 'Select a player'; return }
  if (!amt || amt <= 0)            { walletFormError.value = 'Enter a valid amount'; return }

  walletFormSaving.value = true
  const params = {
    p_amount:         amt,
    p_notes:          walletForm.value.notes.trim() || null,
    p_contributed_at: new Date(walletForm.value.contributed_at).toISOString()
  }

  let error
  if (walletEditId.value) {
    const res = await supabase.rpc('update_wallet_contribution', { p_id: walletEditId.value, ...params })
    error = res.error
  } else {
    const res = await supabase.rpc('add_wallet_contribution', {
      p_club_id:   currentClub.value.club_id,
      p_player_id: walletForm.value.player_id,
      ...params
    })
    error = res.error
  }

  walletFormSaving.value = false
  if (error) { walletFormError.value = error.message; return }
  showWalletForm.value = false
  await load()
}

async function doDeleteContrib() {
  const id = confirmDelWallet.value
  if (!id) return
  confirmDelWallet.value = null
  await supabase.rpc('delete_wallet_contribution', { p_id: id })
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
          <p><strong class="text-slate-800">Activities</strong> — Full expense list with your contribution per item. Only the person who added an entry (or a manager) can edit or delete it.</p>
          <p><strong class="text-slate-800">Balance</strong> — Who owes whom across person-paid expenses. Tap a name to expand.</p>
          <p><strong class="text-slate-800">Wallet</strong> — Shared cash pool. Contributions are consumed oldest-first (FIFO) when a wallet expense is recorded.</p>
          <p><strong class="text-slate-800">Totals</strong> — Monthly spending charts and all-time summary.</p>
          <p><strong class="text-slate-800">Notes</strong> — Shared notepad for payment reminders.</p>
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
          {{ myBalance.net > 0.01 ? 'Overall you get back (person-paid expenses)' : myBalance.net < -0.01 ? 'Overall you owe (person-paid expenses)' : '🎉 All settled up!' }}
        </div>
        <div class="space-y-1.5">
          <div v-for="g in myBalance.gets" :key="g.name" class="flex items-center justify-between text-xs">
            <span class="text-slate-400">{{ g.name }} owes you</span>
            <span class="font-semibold text-emerald-400">+{{ aed(g.amount) }}</span>
          </div>
          <div v-for="o in myBalance.owe" :key="o.name" class="flex items-center justify-between text-xs">
            <span class="text-slate-400">You owe {{ o.name }}</span>
            <span class="font-semibold text-rose-400">-{{ aed(o.amount) }}</span>
          </div>
          <div v-if="!myBalance.owe.length && !myBalance.gets.length"
            class="text-xs text-slate-600">No outstanding person-to-person balances</div>
        </div>

        <!-- Wallet position -->
        <div v-if="myWalletPosition && (myWalletPosition.contributed > 0 || myWalletPosition.expense_share > 0)"
          class="mt-3 pt-3 border-t border-white/[.06]">
          <div class="flex items-center justify-between text-xs">
            <span class="text-slate-500">💰 Wallet position</span>
            <span class="font-semibold"
              :class="myWalletPosition.balance >= 0 ? 'text-emerald-400' : 'text-rose-400'">
              {{ myWalletPosition.balance >= 0 ? '+' : '' }}{{ aed(myWalletPosition.balance) }}
            </span>
          </div>
          <div class="text-[10px] text-slate-600 mt-0.5">
            Contributed {{ aed(myWalletPosition.contributed) }} · Share of wallet expenses {{ aed(myWalletPosition.expense_share) }}
          </div>
        </div>
      </template>
      <div v-else class="text-sm text-slate-500">
        No player record found for your account in this club yet.
      </div>
    </div>

    <!-- ── Tab bar (5 tabs) ── -->
    <div class="flex gap-1 mb-4 rounded-2xl p-1" style="background:rgba(255,255,255,.05); border:1px solid rgba(255,255,255,.07)">
      <button v-for="t in [
          { key: 'activities', label: 'Expenses' },
          { key: 'balance',    label: 'Balance' },
          { key: 'wallet',     label: 'Wallet' },
          { key: 'totals',     label: 'Totals' },
          { key: 'notes',      label: 'Notes' }
        ]" :key="t.key"
        @click="activeTab = t.key"
        class="flex-1 py-2 rounded-xl text-[10px] font-semibold transition-all duration-200"
        :class="activeTab === t.key ? 'text-slate-950' : 'text-slate-500 hover:text-slate-300'"
        :style="activeTab === t.key ? 'background:linear-gradient(135deg,#00e5ff,#0099cc)' : ''">
        {{ t.label }}
      </button>
    </div>

    <!-- ══════════════════════════════ EXPENSES ══════════════════════════ -->
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
                <div class="flex items-center gap-1.5">
                  <span class="font-semibold text-sm text-slate-100 truncate">{{ exp.title }}</span>
                  <span v-if="exp.paid_from_wallet"
                    class="shrink-0 text-[9px] font-bold px-1.5 py-0.5 rounded-md"
                    style="background:rgba(168,85,247,.18); color:#c084fc; border:1px solid rgba(168,85,247,.3)">
                    💰 WALLET
                  </span>
                </div>
                <div class="text-[10px] text-slate-500 mt-0.5">
                  {{ catLabel(exp.category) }} · {{ fmtDate(exp.expense_date) }}
                </div>
              </div>
            </div>
            <div class="text-right shrink-0">
              <div class="font-bold text-slate-100">{{ aed(exp.amount) }}</div>
              <div class="text-[10px] text-slate-500">
                {{ exp.paid_from_wallet ? 'From wallet' : exp.paid_name + ' paid' }}
              </div>
            </div>
          </div>

          <!-- My contribution pill -->
          <div v-if="myContrib(exp)"
            class="flex items-center justify-between rounded-lg px-3 py-2 mb-2 text-xs"
            style="background:rgba(255,255,255,.04); border:1px solid rgba(255,255,255,.06)">
            <span class="text-slate-400">
              {{ myContrib(exp).type === 'paid' ? 'You paid · gets back'
               : myContrib(exp).type === 'wallet' ? 'Your share (wallet-paid)'
               : 'Your share' }}
            </span>
            <span class="font-bold"
              :class="myContrib(exp).net >= 0 ? 'text-emerald-400' : 'text-rose-400'">
              {{ myContrib(exp).net >= 0 ? '+' : '' }}{{ aed(myContrib(exp).net) }}
            </span>
          </div>

          <!-- Split summary + participant names -->
          <div class="mb-3">
            <div class="text-[10px] text-slate-600 mb-1.5">
              Split equally among {{ exp.participants?.length ?? 0 }} people
              <span v-if="exp.participants?.length">
                · {{ aed(Number(exp.amount) / exp.participants.length) }} each
              </span>
            </div>
            <div v-if="exp.participants?.length" class="flex flex-wrap gap-1">
              <span v-for="pt in exp.participants" :key="pt.player_id"
                class="text-[9px] px-1.5 py-0.5 rounded-md"
                :class="pt.player_id === myPlayer?.id
                  ? 'text-neon font-semibold'
                  : 'text-slate-400'"
                style="background:rgba(255,255,255,.06); border:1px solid rgba(255,255,255,.09)">
                {{ pt.player_id === myPlayer?.id ? 'You' : pt.name }}
              </span>
            </div>
          </div>

          <!-- Actions: only for creator or manager -->
          <div v-if="canModify(exp)" class="flex items-center gap-2 pt-2 border-t border-white/[0.05]">
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
    <div v-if="activeTab === 'balance'" class="fade-up">
      <div v-if="!playerBalanceList.length" class="card p-10 text-center text-slate-400">
        <div class="text-4xl mb-3">⚖️</div>
        <p class="font-semibold mb-1">All settled!</p>
        <p class="text-sm">No outstanding person-paid balances in this club.</p>
      </div>

      <div class="space-y-2">
        <div v-for="p in playerBalanceList" :key="p.id"
          class="card overflow-hidden"
          :class="isMe(p.id) ? 'card-neon' : ''">

          <!-- Row header -->
          <button class="w-full flex items-center gap-3 px-4 py-3.5 text-left"
            @click="expandedPlayer = expandedPlayer === p.id ? null : p.id">

            <!-- Initials avatar -->
            <div class="w-9 h-9 rounded-full flex items-center justify-center text-xs font-bold shrink-0"
              :style="p.net > 0.01
                ? 'background:rgba(52,211,153,.12); color:#34d399'
                : 'background:rgba(248,113,113,.12); color:#f87171'">
              {{ p.name.slice(0,2).toUpperCase() }}
            </div>

            <!-- Sentence: "Name owes/gets back AED X in total" -->
            <div class="flex-1 min-w-0 text-sm leading-snug">
              <span class="font-semibold" :class="isMe(p.id) ? 'text-neon' : 'text-slate-200'">
                {{ isMe(p.id) ? 'You' : p.name }}
              </span>
              <span :class="p.net > 0.01 ? 'text-emerald-400' : 'text-rose-400'">
                {{ p.net > 0.01 ? ' get back ' : ' owe ' }}
              </span>
              <span class="font-bold" :class="p.net > 0.01 ? 'text-emerald-400' : 'text-rose-400'">
                {{ aed(Math.abs(p.net)) }}
              </span>
              <span class="text-slate-500 text-xs"> in total</span>
            </div>

            <span class="text-slate-500 text-xs shrink-0 transition-transform duration-200"
              :style="expandedPlayer === p.id ? 'transform:rotate(180deg)' : ''">▾</span>
          </button>

          <!-- Expanded breakdown -->
          <div v-if="expandedPlayer === p.id"
            class="border-t border-white/[0.06] px-4 py-3 space-y-2">

            <!-- Debts this player owes to others -->
            <div v-for="o in p.owes" :key="o.toId"
              class="flex items-center justify-between text-xs rounded-lg px-3 py-2"
              style="background:rgba(248,113,113,.06); border:1px solid rgba(248,113,113,.12)">
              <span>
                <span class="font-medium text-slate-200">{{ isMe(p.id) ? 'You' : p.name }}</span>
                <span class="text-slate-500"> owe </span>
                <span class="font-medium text-slate-200">{{ o.to }}</span>
              </span>
              <span class="text-rose-400 font-bold shrink-0 ml-3">{{ aed(o.amount) }}</span>
            </div>

            <!-- Debts others owe to this player -->
            <div v-for="g in p.gets" :key="g.fromId"
              class="flex items-center justify-between text-xs rounded-lg px-3 py-2"
              style="background:rgba(52,211,153,.06); border:1px solid rgba(52,211,153,.12)">
              <span>
                <span class="font-medium text-slate-200">{{ g.from }}</span>
                <span class="text-slate-500"> owes </span>
                <span class="font-medium text-slate-200">{{ isMe(p.id) ? 'you' : p.name }}</span>
              </span>
              <span class="text-emerald-400 font-bold shrink-0 ml-3">{{ aed(g.amount) }}</span>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- ══════════════════════════════ WALLET ═════════════════════════════ -->
    <div v-if="activeTab === 'wallet'" class="fade-up space-y-4">

      <!-- Wallet balance summary -->
      <div class="card p-4">
        <div class="text-[10px] uppercase tracking-widest text-slate-500 mb-3">Common Wallet</div>
        <div class="grid grid-cols-3 gap-3 text-center mb-3">
          <div>
            <div class="text-[10px] text-slate-500 mb-1">Contributed</div>
            <div class="text-base font-extrabold text-emerald-400">{{ aed(walletTotalContributed) }}</div>
          </div>
          <div>
            <div class="text-[10px] text-slate-500 mb-1">Spent</div>
            <div class="text-base font-extrabold text-rose-400">{{ aed(walletTotalExpenses) }}</div>
          </div>
          <div>
            <div class="text-[10px] text-slate-500 mb-1">Balance</div>
            <div class="text-base font-extrabold"
              :class="walletBalance >= 0 ? 'text-neon' : 'text-rose-400'">
              {{ aed(walletBalance) }}
            </div>
          </div>
        </div>
        <div class="text-[10px] text-slate-600 text-center">
          Oldest contribution is consumed first (FIFO) when wallet pays an expense
        </div>
      </div>

      <!-- Add Contribution button -->
      <button class="btn-primary w-full py-3 text-sm" @click="openWalletAddForm">
        ➕ Add Contribution
      </button>

      <!-- ── Active FIFO Queue ── -->
      <div class="card overflow-hidden">
        <div class="px-4 py-2.5 border-b border-white/[.06]">
          <div class="text-xs font-semibold text-slate-300">FIFO Queue</div>
          <div class="text-[10px] text-slate-500">#1 is consumed first when wallet pays an expense</div>
        </div>

        <div v-if="!fifoResult.active.length" class="px-4 py-8 text-center text-sm text-slate-500">
          <div class="text-3xl mb-2">🪙</div>
          No active contributions. Add the first one!
        </div>

        <div v-for="(c, i) in fifoResult.active" :key="c.id"
          class="px-4 py-3 border-b border-white/[.04] last:border-0">
          <div class="flex items-start justify-between gap-3">
            <div class="flex items-center gap-2.5 min-w-0">
              <div class="w-7 h-7 rounded-xl flex items-center justify-center text-xs font-bold shrink-0"
                style="background:rgba(0,229,255,.12); color:#00e5ff">
                #{{ i + 1 }}
              </div>
              <div class="min-w-0">
                <div class="text-sm font-semibold"
                  :class="isMe(c.player_id) ? 'text-neon' : 'text-slate-100'">
                  {{ isMe(c.player_id) ? 'You' : c.player_name }}
                  <span v-if="isMe(c.player_id)" class="text-[10px] text-slate-500 ml-1">· {{ c.player_name }}</span>
                </div>
                <div class="text-[10px] text-slate-500">
                  {{ fmtDatetime(c.contributed_at) }}<span v-if="c.notes"> · {{ c.notes }}</span>
                </div>
              </div>
            </div>
            <div class="text-right shrink-0">
              <div class="font-bold text-slate-100">{{ aed(c.amount) }}</div>
              <div class="text-[10px] text-emerald-400">{{ aed(c.remaining) }} left</div>
            </div>
          </div>
          <!-- Partial consumption so far -->
          <div v-if="c.consumedBy.length" class="mt-2 ml-9 space-y-1">
            <div v-for="cb in c.consumedBy" :key="cb.expenseId"
              class="flex items-center justify-between text-[10px] text-slate-500">
              <span>→ {{ cb.title }}</span>
              <span class="text-rose-400/70">−{{ aed(cb.amount) }}</span>
            </div>
          </div>
          <div v-if="canModify(c)" class="flex gap-3 mt-2 ml-9">
            <button class="text-[10px] text-slate-500 hover:text-neon transition"
              @click="openWalletEditForm(c)">✏️ Edit</button>
            <button class="text-[10px] text-rose-500/60 hover:text-rose-400 transition"
              @click="confirmDelWallet = c.id">🗑️ Delete</button>
          </div>
        </div>
      </div>

      <!-- ── Consumed contributions ── -->
      <div v-if="fifoResult.consumed.length" class="card overflow-hidden">
        <div class="px-4 py-2.5 border-b border-white/[.06]">
          <div class="text-xs font-semibold text-slate-400">✓ Wallet Consumed</div>
          <div class="text-[10px] text-slate-600">Fully used — tap to see which expenses</div>
        </div>

        <div v-for="c in fifoResult.consumed" :key="c.id"
          class="border-b border-white/[.04] last:border-0">

          <!-- Row (tap to expand) -->
          <button class="w-full px-4 py-3 flex items-center justify-between text-left"
            @click="expandedConsumed = expandedConsumed === c.id ? null : c.id">
            <div class="flex items-center gap-2.5 min-w-0">
              <div class="w-7 h-7 rounded-xl flex items-center justify-center text-xs shrink-0"
                style="background:rgba(100,116,139,.12); color:#475569">✓</div>
              <div class="min-w-0">
                <div class="text-sm text-slate-500">
                  {{ isMe(c.player_id) ? 'You' : c.player_name }}
                </div>
                <div class="text-[10px] text-slate-600">{{ fmtDatetime(c.contributed_at) }}<span v-if="c.notes"> · {{ c.notes }}</span></div>
              </div>
            </div>
            <div class="flex items-center gap-2 shrink-0">
              <div class="font-bold text-slate-600 line-through text-sm">{{ aed(c.amount) }}</div>
              <span class="text-slate-600 text-xs transition-transform duration-200"
                :style="expandedConsumed === c.id ? 'transform:rotate(180deg)' : ''">▾</span>
            </div>
          </button>

          <!-- Expanded: expense breakdown -->
          <div v-if="expandedConsumed === c.id"
            class="px-4 pb-3 ml-9 space-y-2 border-t border-white/[.04]">
            <div class="pt-2 text-[10px] text-slate-600 mb-1">Used for:</div>
            <div v-for="cb in c.consumedBy" :key="cb.expenseId"
              class="flex items-center justify-between rounded-lg px-3 py-2"
              style="background:rgba(255,255,255,.03); border:1px solid rgba(255,255,255,.06)">
              <span class="text-xs text-slate-400">{{ cb.title }}</span>
              <span class="text-xs font-semibold text-slate-400">{{ aed(cb.amount) }}</span>
            </div>
            <div v-if="canModify(c)" class="flex gap-3 pt-1">
              <button class="text-[10px] text-slate-600 hover:text-neon transition"
                @click="openWalletEditForm(c)">✏️ Edit</button>
              <button class="text-[10px] text-rose-600/50 hover:text-rose-400 transition"
                @click="confirmDelWallet = c.id">🗑️ Delete</button>
            </div>
          </div>
        </div>
      </div>

    </div>

    <!-- ══════════════════════════════ TOTALS ══════════════════════════════ -->
    <div v-if="activeTab === 'totals'" class="fade-up">
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

      <div class="card p-4 mb-5">
        <div class="text-xs font-semibold text-slate-300 mb-5">Last 3 Months</div>
        <div class="flex items-end justify-around gap-3" style="height:130px">
          <div v-for="m in last3Months" :key="m.key" class="flex-1 flex flex-col items-center gap-1.5">
            <div class="text-[10px] text-slate-400 font-semibold text-center leading-tight">
              <span v-if="m.total > 0">{{ aed(m.total) }}</span>
              <span v-else class="opacity-40">—</span>
            </div>
            <div class="w-full rounded-t-xl transition-all duration-700 min-h-[4px]"
              :style="{
                height: Math.max((m.total / barMax) * 80, m.total > 0 ? 6 : 2) + 'px',
                background: m.total > 0 ? 'linear-gradient(180deg,#00e5ff,#0099cc)' : 'rgba(255,255,255,.08)'
              }" />
            <div class="text-[11px] font-medium" :class="m.total > 0 ? 'text-slate-300' : 'text-slate-600'">
              {{ m.label }}
            </div>
          </div>
        </div>
      </div>

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
    <div v-if="activeTab === 'notes'" class="fade-up">
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
            <button v-if="canModify(n)" class="text-[11px] text-rose-500/60 hover:text-rose-400 transition"
              @click="deleteNote(n.id)">Delete</button>
          </div>
        </div>
      </div>
    </div>

    <!-- ══════════════════════════ ADD / EDIT EXPENSE FORM ════════════════ -->
    <Teleport to="body">
      <div v-if="showForm" class="fixed inset-0 z-50">
        <div class="absolute inset-0 bg-black/70" @click="showForm = false" />
        <div class="absolute bottom-0 left-0 right-0 rounded-t-2xl overflow-hidden"
          style="background:#ffffff; border-top:1px solid rgba(0,0,0,.1); max-height:92vh">

          <div class="sticky top-0 px-4 pt-3 pb-3 z-10"
            style="background:#ffffff; border-bottom:1px solid rgba(0,0,0,.07)">
            <div class="w-10 h-1 rounded-full bg-slate-200 mx-auto mb-3" />
            <div class="flex items-center justify-between">
              <span class="font-semibold text-slate-800">
                {{ editingId ? 'Edit Expense' : 'Add Expense' }}
              </span>
              <button @click="showForm = false" class="text-slate-400 hover:text-slate-700 text-lg">✕</button>
            </div>
          </div>

          <div class="overflow-y-auto px-4 pb-8 space-y-4 pt-4" style="max-height: calc(92vh - 72px)">

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
                  :class="form.category === c.value ? 'text-white font-bold' : 'text-slate-500 border border-slate-200 hover:border-slate-400'"
                  :style="form.category === c.value ? 'background:linear-gradient(135deg,#00b4cc,#0077a0)' : ''">
                  {{ c.icon }} {{ c.label }}
                </button>
              </div>
            </div>

            <!-- Amount + Date -->
            <div class="grid grid-cols-2 gap-3">
              <div>
                <label class="label">Amount (AED)</label>
                <input v-model="form.amount" type="number" min="0.01" step="0.01" class="input" placeholder="0.00" />
              </div>
              <div>
                <label class="label">Date</label>
                <input v-model="form.expense_date" type="date" class="input" />
              </div>
            </div>

            <!-- Payment source toggle -->
            <div>
              <label class="label">Payment Source</label>
              <div class="flex gap-2">
                <button
                  @click="form.paymentSource = 'person'"
                  class="flex-1 flex items-center justify-center gap-2 py-2.5 rounded-xl text-xs font-semibold transition-all"
                  :class="form.paymentSource === 'person' ? 'text-white' : 'text-slate-500 border border-slate-200'"
                  :style="form.paymentSource === 'person' ? 'background:linear-gradient(135deg,#00b4cc,#0077a0)' : ''">
                  👤 Person Paid
                </button>
                <button
                  @click="form.paymentSource = 'wallet'"
                  class="flex-1 flex flex-col items-center justify-center gap-0.5 py-2 rounded-xl text-xs font-semibold transition-all"
                  :class="form.paymentSource === 'wallet' ? 'text-white' : walletBalance <= 0 ? 'text-slate-300 border border-slate-100' : 'text-slate-500 border border-slate-200'"
                  :style="form.paymentSource === 'wallet' ? 'background:linear-gradient(135deg,#a855f7,#7c3aed)' : ''">
                  <span>💰 Common Wallet</span>
                  <span class="text-[9px] font-normal opacity-80">{{ aed(walletBalance) }} available</span>
                </button>
              </div>
              <!-- Wallet balance hint -->
              <div v-if="form.paymentSource === 'wallet'"
                class="mt-2 text-[10px] px-3 py-2 rounded-lg"
                :style="walletBalance > 0
                  ? 'background:rgba(0,153,184,.08); color:#0077a0; border:1px solid rgba(0,153,184,.2)'
                  : 'background:rgba(220,38,38,.06); color:#dc2626; border:1px solid rgba(220,38,38,.2)'">
                Wallet balance: {{ aed(walletBalance) }}
                {{ walletBalance < 0 ? ' — wallet is in deficit' : '' }}
              </div>
            </div>

            <!-- Paid by (only for person payment) -->
            <div v-if="form.paymentSource === 'person'">
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
                  <button class="text-[10px] text-cyan-600 font-semibold" @click="form.participant_ids = players.map(p => p.id)">All</button>
                  <button class="text-[10px] text-slate-400" @click="form.participant_ids = []">None</button>
                  <button class="text-[10px] text-slate-400"
                    @click="form.participant_ids = players.filter(p => p.is_active).map(p => p.id)">
                    Active only
                  </button>
                </div>
              </div>

              <div v-if="perShare && form.participant_ids.length"
                class="text-[11px] font-semibold mb-2" style="color:#0077a0">
                AED {{ perShare }} per person ({{ form.participant_ids.length }} selected)
              </div>

              <div class="grid grid-cols-2 gap-1.5 max-h-44 overflow-y-auto pr-1">
                <label v-for="p in players" :key="p.id"
                  class="flex items-center gap-2 px-3 py-2 rounded-xl cursor-pointer transition-all text-sm select-none"
                  :class="form.participant_ids.includes(p.id)
                    ? 'font-medium text-slate-800'
                    : 'text-slate-500 border border-slate-200'"
                  :style="form.participant_ids.includes(p.id)
                    ? 'background:rgba(0,153,184,.1); border:1px solid rgba(0,153,184,.3)'
                    : ''"
                  @click="toggleParticipant(p.id)">
                  <span class="text-xs w-3 shrink-0">{{ form.participant_ids.includes(p.id) ? '✓' : '' }}</span>
                  <span class="truncate">{{ p.display_name }}{{ isMe(p.id) ? ' (you)' : '' }}</span>
                </label>
              </div>
            </div>

            <!-- Notes -->
            <div>
              <label class="label">Notes <span class="text-slate-400 normal-case tracking-normal">(optional)</span></label>
              <input v-model="form.notes" class="input" placeholder="Any extra details…" maxlength="120" />
            </div>

            <p v-if="formError" class="text-xs text-rose-600 px-1">{{ formError }}</p>

            <button class="btn-primary w-full py-3" :disabled="formSaving" @click="saveExpense">
              {{ formSaving ? 'Saving…' : editingId ? '✓ Update Expense' : '➕ Add Expense' }}
            </button>
          </div>
        </div>
      </div>
    </Teleport>

    <!-- ══════════════════════════ ADD / EDIT WALLET FORM ═════════════════ -->
    <Teleport to="body">
      <div v-if="showWalletForm" class="fixed inset-0 z-50">
        <div class="absolute inset-0 bg-black/70" @click="showWalletForm = false" />
        <div class="absolute bottom-0 left-0 right-0 rounded-t-2xl overflow-hidden"
          style="background:#ffffff; border-top:1px solid rgba(168,85,247,.3); max-height:85vh">

          <div class="sticky top-0 px-4 pt-3 pb-3 z-10"
            style="background:#ffffff; border-bottom:1px solid rgba(0,0,0,.07)">
            <div class="w-10 h-1 rounded-full bg-slate-200 mx-auto mb-3" />
            <div class="flex items-center justify-between">
              <span class="font-semibold text-slate-800">
                {{ walletEditId ? 'Edit Contribution' : 'Add Wallet Contribution' }}
              </span>
              <button @click="showWalletForm = false" class="text-slate-400 hover:text-slate-700 text-lg">✕</button>
            </div>
          </div>

          <div class="overflow-y-auto px-4 pb-8 space-y-4 pt-4" style="max-height: calc(85vh - 72px)">

            <!-- Player -->
            <div>
              <label class="label">Player (who contributed)</label>
              <select v-model="walletForm.player_id" class="input">
                <option value="" disabled>Select player</option>
                <option v-for="p in players" :key="p.id" :value="p.id">
                  {{ p.display_name }}{{ isMe(p.id) ? ' (you)' : '' }}
                </option>
              </select>
            </div>

            <!-- Amount -->
            <div>
              <label class="label">Amount (AED)</label>
              <input v-model="walletForm.amount" type="number" min="0.01" step="0.01" class="input" placeholder="0.00" />
            </div>

            <!-- Date & time (determines FIFO position) -->
            <div>
              <label class="label">
                Date &amp; Time
                <span class="text-[10px] text-slate-400 font-normal normal-case tracking-normal ml-1">— determines queue position</span>
              </label>
              <input v-model="walletForm.contributed_at" type="datetime-local" class="input" />
            </div>

            <!-- Notes -->
            <div>
              <label class="label">Notes <span class="text-slate-400 normal-case tracking-normal">(optional)</span></label>
              <input v-model="walletForm.notes" class="input" placeholder="e.g. June court fee, whatsapp payment…" maxlength="100" />
            </div>

            <p v-if="walletFormError" class="text-xs text-rose-600 px-1">{{ walletFormError }}</p>

            <button class="w-full py-3 rounded-xl font-bold text-white text-sm transition active:scale-[.98]"
              style="background:linear-gradient(135deg,#a855f7,#7c3aed)"
              :disabled="walletFormSaving"
              @click="saveContrib">
              {{ walletFormSaving ? 'Saving…' : walletEditId ? '✓ Update Contribution' : '💰 Record Contribution' }}
            </button>
          </div>
        </div>
      </div>
    </Teleport>

    <!-- ══════════════════════════ DELETE EXPENSE CONFIRM ═════════════════ -->
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
            <button class="flex-1 py-3 rounded-xl text-sm font-semibold text-slate-300 border border-white/10 hover:border-white/25 hover:text-white transition"
              @click="confirmDelId = null">Cancel</button>
            <button class="flex-1 py-3 rounded-xl text-sm font-bold text-white transition active:scale-[.97]"
              style="background:rgba(220,38,38,.85); border:1px solid rgba(244,63,94,.4)"
              @click="doDelete">Yes, Delete</button>
          </div>
        </div>
      </div>
    </Teleport>

    <!-- ══════════════════════════ DELETE WALLET CONFIRM ══════════════════ -->
    <Teleport to="body">
      <div v-if="confirmDelWallet"
        class="fixed inset-0 z-50 flex items-center justify-center px-5"
        style="background:rgba(0,0,0,.75); backdrop-filter:blur(6px)"
        @click.self="confirmDelWallet = null">
        <div class="w-full max-w-sm rounded-2xl p-6"
          style="background:#0d1a2e; border:1px solid rgba(168,85,247,.25); box-shadow:0 0 40px rgba(168,85,247,.1)">
          <div class="text-center mb-4">
            <div class="inline-flex w-14 h-14 rounded-2xl items-center justify-center text-3xl mb-3"
              style="background:rgba(168,85,247,.12); border:1px solid rgba(168,85,247,.25)">💰</div>
            <h3 class="font-display text-lg font-bold text-slate-100">Delete Contribution?</h3>
            <p class="text-sm text-slate-400 mt-1">The FIFO queue and wallet balance will update accordingly.</p>
          </div>
          <div class="flex gap-3">
            <button class="flex-1 py-3 rounded-xl text-sm font-semibold text-slate-300 border border-white/10 hover:border-white/25 hover:text-white transition"
              @click="confirmDelWallet = null">Cancel</button>
            <button class="flex-1 py-3 rounded-xl text-sm font-bold text-white transition active:scale-[.97]"
              style="background:rgba(220,38,38,.85); border:1px solid rgba(244,63,94,.4)"
              @click="doDeleteContrib">Yes, Delete</button>
          </div>
        </div>
      </div>
    </Teleport>

  </template>
</template>
