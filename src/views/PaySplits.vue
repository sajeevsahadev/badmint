<script setup>
import { ref, computed, watch, onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { supabase } from '../lib/supabase'
import { useClub } from '../composables/useClub'
import { useAuth } from '../composables/useAuth'
import { computeSettledEdges } from '../utils/settle-up'
import { aed, fmtExpMonth, fmtExpDay, timeAgo } from '../utils/formatters'
import PageHeader from '../components/PageHeader.vue'

const route  = useRoute()
const router = useRouter()

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

const CAT_COLORS = {
  facility:  '#00e5ff',
  food:      '#fbbf24',
  drinks:    '#a855f7',
  equipment: '#34d399',
  transport: '#f87171',
  tax:       '#94a3b8',
  other:     '#6b7280',
}
const CAT_BG = {
  facility:  'rgba(0,229,255,.13)',
  food:      'rgba(251,191,36,.13)',
  drinks:    'rgba(168,85,247,.13)',
  equipment: 'rgba(52,211,153,.13)',
  transport: 'rgba(248,113,113,.13)',
  tax:       'rgba(148,163,184,.13)',
  other:     'rgba(107,114,128,.13)',
}
const catColorBg = v => CAT_BG[v] ?? 'rgba(129,140,248,.13)'

// custom categories — stored in localStorage per club
const customCategories = ref([])
const allCategories    = computed(() => [...CATEGORIES, ...customCategories.value])

const catIcon  = v => allCategories.value.find(c => c.value === v)?.icon  ?? '🏷️'
const catLabel = v => allCategories.value.find(c => c.value === v)?.label ?? v
const catColor = v => CAT_COLORS[v] ?? '#818cf8'
const fmtDate = d => new Date(d + 'T00:00:00').toLocaleDateString('en-AE', { day: 'numeric', month: 'short', year: 'numeric' })
const fmtDatetime = ts => new Date(ts).toLocaleString('en-AE', {
  day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit'
})
const toDatetimeLocal = d => new Date(d).toISOString().slice(0, 16)

// ── State ──────────────────────────────────────────────────────────────
const expenses        = ref([])
const balances        = ref([])
const players         = ref([])
const notes           = ref([])
const myPlayer        = ref(null)
const walletData      = ref({ contributions: [], wallet_expenses: [], player_balances: [] })
const fifoResult      = ref({ active: [], consumed: [] })
const openingBalances = ref([])
const loading         = ref(true)
const activeTab       = ref('activities')
const expandedPlayer  = ref(null)

// Splitwise-style "simplify debts" toggle — ON restructures who-pays-whom
// into the fewest payments; OFF shows debts exactly as recorded.
const simplifyOn = ref(localStorage.getItem('b360_simplify_debts') !== '0')
watch(simplifyOn, v => localStorage.setItem('b360_simplify_debts', v ? '1' : '0'))

// "Plus N more balances" collapse in the top summary card
const showAllMyBalance = ref(false)

// Opening balances section collapsed by default in Expenses tab
const showOpeningBalances = ref(false)

// ── Load all data ──────────────────────────────────────────────────────
async function load() {
  if (!currentClub.value || !user.value) {
    loading.value = false   // don't stay stuck; no-club handled in template
    return
  }
  loading.value = true
  const cid = currentClub.value.club_id
  try {
  const [plRes, expRes, balRes, noteRes, myPlRes, wRes, obRes, fifoRes] = await Promise.all([
    supabase.rpc('get_club_players', { p_club_id: cid }),
    supabase.rpc('get_expenses', { p_club_id: cid }),
    supabase.rpc('get_balance_summary', { p_club_id: cid }),
    supabase.from('paysplit_notes')
      .select('id, content, created_at, created_by')
      .eq('club_id', cid).order('created_at', { ascending: false }),
    supabase.from('players')
      .select('id, display_name, user_id')
      .eq('club_id', cid).eq('user_id', user.value.id).maybeSingle(),
    supabase.rpc('get_wallet_data', { p_club_id: cid }),
    supabase.rpc('get_opening_balances', { p_club_id: cid }),
    supabase.rpc('get_fifo_result', { p_club_id: cid })
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

  // Tolerate the v19 migration not being applied yet; show newest entry first
  openingBalances.value = obRes.error ? [] : [...(obRes.data ?? [])].sort(
    (a, b) => new Date(b.updated_at) - new Date(a.updated_at)
  )

  // FIFO from server (O(C+W) SQL) — falls back to empty if v36b not yet applied
  fifoResult.value = fifoRes.data ?? { active: [], consumed: [] }
  loadCats()
  } finally {
    loading.value = false
  }
}

onMounted(() => {
  load()
  const tab = route.query.tab
  if (tab && ['activities','balance','wallet','totals','notes'].includes(tab)) {
    activeTab.value = tab
  }
})
watch(currentClub, () => { expandedPlayer.value = null; load() })
watch(() => route.query.tab, (tab) => {
  if (tab && ['activities','balance','wallet','totals','notes'].includes(tab)) {
    activeTab.value = tab
  }
})

// ── Permission helper: creator or club manager/owner ───────────────────
function canModify(item) {
  return item.created_by === user.value?.id || isManager()
}

// ── Net positions feeding settle-up ────────────────────────────────────
// "Club Pool" pseudo-party used in the unsimplified view for debts that have
// no single counterparty (wallet consumption, opening balances).
const POOL_ID = '__pool__'

// Wallet net positions — derived from actual FIFO consumption, not a uniform ratio.
// For each player: net = (amount FIFO consumed from their contributions) − (their wallet expense share)
// sum(consumed) = totalWalletExpenses = sum(expense_shares), so nets always sum to zero. ✓
// This correctly attributes wallet credits to whoever contributed first (per FIFO order),
// rather than spreading credit proportionally across ALL contributors regardless of order.
const walletNets = computed(() => {
  const allContribs = [...fifoResult.value.active, ...fifoResult.value.consumed]

  // How much FIFO actually consumed from each player's contributions
  const consumedByPlayer = {}
  allContribs.forEach(c => {
    const consumed = c.consumedBy.reduce((s, cb) => s + cb.amount, 0)
    if (!consumedByPlayer[c.player_id]) {
      consumedByPlayer[c.player_id] = { name: c.player_name, consumed: 0 }
    }
    consumedByPlayer[c.player_id].consumed =
      Math.round((consumedByPlayer[c.player_id].consumed + consumed) * 100) / 100
  })

  const nets = {}
  // Credit each contributor for how much FIFO drew from their wallet
  Object.entries(consumedByPlayer).forEach(([pid, data]) => {
    if (!nets[pid]) nets[pid] = { id: pid, name: data.name, net: 0 }
    nets[pid].net = Math.round((nets[pid].net + data.consumed) * 100) / 100
  })
  // Debit each participant for their share of wallet expenses
  ;(walletData.value.player_balances ?? []).forEach(b => {
    if (!nets[b.player_id]) nets[b.player_id] = { id: b.player_id, name: b.player_name, net: 0 }
    nets[b.player_id].net = Math.round((nets[b.player_id].net - Number(b.expense_share)) * 100) / 100
  })

  return Object.values(nets).filter(p => Math.abs(p.net) >= 0.01)
})

// Opening balances (v19): admin-entered starting position per player.
// Positive = player gets back, negative = player owes.
const openingNets = computed(() =>
  openingBalances.value
    .map(ob => ({ id: ob.player_id, name: ob.player_name, net: Math.round(Number(ob.amount) * 100) / 100 }))
    .filter(o => Math.abs(o.net) >= 0.01)
)

// When opening balances don't net to zero, the group can't fully settle —
// surfaced as a warning so the admin can correct the migration entries.
const openingSum = computed(() =>
  Math.round(openingNets.value.reduce((s, o) => s + o.net, 0) * 100) / 100
)

// ── Simplified: minimum transactions to clear ALL debts ───────────────
// 1. Compute each player's net from direct-pay expenses + wallet + opening.
// 2. Greedy: match biggest getter with biggest ower, repeat.
// Result: fewest possible payment edges — like Splitwise "simplify debts".
const settledEdges = computed(() => {
  const netMap = {}
  const addNet = (id, name, delta) => {
    if (!netMap[id]) netMap[id] = { id, name, net: 0 }
    netMap[id].net = Math.round((netMap[id].net + delta) * 100) / 100
  }
  balances.value.forEach(b => {
    addNet(b.from_player_id, b.from_name, -Number(b.net_amount))
    addNet(b.to_player_id,   b.to_name,   +Number(b.net_amount))
  })
  walletNets.value.forEach(w => addNet(w.id, w.name, w.net))
  openingNets.value.forEach(o => addNet(o.id, o.name, o.net))
  return computeSettledEdges(netMap).map(e => ({ ...e, kind: 'settle' }))
})

// ── Unsimplified: debts exactly as recorded ────────────────────────────
// Person-paid expenses stay pairwise; wallet and opening-balance positions
// are shown against the "Club Pool" since they have no single counterparty.
const directEdges = computed(() => {
  const edges = balances.value.map(b => ({
    fromId: b.from_player_id, fromName: b.from_name,
    toId:   b.to_player_id,   toName:   b.to_name,
    amount: Number(b.net_amount), kind: 'direct'
  }))
  walletNets.value.forEach(w => {
    if (w.net > 0) edges.push({ fromId: POOL_ID, fromName: 'Club Pool', toId: w.id, toName: w.name, amount: w.net, kind: 'wallet' })
    else           edges.push({ fromId: w.id, fromName: w.name, toId: POOL_ID, toName: 'Club Pool', amount: Math.abs(w.net), kind: 'wallet' })
  })
  openingNets.value.forEach(o => {
    if (o.net > 0) edges.push({ fromId: POOL_ID, fromName: 'Club Pool', toId: o.id, toName: o.name, amount: o.net, kind: 'opening' })
    else           edges.push({ fromId: o.id, fromName: o.name, toId: POOL_ID, toName: 'Club Pool', amount: Math.abs(o.net), kind: 'opening' })
  })
  return edges
})

const activeEdges = computed(() => simplifyOn.value ? settledEdges.value : directEdges.value)

// ── My balance summary — derived from the active edge set ─────────────
const myBalance = computed(() => {
  const mid = myPlayer.value?.id
  if (!mid) return null
  const owe  = activeEdges.value.filter(e => e.fromId === mid).map(e => ({ name: e.toName,   amount: e.amount }))
  const gets = activeEdges.value.filter(e => e.toId   === mid).map(e => ({ name: e.fromName, amount: e.amount }))
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
  const part = exp.participants?.find(p => p.player_id === mid)
  if (exp.paid_from_wallet) {
    return part ? { type: 'wallet', net: -Number(part.share) } : null
  }
  // Multi-payer
  if ((exp.payers?.length ?? 0) > 1) {
    const myPayer = exp.payers.find(p => p.player_id === mid)
    const paidAmt = myPayer ? Number(myPayer.amount) : 0
    const shareAmt = part ? Number(part.share) : 0
    if (!myPayer && !part) return null
    return { type: paidAmt > 0 ? 'paid' : 'split', net: paidAmt - shareAmt }
  }
  // Single payer
  const isPayer = exp.paid_player_id === mid
  if (!isPayer && !part) return null
  if (isPayer && !part) return { type: 'paid', net: Number(exp.amount) }
  if (isPayer &&  part) return { type: 'paid', net: Number(exp.amount) - Number(part.share) }
  return { type: 'split', net: -Number(part.share) }
}

// ── Balance tab list — derived from the active edge set ───────────────
// "Club Pool" never gets its own row; pool edges appear inside player rows.
const playerBalanceList = computed(() => {
  const map = {}
  const ensure = (id, name) => {
    if (!map[id]) map[id] = { id, name, owes: [], gets: [], net: 0 }
    return map[id]
  }
  activeEdges.value.forEach(({ fromId, fromName, toId, toName, amount, kind }) => {
    if (fromId !== POOL_ID) {
      const p = ensure(fromId, fromName)
      p.owes.push({ to: toName, toId, amount, kind })
      p.net = Math.round((p.net - amount) * 100) / 100
    }
    if (toId !== POOL_ID) {
      const p = ensure(toId, toName)
      p.gets.push({ from: fromName, fromId, amount, kind })
      p.net = Math.round((p.net + amount) * 100) / 100
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

// fifoResult is loaded from the server via get_fifo_result() RPC in load()
// (replaces the former O(n²) browser loop)

const expandedConsumed = ref(null)
const expandedExp      = ref(null)

// For wallet-paid expenses: map expenseId → [{ name, player_id, amount }]
// Inverts fifoResult.consumedBy so the collapsed card can show who funded it.
const walletExpenseContributors = computed(() => {
  const map = {}
  const allContribs = [...fifoResult.value.active, ...fifoResult.value.consumed]
  allContribs.forEach(c => {
    c.consumedBy.forEach(cb => {
      if (!map[cb.expenseId]) map[cb.expenseId] = []
      map[cb.expenseId].push({ name: c.player_name, player_id: c.player_id, amount: cb.amount })
    })
  })
  return map
})

// Auto-expand the current user's row when switching to the Balance tab;
// also collapse the "Plus N more" summary each time.
watch(activeTab, tab => {
  showAllMyBalance.value = false
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

// Group expenses by month for the Splitwise-style list (newest month first)
const expensesByMonth = computed(() => {
  const groups = {}
  expenses.value.forEach(e => {
    const key = e.expense_date?.slice(0, 7) ?? 'unknown'
    if (!groups[key]) groups[key] = { monthKey: key, expenses: [], total: 0 }
    groups[key].expenses.push(e)
    groups[key].total = Math.round((groups[key].total + Number(e.amount)) * 100) / 100
  })
  return Object.entries(groups)
    .sort((a, b) => b[0].localeCompare(a[0]))
    .map(([key, g]) => {
      const [y, m] = key.split('-').map(Number)
      return { ...g, label: isNaN(m) ? key : `${MONTHS[m - 1]} ${y}` }
    })
})

// ── Add / Edit expense form ────────────────────────────────────────────
const showForm   = ref(false)
const editingId  = ref(null)
const formError  = ref(null)
const formSaving = ref(false)

const expSchedAttendeeIds = ref(new Set())
const showAllExpPlayers   = ref(false)

const formDisplayPlayers = computed(() => {
  const active = players.value.filter(p => p.is_active)
  if (!expSchedAttendeeIds.value.size || showAllExpPlayers.value) return active
  return active.filter(p => expSchedAttendeeIds.value.has(p.id))
})

async function checkExpenseAttendees(date) {
  expSchedAttendeeIds.value = new Set()
  showAllExpPlayers.value   = false
  if (!currentClub.value || !date) return
  const { data: sched } = await supabase
    .from('club_schedule').select('id')
    .eq('club_id', currentClub.value.club_id)
    .eq('scheduled_date', date)
    .maybeSingle()
  if (!sched) return
  const { data: atts } = await supabase.rpc('get_schedule_attendees', { p_schedule_id: sched.id })
  if (atts?.length) {
    expSchedAttendeeIds.value = new Set(atts.map(a => a.player_id))
    form.value.participant_ids = atts
      .map(a => a.player_id)
      .filter(id => players.value.find(p => p.id === id && p.is_active))
  }
}

const titleAutoFilledFrom = ref(null)

function selectCategory(cat) {
  form.value.category = cat.value
  if (!form.value.title.trim() || form.value.title === titleAutoFilledFrom.value) {
    form.value.title = cat.label
    titleAutoFilledFrom.value = cat.label
  }
}

const blankForm = () => ({
  title:           '',
  category:        'other',
  amount:          '',
  paymentSource:   'person',
  paid_player_id:  myPlayer.value?.id ?? '',
  multiPayer:      false,
  payers:          [],
  expense_date:    new Date().toISOString().slice(0, 10),
  notes:           '',
  participant_ids: players.value.filter(p => p.is_active).map(p => p.id)
})

const form = ref(blankForm())

watch(() => form.value.expense_date, date => {
  if (showForm.value && !editingId.value) checkExpenseAttendees(date)
})

function openAddForm() {
  editingId.value = null
  form.value      = blankForm()
  formError.value = null
  titleAutoFilledFrom.value = null
  expSchedAttendeeIds.value = new Set()
  showAllExpPlayers.value   = false
  showForm.value  = true
  checkExpenseAttendees(form.value.expense_date)
}

function openEditForm(exp) {
  editingId.value = exp.id
  const isMulti = !exp.paid_from_wallet && (exp.payers?.length ?? 0) > 1
  form.value = {
    title:           exp.title,
    category:        exp.category,
    amount:          String(exp.amount),
    paymentSource:   exp.paid_from_wallet ? 'wallet' : 'person',
    paid_player_id:  exp.paid_player_id ?? '',
    multiPayer:      isMulti,
    payers:          isMulti
      ? (exp.payers ?? []).map(p => ({ player_id: p.player_id, amount: String(p.amount) }))
      : [],
    expense_date:    exp.expense_date,
    notes:           exp.notes ?? '',
    participant_ids: (exp.participants ?? []).map(p => p.player_id)
  }
  formError.value = null
  titleAutoFilledFrom.value = null
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
  if (!form.value.participant_ids.length){ formError.value = 'Select at least one participant'; return }

  const isWallet = form.value.paymentSource === 'wallet'
  const isMulti  = !isWallet && form.value.multiPayer

  if (isMulti) {
    if (!form.value.payers.length) { formError.value = 'Add at least one payer'; return }
    const payerTotal = form.value.payers.reduce((s, p) => s + (parseFloat(p.amount) || 0), 0)
    if (Math.abs(payerTotal - amt) > 0.01) {
      formError.value = `Payer amounts total ${aed(payerTotal)} but expense is ${aed(amt)} — they must match`
      return
    }
    if (form.value.payers.some(p => !p.player_id || !(parseFloat(p.amount) > 0))) {
      formError.value = 'Each payer must have a player selected and a valid amount'
      return
    }
  } else if (!isWallet && !form.value.paid_player_id) {
    formError.value = 'Select who paid'
    return
  }

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
  const payersPayload = isMulti
    ? form.value.payers.map(p => ({ player_id: p.player_id, amount: parseFloat(p.amount) }))
    : null

  const params = {
    p_club_id:          currentClub.value.club_id,
    p_title:            form.value.title.trim(),
    p_category:         form.value.category,
    p_amount:           amt,
    p_paid_player_id:   (isWallet || isMulti) ? null : form.value.paid_player_id,
    p_expense_date:     form.value.expense_date,
    p_participant_ids:  form.value.participant_ids,
    p_notes:            form.value.notes.trim() || null,
    p_paid_from_wallet: isWallet,
    p_payers:           payersPayload
  }

  const { p_club_id: _cid, ...updateParams } = params
  const { error } = editingId.value
    ? await supabase.rpc('update_expense', { p_expense_id: editingId.value, ...updateParams })
    : await supabase.rpc('add_expense', params)

  formSaving.value = false
  if (error) { formError.value = error.message; return }

  // Fire-and-forget: notify club members about new expense (new expenses only, not edits)
  if (!editingId.value) {
    const isWallet = form.value.paymentSource === 'wallet'
    const isMultiPayer = !isWallet && form.value.multiPayer && form.value.payers.length > 1
    const paidByName = isWallet
      ? 'Club Wallet'
      : isMultiPayer
        ? form.value.payers.map(p => players.value.find(pl => pl.id === p.player_id)?.display_name ?? '?').join(', ')
        : players.value.find(p => p.id === form.value.paid_player_id)?.display_name ?? 'Unknown'
    supabase.functions.invoke('send-expense-email', {
      body: {
        club_id:      currentClub.value.club_id,
        title:        form.value.title.trim(),
        amount:       parseFloat(form.value.amount),
        paid_by_name: paidByName,
        split_count:  form.value.participant_ids.length,
      }
    }).catch(() => {})
  }

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
  const { error } = await supabase.rpc('delete_expense', { p_expense_id: id })
  deletingId.value = null
  if (error) { formError.value = error.message; await load(); return }
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
  const { error } = await supabase.rpc('delete_wallet_contribution', { p_id: id })
  if (error) { formError.value = error.message; await load(); return }
  await load()
}

// ── Opening balances (v19) — club admin only ───────────────────────────
const showObForm   = ref(false)
const obFormError  = ref(null)
const obFormSaving = ref(false)
const confirmDelOb = ref(null)   // player_id pending delete

const blankObForm = () => ({ player_id: '', direction: 'gets', amount: '', notes: '' })
const obForm = ref(blankObForm())

function openObAddForm() {
  obForm.value      = blankObForm()
  obFormError.value = null
  showObForm.value  = true
}

function openObEditForm(ob) {
  obForm.value = {
    player_id: ob.player_id,
    direction: Number(ob.amount) >= 0 ? 'gets' : 'owes',
    amount:    String(Math.abs(Number(ob.amount))),
    notes:     ob.notes ?? ''
  }
  obFormError.value = null
  showObForm.value  = true
}

async function saveOb() {
  obFormError.value = null
  const amt = parseFloat(obForm.value.amount)
  if (!obForm.value.player_id) { obFormError.value = 'Select a player'; return }
  if (!amt || amt <= 0)        { obFormError.value = 'Enter a valid amount'; return }

  obFormSaving.value = true
  const { error } = await supabase.rpc('set_opening_balance', {
    p_club_id:   currentClub.value.club_id,
    p_player_id: obForm.value.player_id,
    p_amount:    obForm.value.direction === 'owes' ? -amt : amt,
    p_notes:     obForm.value.notes.trim() || null
  })
  obFormSaving.value = false
  if (error) { obFormError.value = error.message; return }
  showObForm.value = false
  await load()
}

async function doDeleteOb() {
  const pid = confirmDelOb.value
  if (!pid) return
  confirmDelOb.value = null
  const { error } = await supabase.rpc('delete_opening_balance', {
    p_club_id: currentClub.value.club_id, p_player_id: pid
  })
  if (error) { formError.value = error.message; await load(); return }
  await load()
}

// ── Notes ──────────────────────────────────────────────────────────────
const noteText   = ref('')
const noteSaving = ref(false)

async function addNote() {
  if (!noteText.value.trim()) return
  noteSaving.value = true
  const { error } = await supabase.from('paysplit_notes').insert({
    club_id:    currentClub.value.club_id,
    content:    noteText.value.trim(),
    created_by: user.value.id
  })
  noteSaving.value = false
  if (error) { formError.value = error.message; return }
  noteText.value = ''
  await load()
}

const confirmDelNoteId = ref(null)

async function deleteNote() {
  const id = confirmDelNoteId.value
  confirmDelNoteId.value = null
  if (!id) return
  const { error } = await supabase.from('paysplit_notes').delete().eq('id', id)
  if (error) { formError.value = error.message; await load(); return }
  notes.value = notes.value.filter(n => n.id !== id)
}

const perShare = computed(() => {
  const amt = parseFloat(form.value.amount)
  const n   = form.value.participant_ids.length
  if (!amt || !n) return null
  return (amt / n).toFixed(2)
})

const isMe = id => myPlayer.value?.id === id

// Resolve display name of any auth-user UUID from the club's player list
const resolveUserName = uid => {
  if (!uid) return 'Member'
  if (uid === user.value?.id) return 'You'
  return players.value.find(p => p.user_id === uid)?.display_name ?? 'Manager'
}

// Resolve which player record created an expense (for the expanded card "Added by" line)
const expCreatorPlayer = exp => players.value.find(p => p.user_id === exp.created_by) ?? null

// ── Custom categories (per-club, localStorage) ─────────────────────────
const showAddCat = ref(false)
const newCatName = ref('')

function loadCats() {
  const cid = currentClub.value?.club_id
  if (!cid) { customCategories.value = []; return }
  try {
    const stored = localStorage.getItem(`b360_cats_${cid}`)
    customCategories.value = stored ? JSON.parse(stored) : []
  } catch { customCategories.value = [] }
}

function saveCats() {
  const cid = currentClub.value?.club_id
  if (!cid) return
  localStorage.setItem(`b360_cats_${cid}`, JSON.stringify(customCategories.value))
}

function confirmAddCategory() {
  const name = newCatName.value.trim()
  if (!name) return
  const value = 'custom_' + Date.now()
  customCategories.value = [...customCategories.value, { value, label: name, icon: '🏷️' }]
  form.value.category = value
  saveCats()
  showAddCat.value = false
  newCatName.value = ''
}

// ── Category breakdown for Insights tab ───────────────────────────────
const categoryBreakdown = computed(() => {
  const map = {}
  expenses.value.forEach(e => {
    const cat = e.category ?? 'other'
    if (!map[cat]) map[cat] = { label: catLabel(cat), icon: catIcon(cat), color: catColor(cat), total: 0, count: 0 }
    map[cat].total  = Math.round((map[cat].total + Number(e.amount)) * 100) / 100
    map[cat].count++
  })
  const grandTotal = Object.values(map).reduce((s, v) => s + v.total, 0)
  return Object.entries(map)
    .map(([key, v]) => ({ key, ...v, pct: grandTotal > 0 ? Math.round(v.total / grandTotal * 100) : 0 }))
    .sort((a, b) => b.total - a.total)
})
</script>

<template>
  <!-- No club selected -->
  <div v-if="!currentClub && !loading" class="card p-10 text-center fade-up">
    <div class="text-4xl mb-3">💰</div>
    <p class="font-bold text-slate-600 text-lg mb-1">No club selected</p>
    <p class="text-slate-400 text-sm mb-4">Select a club from <strong>My Clubs</strong> or the top bar to view PaySplits.</p>
    <RouterLink to="/clubs" class="btn-primary inline-block px-6 py-2">Go to My Clubs</RouterLink>
  </div>

  <div v-else-if="loading" class="space-y-3">
    <div v-for="i in 4" :key="i" class="h-20 shimmer rounded-2xl" />
  </div>

  <template v-else>
    <PageHeader icon="💰" title="PaySplits" subtitle="Track & split court costs equally among players">
      <template #help>
        <div class="text-xs space-y-1.5">
          <p><strong class="text-slate-800">Activities</strong> — Full expense list with your contribution per item. Only the person who added an entry (or a manager) can edit or delete it.</p>
          <p><strong class="text-slate-800">Balance</strong> — Who owes whom. With <strong>Simplify debts ON</strong>, the app restructures debts into the fewest possible payments (totals never change). OFF shows debts exactly as recorded. Tap a name to expand.</p>
          <p><strong class="text-slate-800">Opening Balances</strong> — Migrating from another app? A club admin can record each player's starting balance once (positive = gets back, negative = owes).</p>
          <p><strong class="text-slate-800">Wallet</strong> — Shared cash pool. Contributions are consumed oldest-first (FIFO) when a wallet expense is recorded.</p>
          <p><strong class="text-slate-800">Insights</strong> — Category breakdown chart, monthly spending, and all-time summary.</p>
          <p><strong class="text-slate-800">Notes</strong> — Shared notepad for payment reminders.</p>
        </div>
      </template>
    </PageHeader>

    <!-- ── Summary card ── -->
    <div class="card-neon p-4 mb-4 fade-up">
      <div v-if="myBalance">
        <!-- Settled -->
        <div v-if="Math.abs(myBalance.net) < 0.01" class="text-base font-bold text-slate-300">
          All settled up! 🎉
        </div>
        <!-- Owe overall -->
        <div v-if="myBalance.net < -0.01">
          <div class="text-xs text-slate-500 mb-0.5">You owe overall</div>
          <div class="text-2xl font-extrabold text-rose-400 mb-3">{{ aed(Math.abs(myBalance.net)) }}</div>
        </div>
        <!-- Get back overall -->
        <div v-if="myBalance.net > 0.01">
          <div class="text-xs text-slate-500 mb-0.5">You get back overall</div>
          <div class="text-2xl font-extrabold text-emerald-400 mb-3">+{{ aed(myBalance.net) }}</div>
        </div>
        <!-- Individual debts — Splitwise style list -->
        <div v-if="myBalance.owe.length || myBalance.gets.length" class="space-y-2">
          <template v-for="(o, i) in myBalance.owe" :key="'owe-' + o.name">
            <div v-if="showAllMyBalance || i < 2" class="flex items-center justify-between">
              <span class="text-sm text-slate-400">You owe <span class="text-slate-200 font-medium">{{ o.name }}</span></span>
              <span class="text-sm font-bold text-rose-400">{{ aed(o.amount) }}</span>
            </div>
          </template>
          <template v-for="(g, i) in myBalance.gets" :key="'get-' + g.name">
            <div v-if="showAllMyBalance || (myBalance.owe.length + i) < 2" class="flex items-center justify-between">
              <span class="text-sm text-slate-400"><span class="text-slate-200 font-medium">{{ g.name }}</span> pays you</span>
              <span class="text-sm font-bold text-emerald-400">{{ aed(g.amount) }}</span>
            </div>
          </template>
          <button v-if="!showAllMyBalance && (myBalance.owe.length + myBalance.gets.length) > 2"
            @click="showAllMyBalance = true"
            class="text-xs text-neon hover:opacity-75 transition pt-0.5">
            Plus {{ myBalance.owe.length + myBalance.gets.length - 2 }} other {{ (myBalance.owe.length + myBalance.gets.length - 2) === 1 ? 'balance' : 'balances' }}
          </button>
        </div>
      </div>
      <div v-if="!myBalance" class="text-sm text-slate-500">
        No player record found for your account in this club yet.
      </div>
    </div>

    <!-- ── Tab bar (5 tabs) ── -->
    <div class="flex gap-1 mb-4 rounded-2xl p-1" style="background:rgba(255,255,255,.05); border:1px solid rgba(255,255,255,.07)">
      <button v-for="t in [
          { key: 'activities', label: 'Expenses' },
          { key: 'balance',    label: 'Balance' },
          { key: 'wallet',     label: 'Wallet' },
          { key: 'totals',     label: 'Insights' },
          { key: 'notes',      label: 'Notes' }
        ]" :key="t.key"
        @click="activeTab = t.key"
        class="flex-1 py-2.5 rounded-xl text-xs font-semibold transition-all duration-200"
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

      <!-- Expenses grouped by month — Splitwise style -->
      <template v-for="group in expensesByMonth" :key="group.monthKey">
        <!-- Month header -->
        <div class="flex items-center gap-2 mt-5 mb-2 first:mt-0">
          <span class="text-xs font-semibold text-slate-400">{{ group.label }}</span>
          <div class="flex-1 h-px" style="background:rgba(255,255,255,.07)"/>
          <span class="text-[10px] text-slate-600">{{ aed(group.total) }}</span>
        </div>

        <div v-for="exp in group.expenses" :key="exp.id" class="card mb-2 overflow-hidden">
          <!-- Collapsed row — tap to expand -->
          <button class="w-full flex items-center gap-3 px-4 py-3 text-left"
            @click="expandedExp = expandedExp === exp.id ? null : exp.id">
            <!-- Date column -->
            <div class="flex flex-col items-center w-7 shrink-0 select-none">
              <span class="text-[10px] text-slate-500 uppercase leading-none">{{ fmtExpMonth(exp.expense_date) }}</span>
              <span class="text-lg font-bold text-slate-200 leading-snug">{{ fmtExpDay(exp.expense_date) }}</span>
            </div>
            <!-- Category icon with tinted bg -->
            <div class="w-10 h-10 rounded-xl flex items-center justify-center text-xl shrink-0"
              :style="{ background: catColorBg(exp.category) }">
              {{ catIcon(exp.category) }}
            </div>
            <!-- Title + payer -->
            <div class="flex-1 min-w-0">
              <div class="flex items-center gap-1.5 mb-0.5">
                <span class="font-semibold text-sm text-slate-100 truncate">{{ exp.title }}</span>
                <span v-if="exp.paid_from_wallet"
                  class="shrink-0 text-[11px] font-bold px-2 py-0.5 rounded-md"
                  style="background:rgba(168,85,247,.18); color:#c084fc; border:1px solid rgba(168,85,247,.3)">
                  💰 WALLET
                </span>
              </div>
              <div class="text-xs text-slate-400">
                <template v-if="exp.paid_from_wallet">
                  <span>Wallet · </span>
                  <template v-if="walletExpenseContributors[exp.id]?.length">
                    <template v-for="(wc, i) in walletExpenseContributors[exp.id]" :key="wc.player_id">
                      <span v-if="i > 0">, </span>
                      <span class="text-slate-400">{{ wc.name }}</span>
                    </template>
                  </template>
                  <span v-else class="text-slate-500">common pool</span>
                  <span class="text-slate-600"> · {{ aed(exp.amount) }}</span>
                </template>
                <template v-else-if="(exp.payers?.length ?? 0) > 1">
                  <span class="text-slate-400">Multiple payers</span>
                  <span class="text-slate-600"> · {{ aed(exp.amount) }}</span>
                </template>
                <template v-else>
                  <span class="text-slate-400">{{ exp.paid_name }}</span>
                  <span> paid {{ aed(exp.amount) }}</span>
                </template>
              </div>
            </div>
            <!-- Your share -->
            <div v-if="myContrib(exp)" class="text-right shrink-0">
              <div class="text-xs leading-none mb-0.5"
                :class="myContrib(exp).net >= 0 ? 'text-emerald-500' : 'text-rose-500'">
                {{ myContrib(exp).net >= 0 ? 'you lent' : 'you borrowed' }}
              </div>
              <div class="font-bold text-sm"
                :class="myContrib(exp).net >= 0 ? 'text-emerald-400' : 'text-rose-400'">
                {{ aed(Math.abs(myContrib(exp).net)) }}
              </div>
            </div>
            <div v-else class="text-right shrink-0">
              <div class="text-xs text-slate-500 mb-0.5">total</div>
              <div class="font-bold text-sm text-slate-400">{{ aed(exp.amount) }}</div>
            </div>
          </button>

          <!-- Expanded details -->
          <div v-if="expandedExp === exp.id"
            class="px-4 pb-4 pt-3 border-t border-[rgba(15,23,42,0.05)]">

            <!-- Added by + timestamp -->
            <div class="flex items-center gap-1.5 mb-3">
              <span class="text-xs text-slate-500">Added by</span>
              <span class="text-xs font-medium"
                :class="expCreatorPlayer(exp) ? 'text-slate-300 underline underline-offset-2 cursor-pointer hover:text-neon transition-colors' : 'text-slate-400'"
                @click.stop="expCreatorPlayer(exp) && router.push('/player/' + expCreatorPlayer(exp).id)">
                {{ expCreatorPlayer(exp)?.display_name ?? (exp.created_by === user?.id ? 'You' : 'Member') }}
              </span>
              <span class="text-xs text-slate-500">·</span>
              <span class="text-xs text-slate-500">{{ fmtDatetime(exp.created_at) }}</span>
            </div>

            <!-- Wallet funding breakdown — shows exactly who funded how much via FIFO -->
            <div v-if="exp.paid_from_wallet && walletExpenseContributors[exp.id]?.length"
              class="rounded-xl overflow-hidden mb-3"
              style="background:rgba(168,85,247,.07); border:1px solid rgba(168,85,247,.18)">
              <div class="px-3 py-2 flex items-center gap-1.5">
                <span class="text-[10px] font-semibold uppercase tracking-wide" style="color:#c084fc">💰 Wallet funded by</span>
              </div>
              <div v-for="wc in walletExpenseContributors[exp.id]" :key="wc.player_id"
                class="flex items-center justify-between px-3 py-2 border-t"
                style="border-color:rgba(168,85,247,.12)">
                <span class="text-xs underline underline-offset-2 cursor-pointer hover:text-neon transition-colors"
                  :class="wc.player_id === myPlayer?.id ? 'text-neon font-semibold' : 'text-slate-300'"
                  @click.stop="router.push('/player/' + wc.player_id)">
                  {{ wc.player_id === myPlayer?.id ? 'You' : wc.name }}
                </span>
                <span class="text-xs font-semibold" style="color:#c084fc">{{ aed(wc.amount) }}</span>
              </div>
            </div>

            <!-- Multi-payer breakdown -->
            <div v-if="(exp.payers?.length ?? 0) > 1"
              class="rounded-xl overflow-hidden mb-3"
              style="background:rgba(0,180,216,.07); border:1px solid rgba(0,180,216,.2)">
              <div class="px-3 py-2 flex items-center gap-1.5">
                <span class="text-[10px] font-semibold uppercase tracking-wide" style="color:#0099b8">👥 Multiple payers</span>
              </div>
              <div v-for="mp in exp.payers" :key="mp.player_id"
                class="flex items-center justify-between px-3 py-2 border-t"
                style="border-color:rgba(0,180,216,.12)">
                <span class="text-xs"
                  :class="mp.player_id === myPlayer?.id ? 'text-neon font-semibold' : 'text-slate-300'">
                  {{ mp.player_id === myPlayer?.id ? 'You' : mp.name }}
                </span>
                <span class="text-xs font-semibold" style="color:#0099b8">{{ aed(mp.amount) }}</span>
              </div>
            </div>

            <!-- Split summary -->
            <div class="text-xs text-slate-400 mb-2">
              Split equally among {{ exp.participants?.length ?? 0 }} people
              <span v-if="exp.participants?.length">
                · {{ aed(Number(exp.amount) / exp.participants.length) }} each
              </span>
            </div>
            <div v-if="exp.participants?.length" class="flex flex-wrap gap-1.5 mb-3">
              <span v-for="pt in exp.participants" :key="pt.player_id"
                class="text-xs px-2.5 py-1 rounded-md"
                :class="pt.player_id === myPlayer?.id ? 'text-neon font-semibold' : 'text-slate-300'"
                style="background:rgba(255,255,255,.06); border:1px solid rgba(255,255,255,.09)">
                {{ pt.player_id === myPlayer?.id ? 'You' : pt.name }}
              </span>
            </div>
            <div v-if="canModify(exp)" class="flex items-center gap-3">
              <button class="text-xs text-slate-400 hover:text-neon transition"
                @click.stop="openEditForm(exp)">✏️ Edit</button>
              <button class="text-xs text-rose-400/70 hover:text-rose-400 transition ml-auto"
                :disabled="deletingId === exp.id"
                @click.stop="confirmDelId = exp.id">
                {{ deletingId === exp.id ? '⏳ Deleting…' : '🗑️ Delete' }}
              </button>
            </div>
          </div>
        </div>
      </template>

      <!-- ── Opening Balances (migration from another app) — collapsible ribbon ── -->
      <div class="card overflow-hidden mt-4">
        <!-- Ribbon header — always visible -->
        <button class="w-full px-4 py-3 flex items-center justify-between gap-3 text-left"
          @click="showOpeningBalances = !showOpeningBalances">
          <div class="min-w-0 flex-1">
            <div class="text-xs font-semibold text-slate-300">⚖️ Opening Balances</div>
            <div class="text-xs text-slate-500 mt-0.5">
              <template v-if="openingBalances.length">
                {{ openingBalances.length }} {{ openingBalances.length === 1 ? 'player' : 'players' }} ·
                net
                <span :class="Math.abs(openingSum) < 0.01 ? 'text-emerald-400' : 'text-amber-400'">
                  {{ openingSum >= 0 ? '' : '-' }}{{ aed(Math.abs(openingSum)) }}
                </span>
              </template>
              <template v-else>Starting balances from another app</template>
            </div>
          </div>
          <div class="flex items-center gap-2 shrink-0">
            <button v-if="isManager()" class="btn-primary text-xs px-3 py-1.5"
              @click.stop="openObAddForm">➕ Set</button>
            <span class="text-slate-400 text-sm transition-transform duration-200"
              :style="showOpeningBalances ? 'display:inline-block; transform:rotate(180deg)' : ''">▾</span>
          </div>
        </button>

        <!-- Expanded rows -->
        <template v-if="showOpeningBalances">
          <div class="border-t border-[rgba(15,23,42,0.06)]" />

          <div v-if="!openingBalances.length" class="px-4 py-5 text-center text-sm text-slate-500">
            No opening balances recorded.
            <span v-if="isManager()" class="block text-xs text-slate-600 mt-1">
              Migrating from Splitwise or another app? Tap "Set" to carry over each player's balance.
            </span>
          </div>

          <div v-for="ob in openingBalances" :key="ob.player_id"
            class="flex items-center justify-between gap-3 px-4 py-3 border-b border-[rgba(15,23,42,0.04)] last:border-0">
            <div class="min-w-0">
              <div class="text-sm font-semibold"
                :class="isMe(ob.player_id) ? 'text-neon' : 'text-slate-100'">
                {{ isMe(ob.player_id) ? 'You' : ob.player_name }}
              </div>
              <div v-if="ob.notes" class="text-xs text-slate-500 truncate">{{ ob.notes }}</div>
            </div>
            <div class="flex items-center gap-3 shrink-0">
              <span class="font-bold text-sm"
                :class="Number(ob.amount) >= 0 ? 'text-emerald-400' : 'text-rose-400'">
                {{ Number(ob.amount) >= 0 ? '+' : '' }}{{ aed(ob.amount) }}
              </span>
              <template v-if="isManager()">
                <button class="text-xs text-slate-500 hover:text-neon transition"
                  @click="openObEditForm(ob)">✏️</button>
                <button class="text-xs text-rose-500/60 hover:text-rose-400 transition"
                  @click="confirmDelOb = ob.player_id">🗑️</button>
              </template>
            </div>
          </div>
        </template>
      </div>
    </div>

    <!-- ══════════════════════════════ BALANCE ═════════════════════════════ -->
    <div v-if="activeTab === 'balance'" class="fade-up">

      <!-- Opening balances don't net to zero — group can't fully settle -->
      <div v-if="Math.abs(openingSum) >= 0.01"
        class="mb-3 px-3.5 py-2.5 rounded-xl text-[11px] leading-relaxed"
        style="background:rgba(251,191,36,.08); border:1px solid rgba(251,191,36,.25); color:#fbbf24">
        ⚠️ Opening balances net to <strong>{{ aed(openingSum) }}</strong> instead of zero,
        so the group can't fully settle. Ask an admin to adjust them in the Expenses tab.
      </div>

      <div v-if="!playerBalanceList.length" class="card p-10 text-center text-slate-400">
        <div class="text-4xl mb-3">⚖️</div>
        <p class="font-semibold mb-1">All settled!</p>
        <p class="text-sm">No outstanding balances in this club.</p>
      </div>

      <!-- Balance list — person rows -->
      <div class="space-y-2">
        <div v-for="p in playerBalanceList" :key="p.id"
          class="card overflow-hidden"
          :class="isMe(p.id) ? 'card-neon' : ''">

          <!-- Row header — tap to expand -->
          <button class="w-full flex items-center gap-3 px-4 py-4 text-left"
            @click="expandedPlayer = expandedPlayer === p.id ? null : p.id">

            <!-- Initials avatar -->
            <div class="w-10 h-10 rounded-full flex items-center justify-center text-sm font-bold shrink-0"
              :style="p.net > 0.01
                ? 'background:rgba(52,211,153,.15); color:#34d399; border:1px solid rgba(52,211,153,.3)'
                : 'background:rgba(248,113,113,.15); color:#f87171; border:1px solid rgba(248,113,113,.3)'">
              {{ p.name.slice(0, 2).toUpperCase() }}
            </div>

            <!-- Name + amount summary -->
            <div class="flex-1 min-w-0">
              <div class="font-semibold text-sm" :class="isMe(p.id) ? 'text-neon' : 'text-slate-100'">
                {{ isMe(p.id) ? 'You' : p.name }}
              </div>
              <div class="text-xs mt-0.5">
                <span :class="p.net > 0.01 ? 'text-emerald-400' : 'text-rose-400'">
                  {{ p.net > 0.01 ? 'get back ' : 'owe ' }}<span class="font-bold">{{ aed(Math.abs(p.net)) }}</span>
                </span>
                <span class="text-slate-500"> in total</span>
              </div>
            </div>

            <!-- Chevron -->
            <svg xmlns="http://www.w3.org/2000/svg" class="shrink-0 text-slate-500 transition-transform duration-200"
              :style="expandedPlayer === p.id ? 'transform:rotate(180deg)' : ''"
              width="16" height="16" viewBox="0 0 24 24" fill="none"
              stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
              <polyline points="6 9 12 15 18 9"></polyline>
            </svg>
          </button>

          <!-- Expanded: individual debt rows (Splitwise style) -->
          <div v-if="expandedPlayer === p.id" class="border-t border-[rgba(15,23,42,0.06)]">
            <!-- Debts this person owes -->
            <div v-for="o in p.owes" :key="o.toId + (o.kind ?? '')"
              class="flex items-center justify-between gap-3 px-5 py-3.5 border-b border-[rgba(15,23,42,0.04)] last:border-0">
              <div class="min-w-0">
                <div class="text-sm text-slate-300">
                  <span class="font-semibold">{{ isMe(p.id) ? 'You' : p.name }}</span>
                  <span class="text-slate-500"> owe{{ isMe(p.id) ? '' : 's' }} </span>
                  <span class="font-semibold">{{ o.to }}</span>
                </div>
                <div v-if="o.kind === 'wallet'" class="text-xs text-slate-400 mt-0.5">💰 wallet payment</div>
                <div v-if="o.kind === 'opening'" class="text-xs text-slate-400 mt-0.5">⚖️ opening balance</div>
              </div>
              <span class="text-rose-400 font-bold text-sm shrink-0">{{ aed(o.amount) }}</span>
            </div>
            <!-- Payments this person receives -->
            <div v-for="g in p.gets" :key="g.fromId + (g.kind ?? '')"
              class="flex items-center justify-between gap-3 px-5 py-3.5 border-b border-[rgba(15,23,42,0.04)] last:border-0">
              <div class="min-w-0">
                <div class="text-sm text-slate-300">
                  <span class="font-semibold">{{ g.from }}</span>
                  <span class="text-slate-500"> pays </span>
                  <span class="font-semibold">{{ isMe(p.id) ? 'you' : p.name }}</span>
                </div>
                <div v-if="g.kind === 'wallet'" class="text-[10px] text-slate-500 mt-0.5">💰 wallet payment</div>
                <div v-if="g.kind === 'opening'" class="text-[10px] text-slate-500 mt-0.5">⚖️ opening balance</div>
              </div>
              <span class="text-emerald-400 font-bold text-sm shrink-0">{{ aed(g.amount) }}</span>
            </div>
            <div v-if="!p.owes.length && !p.gets.length"
              class="px-5 py-4 text-sm text-slate-500 text-center">Settled up ✓</div>
          </div>
        </div>
      </div>

      <!-- Simplify debts toggle — bottom banner (Splitwise style) -->
      <div class="mt-4 flex items-center justify-between gap-3 px-4 py-3 rounded-2xl"
        style="background:rgba(0,229,255,.05); border:1px solid rgba(0,229,255,.1)">
        <p class="text-xs text-slate-400 leading-snug">
          <span class="font-semibold text-neon">Simplify debts</span> is {{ simplifyOn ? 'on' : 'off' }}
          <span class="text-slate-500">{{ simplifyOn
            ? ' — restructured into the fewest payments'
            : ' — showing debts exactly as recorded' }}</span>
        </p>
        <button @click="simplifyOn = !simplifyOn"
          class="shrink-0 px-3.5 py-1.5 rounded-full text-[11px] font-bold border transition-all duration-200"
          :class="simplifyOn ? 'text-slate-950 border-transparent' : 'text-slate-400 border-[rgba(15,23,42,0.15)] hover:border-[rgba(15,23,42,0.30)]'"
          :style="simplifyOn ? 'background:linear-gradient(135deg,#00e5ff,#0099cc)' : ''">
          {{ simplifyOn ? 'ON' : 'OFF' }}
        </button>
      </div>

    </div>

    <!-- ══════════════════════════════ WALLET ═════════════════════════════ -->
    <div v-if="activeTab === 'wallet'" class="fade-up space-y-4">

      <!-- Wallet balance summary -->
      <div class="card p-4">
        <div class="text-xs uppercase tracking-widest text-slate-400 mb-3">Common Wallet</div>
        <div class="text-center mb-3">
          <div class="text-xs text-slate-400 mb-1">Wallet Balance</div>
          <div class="text-2xl font-extrabold"
            :class="walletBalance >= 0 ? 'text-neon' : 'text-rose-400'">
            {{ aed(walletBalance) }}
          </div>
        </div>
        <div class="text-[10px] text-slate-600 text-center">
          Oldest contribution is consumed first (FIFO) when wallet pays an expense
        </div>
      </div>

      <!-- Add Contribution — managers/owners only; players can still add wallet-paid expenses -->
      <button v-if="isManager()" class="btn-primary w-full py-3 text-sm" @click="openWalletAddForm">
        ➕ Add Contribution
      </button>
      <div v-else class="text-center text-xs text-slate-500 py-2">
        Contributions are managed by club managers · you can still pay expenses from the wallet
      </div>

      <!-- ── Active FIFO Queue ── -->
      <div class="card overflow-hidden">
        <div class="px-4 py-2.5 border-b border-[rgba(15,23,42,0.06)]">
          <div class="text-xs font-semibold text-slate-300">FIFO Queue</div>
          <div class="text-xs text-slate-400">#1 is consumed first when wallet pays an expense</div>
        </div>

        <div v-if="!fifoResult.active.length" class="px-4 py-8 text-center text-sm text-slate-500">
          <div class="text-3xl mb-2">🪙</div>
          No active contributions. Add the first one!
        </div>

        <div v-for="(c, i) in fifoResult.active" :key="c.id"
          class="px-4 py-3 border-b border-[rgba(15,23,42,0.04)] last:border-0">
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
                <div class="text-xs text-slate-400">
                  {{ fmtDatetime(c.contributed_at) }}<span v-if="c.notes"> · {{ c.notes }}</span>
                </div>
                <div class="text-xs text-slate-500">
                  Added by {{ resolveUserName(c.created_by) }}
                </div>
              </div>
            </div>
            <div class="text-right shrink-0">
              <div class="font-bold text-emerald-400 text-base">{{ aed(c.remaining) }}</div>
              <div class="text-xs text-slate-400">of {{ aed(c.amount) }} received</div>
              <div v-if="c.amount - c.remaining > 0.005" class="text-xs text-rose-400 font-medium">−{{ aed(Math.round((c.amount - c.remaining) * 100) / 100) }} used</div>
            </div>
          </div>
          <!-- Partial consumption so far -->
          <div v-if="c.consumedBy.length" class="mt-2 ml-9 space-y-1.5">
            <div v-for="cb in c.consumedBy" :key="cb.expenseId"
              class="flex items-center justify-between text-xs">
              <span class="text-slate-300 font-medium">→ {{ cb.title }}<span v-if="cb.expense_date" class="text-slate-400 font-normal"> · {{ fmtDate(cb.expense_date) }}</span></span>
              <span class="text-rose-400 font-semibold shrink-0 ml-2">−{{ aed(cb.amount) }}</span>
            </div>
          </div>
          <div v-if="canModify(c)" class="flex gap-3 mt-2 ml-9">
            <button class="text-xs text-slate-400 hover:text-neon transition"
              @click="openWalletEditForm(c)">✏️ Edit</button>
            <button class="text-xs text-rose-400/70 hover:text-rose-400 transition"
              @click="confirmDelWallet = c.id">🗑️ Delete</button>
          </div>
        </div>
      </div>

      <!-- ── Consumed contributions ── -->
      <div v-if="fifoResult.consumed.length" class="card overflow-hidden">
        <div class="px-4 py-3 border-b border-[rgba(15,23,42,0.06)]">
          <div class="text-sm font-semibold text-slate-300">✓ Wallet Consumed</div>
          <div class="text-xs text-slate-400 mt-0.5">Fully used — tap to see which expenses</div>
        </div>

        <div v-for="c in fifoResult.consumed" :key="c.id"
          class="border-b border-[rgba(15,23,42,0.04)] last:border-0">

          <!-- Row (tap to expand) -->
          <button class="w-full px-4 py-3 flex items-center justify-between text-left"
            @click="expandedConsumed = expandedConsumed === c.id ? null : c.id">
            <div class="flex items-center gap-2.5 min-w-0">
              <div class="w-7 h-7 rounded-xl flex items-center justify-center text-sm shrink-0"
                style="background:rgba(100,116,139,.18); color:#94a3b8">✓</div>
              <div class="min-w-0">
                <div class="text-sm font-semibold text-slate-300">
                  {{ isMe(c.player_id) ? 'You' : c.player_name }}
                </div>
                <div class="text-xs text-slate-400">{{ fmtDatetime(c.contributed_at) }}<span v-if="c.notes"> · {{ c.notes }}</span></div>
                <div class="text-xs text-slate-500">Added by {{ resolveUserName(c.created_by) }}</div>
              </div>
            </div>
            <div class="flex items-center gap-2 shrink-0">
              <div class="font-bold text-slate-400 line-through text-sm">{{ aed(c.amount) }}</div>
              <span class="text-slate-400 text-xs transition-transform duration-200"
                :style="expandedConsumed === c.id ? 'transform:rotate(180deg)' : ''">▾</span>
            </div>
          </button>

          <!-- Expanded: expense breakdown -->
          <div v-if="expandedConsumed === c.id"
            class="px-4 pb-4 ml-9 space-y-2 border-t border-[rgba(15,23,42,0.06)]">
            <div class="pt-3 text-xs font-semibold text-slate-400 uppercase tracking-wide mb-2">Used for:</div>
            <div v-for="cb in c.consumedBy" :key="cb.expenseId"
              class="flex items-center justify-between rounded-xl px-3 py-2.5"
              style="background:rgba(255,255,255,.05); border:1px solid rgba(255,255,255,.09)">
              <span class="text-sm font-medium text-slate-200 min-w-0 truncate">
                {{ cb.title }}<span v-if="cb.expense_date" class="text-slate-400 font-normal text-xs"> · {{ fmtDate(cb.expense_date) }}</span>
              </span>
              <span class="text-sm font-bold text-rose-400 shrink-0 ml-3">−{{ aed(cb.amount) }}</span>
            </div>
            <div v-if="canModify(c)" class="flex gap-3 pt-1">
              <button class="text-xs text-slate-400 hover:text-neon transition"
                @click="openWalletEditForm(c)">✏️ Edit</button>
              <button class="text-xs text-rose-400/70 hover:text-rose-400 transition"
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
          <div class="text-xs uppercase tracking-widest text-slate-400 mb-1.5">All-time spent</div>
          <div class="text-xl font-extrabold text-gold">{{ aed(allTimeTotal) }}</div>
          <div class="text-xs text-slate-500 mt-1">{{ expenses.length }} expenses</div>
        </div>
        <div class="card p-4 text-center">
          <div class="text-xs uppercase tracking-widest text-slate-400 mb-1.5">{{ currentYear }} total</div>
          <div class="text-xl font-extrabold text-neon">{{ aed(yearTotal) }}</div>
          <div class="text-xs text-slate-500 mt-1">this year</div>
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

      <!-- Category Breakdown -->
      <div class="card p-4 mb-5">
        <div class="text-xs font-semibold text-slate-300 mb-4">By Category</div>
        <div v-if="!categoryBreakdown.length" class="text-sm text-slate-500 text-center py-4">
          No expenses yet
        </div>
        <div v-else class="space-y-4">
          <div v-for="c in categoryBreakdown" :key="c.key">
            <div class="flex items-center justify-between mb-1.5">
              <span class="text-xs text-slate-300 flex items-center gap-1.5">
                <span>{{ c.icon }}</span>
                <span>{{ c.label }}</span>
                <span class="text-xs text-slate-500">({{ c.count }})</span>
              </span>
              <div class="flex items-center gap-2">
                <span class="text-xs text-slate-400">{{ c.pct }}%</span>
                <span class="text-xs font-bold text-slate-200">{{ aed(c.total) }}</span>
              </div>
            </div>
            <div class="h-2 rounded-full" style="background:rgba(255,255,255,.06)">
              <div class="h-2 rounded-full transition-all duration-700"
                :style="{ width: c.pct + '%', background: c.color }" />
            </div>
          </div>
        </div>
      </div>

      <div class="card overflow-hidden">
        <div class="px-4 py-3 border-b border-[rgba(15,23,42,0.06)]">
          <div class="text-xs font-semibold text-slate-300">Monthly Breakdown</div>
        </div>
        <div v-if="!monthlyTrend.length" class="px-4 py-6 text-center text-sm text-slate-500">
          No expenses recorded yet.
        </div>
        <div v-for="m in monthlyTrend" :key="m.key"
          class="flex items-center justify-between px-4 py-3 border-b border-[rgba(15,23,42,0.04)] last:border-0">
          <span class="text-sm text-slate-300">{{ m.label }}</span>
          <span class="font-bold text-slate-100">{{ aed(m.total) }}</span>
        </div>
      </div>
    </div>

    <!-- ══════════════════════════════ NOTES ═══════════════════════════════ -->
    <div v-if="activeTab === 'notes'" class="fade-up">
      <div class="card p-4 mb-4">
        <div class="text-xs uppercase tracking-widest text-slate-400 mb-2">Add a Note</div>
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
            <div class="text-xs text-slate-400">
              <span class="font-medium text-slate-300">{{ n.author }}</span>
              · {{ timeAgo(n.created_at) }}
            </div>
            <button v-if="canModify(n)" class="text-xs text-rose-400/70 hover:text-rose-400 transition"
              @click="confirmDelNoteId = n.id">Delete</button>
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
              <input v-model="form.title" class="input" placeholder="e.g. Tea break, Court rent, Cork pack" maxlength="60"
                @input="titleAutoFilledFrom = null" />
            </div>

            <!-- Category chips -->
            <div>
              <label class="label">Category</label>
              <div class="flex flex-wrap gap-2">
                <button v-for="c in allCategories" :key="c.value"
                  @click="selectCategory(c)"
                  class="flex items-center gap-1.5 px-3 py-1.5 rounded-xl text-xs font-medium transition-all"
                  :class="form.category === c.value ? 'text-white font-bold' : 'text-slate-500 border border-slate-200 hover:border-slate-400'"
                  :style="form.category === c.value ? 'background:linear-gradient(135deg,#00b4cc,#0077a0)' : ''">
                  {{ c.icon }} {{ c.label }}
                </button>
                <!-- Add new category -->
                <div v-if="showAddCat" class="flex items-center gap-1.5 w-full mt-1">
                  <input v-model="newCatName" type="text" placeholder="Category name…"
                    class="input text-xs h-8 flex-1 px-2 py-1"
                    maxlength="30"
                    @keyup.enter="confirmAddCategory"
                    @keyup.escape="showAddCat = false; newCatName = ''" />
                  <button @click="confirmAddCategory"
                    class="px-3 h-8 rounded-xl text-xs font-semibold text-white shrink-0"
                    style="background:linear-gradient(135deg,#00b4cc,#0077a0)">Add</button>
                  <button @click="showAddCat = false; newCatName = ''"
                    class="text-slate-400 hover:text-slate-600 text-sm shrink-0">✕</button>
                </div>
                <button v-else
                  @click="showAddCat = true"
                  class="flex items-center gap-1 px-3 py-1.5 rounded-xl text-xs font-medium text-slate-400 transition-all hover:border-slate-400"
                  style="border:1px dashed rgba(100,116,139,.5)">
                  + Add new
                </button>
              </div>
            </div>

            <!-- Amount + Date -->
            <div class="grid grid-cols-2 gap-3">
              <div>
                <label class="label">Amount (AED)</label>
                <div class="relative">
                  <span class="absolute left-3 top-1/2 -translate-y-1/2 text-sm font-semibold text-slate-400 pointer-events-none">AED</span>
                  <input v-model="form.amount" type="number" min="0.01" step="0.01" class="input pl-12 text-right font-semibold" placeholder="0.00" />
                </div>
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
                  <span class="text-[11px] font-normal opacity-80">{{ aed(walletBalance) }} available</span>
                </button>
              </div>
              <!-- Wallet balance hint -->
              <div v-if="form.paymentSource === 'wallet'"
                class="mt-2 text-xs px-3 py-2 rounded-lg"
                :style="walletBalance > 0
                  ? 'background:rgba(0,153,184,.08); color:#0077a0; border:1px solid rgba(0,153,184,.2)'
                  : 'background:rgba(220,38,38,.06); color:#dc2626; border:1px solid rgba(220,38,38,.2)'">
                Wallet balance: {{ aed(walletBalance) }}
                {{ walletBalance < 0 ? ' — wallet is in deficit' : '' }}
              </div>
            </div>

            <!-- Paid by (only for person payment) -->
            <div v-if="form.paymentSource === 'person'">
              <label class="label">Who Paid?</label>
              <!-- Single / Multiple payer toggle -->
              <div class="flex gap-2 mb-3">
                <button
                  @click="form.multiPayer = false; form.payers = []"
                  class="flex-1 py-2 rounded-xl text-xs font-semibold transition-all"
                  :class="!form.multiPayer ? 'text-white' : 'text-slate-500 border border-slate-200'"
                  :style="!form.multiPayer ? 'background:linear-gradient(135deg,#00b4cc,#0077a0)' : ''">
                  👤 One person paid
                </button>
                <button
                  @click="form.multiPayer = true; form.paid_player_id = ''"
                  class="flex-1 py-2 rounded-xl text-xs font-semibold transition-all"
                  :class="form.multiPayer ? 'text-white' : 'text-slate-500 border border-slate-200'"
                  :style="form.multiPayer ? 'background:linear-gradient(135deg,#00b4cc,#0077a0)' : ''">
                  👥 Multiple people paid
                </button>
              </div>

              <!-- Single payer select -->
              <select v-if="!form.multiPayer" v-model="form.paid_player_id" class="input">
                <option value="" disabled>Who paid?</option>
                <option v-for="p in players.filter(p => p.is_active)" :key="p.id" :value="p.id">
                  {{ p.display_name }}{{ isMe(p.id) ? ' (you)' : '' }}
                </option>
              </select>

              <!-- Multi-payer: Splitwise-style — all players listed with amount inputs -->
              <div v-else>
                <div class="rounded-2xl overflow-hidden border border-slate-200 mb-2">
                  <div v-for="p in players.filter(p => p.is_active)" :key="p.id"
                    class="flex items-center gap-3 px-3 py-2.5 border-b border-slate-100 last:border-0"
                    :class="(form.payers.find(x => x.player_id === p.id)?.amount || 0) > 0 ? 'bg-cyan-50' : 'bg-white'">
                    <!-- Avatar -->
                    <div class="w-8 h-8 rounded-full flex items-center justify-center text-xs font-bold shrink-0 text-white"
                      :style="(form.payers.find(x => x.player_id === p.id)?.amount || 0) > 0
                        ? 'background:linear-gradient(135deg,#00b4cc,#0077a0)'
                        : 'background:#cbd5e1'">
                      {{ p.display_name.slice(0,2).toUpperCase() }}
                    </div>
                    <!-- Name -->
                    <span class="flex-1 text-sm font-medium text-slate-700 truncate">
                      {{ isMe(p.id) ? p.display_name + ' (you)' : p.display_name }}
                    </span>
                    <!-- Amount input -->
                    <div class="flex items-center gap-1 shrink-0">
                      <span class="text-xs text-slate-400 font-medium">AED</span>
                      <input
                        :value="form.payers.find(x => x.player_id === p.id)?.amount || ''"
                        @input="e => {
                          const idx = form.payers.findIndex(x => x.player_id === p.id)
                          const val = e.target.value
                          if (idx >= 0) { if (!val || parseFloat(val) <= 0) form.payers.splice(idx,1); else form.payers[idx].amount = val }
                          else if (val && parseFloat(val) > 0) form.payers.push({ player_id: p.id, amount: val })
                        }"
                        type="number" min="0" step="0.01" placeholder="0.00"
                        class="w-20 text-right text-sm font-semibold border-0 border-b-2 bg-transparent outline-none py-0.5 transition-colors"
                        :class="(form.payers.find(x => x.player_id === p.id)?.amount || 0) > 0
                          ? 'border-cyan-400 text-cyan-700'
                          : 'border-slate-200 text-slate-400'" />
                    </div>
                  </div>
                </div>
                <!-- Running total bar -->
                <div class="flex items-center justify-between px-3 py-2 rounded-xl text-xs font-semibold"
                  :style="Math.abs(form.payers.reduce((s,p) => s + (parseFloat(p.amount)||0), 0) - (parseFloat(form.amount)||0)) <= 0.01 && form.payers.length > 0
                    ? 'background:rgba(16,185,129,.1); color:#059669; border:1px solid rgba(16,185,129,.25)'
                    : 'background:rgba(239,68,68,.07); color:#dc2626; border:1px solid rgba(239,68,68,.2)'">
                  <span>{{ aed(form.payers.reduce((s,p) => s + (parseFloat(p.amount)||0), 0)) }} entered</span>
                  <span v-if="Math.abs(form.payers.reduce((s,p) => s + (parseFloat(p.amount)||0), 0) - (parseFloat(form.amount)||0)) <= 0.01 && form.payers.length > 0">✓ matches total</span>
                  <span v-else-if="form.payers.reduce((s,p) => s + (parseFloat(p.amount)||0), 0) < (parseFloat(form.amount)||0)">
                    {{ aed((parseFloat(form.amount)||0) - form.payers.reduce((s,p) => s + (parseFloat(p.amount)||0), 0)) }} remaining
                  </span>
                  <span v-else>{{ aed(form.payers.reduce((s,p) => s + (parseFloat(p.amount)||0), 0) - (parseFloat(form.amount)||0)) }} over</span>
                </div>
              </div>
            </div>

            <!-- Participants -->
            <div>
              <div class="flex items-center justify-between mb-2">
                <label class="label mb-0">Split Among</label>
                <div class="flex gap-3">
                  <button class="text-[10px] text-cyan-600 font-semibold"
                    @click="form.participant_ids = formDisplayPlayers.map(p => p.id)">All</button>
                  <button class="text-[10px] text-slate-400"
                    @click="form.participant_ids = []">None</button>
                  <button v-if="expSchedAttendeeIds.size"
                    class="text-[10px] font-semibold"
                    :class="showAllExpPlayers ? 'text-slate-400' : 'text-violet-400'"
                    @click="showAllExpPlayers = !showAllExpPlayers; form.participant_ids = showAllExpPlayers ? players.filter(p => p.is_active).map(p => p.id) : [...expSchedAttendeeIds].filter(id => players.find(p => p.id === id && p.is_active))">
                    {{ showAllExpPlayers ? 'Attendees' : 'Show all' }}
                  </button>
                </div>
              </div>

              <div v-if="expSchedAttendeeIds.size && !showAllExpPlayers"
                class="flex items-center gap-1.5 mb-2 px-2 py-1.5 rounded-lg text-[10px] text-violet-300"
                style="background:rgba(168,85,247,.1); border:1px solid rgba(168,85,247,.2)">
                <span>📋</span>
                <span>Showing players who attended on this date</span>
              </div>

              <div v-if="perShare && form.participant_ids.length"
                class="text-[11px] font-semibold mb-2" style="color:#0077a0">
                AED {{ perShare }} per person ({{ form.participant_ids.length }} selected)
              </div>

              <div class="grid grid-cols-2 gap-1.5 max-h-44 overflow-y-auto pr-1">
                <label v-for="p in formDisplayPlayers" :key="p.id"
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

    <!-- ══════════════════════════ OPENING BALANCE FORM ═══════════════════ -->
    <Teleport to="body">
      <div v-if="showObForm" class="fixed inset-0 z-50">
        <div class="absolute inset-0 bg-black/70" @click="showObForm = false" />
        <div class="absolute bottom-0 left-0 right-0 rounded-t-2xl overflow-hidden"
          style="background:#ffffff; border-top:1px solid rgba(251,191,36,.4); max-height:85vh">

          <div class="sticky top-0 px-4 pt-3 pb-3 z-10"
            style="background:#ffffff; border-bottom:1px solid rgba(0,0,0,.07)">
            <div class="w-10 h-1 rounded-full bg-slate-200 mx-auto mb-3" />
            <div class="flex items-center justify-between">
              <span class="font-semibold text-slate-800">⚖️ Set Opening Balance</span>
              <button @click="showObForm = false" class="text-slate-400 hover:text-slate-700 text-lg">✕</button>
            </div>
          </div>

          <div class="overflow-y-auto px-4 pb-8 space-y-4 pt-4" style="max-height: calc(85vh - 72px)">

            <p class="text-[11px] text-slate-500 leading-relaxed -mt-1">
              Carry over a player's balance from another app. One entry per player —
              saving again replaces the previous value. Admins only.
            </p>

            <!-- Player -->
            <div>
              <label class="label">Player</label>
              <select v-model="obForm.player_id" class="input">
                <option value="" disabled>Select player</option>
                <option v-for="p in players" :key="p.id" :value="p.id">
                  {{ p.display_name }}{{ isMe(p.id) ? ' (you)' : '' }}
                </option>
              </select>
            </div>

            <!-- Direction -->
            <div>
              <label class="label">Starting Position</label>
              <div class="flex gap-2">
                <button
                  @click="obForm.direction = 'gets'"
                  class="flex-1 py-2.5 rounded-xl text-xs font-semibold transition-all"
                  :class="obForm.direction === 'gets' ? 'text-white' : 'text-slate-500 border border-slate-200'"
                  :style="obForm.direction === 'gets' ? 'background:linear-gradient(135deg,#10b981,#059669)' : ''">
                  ➕ Gets back (group owes them)
                </button>
                <button
                  @click="obForm.direction = 'owes'"
                  class="flex-1 py-2.5 rounded-xl text-xs font-semibold transition-all"
                  :class="obForm.direction === 'owes' ? 'text-white' : 'text-slate-500 border border-slate-200'"
                  :style="obForm.direction === 'owes' ? 'background:linear-gradient(135deg,#f43f5e,#dc2626)' : ''">
                  ➖ Owes (they owe the group)
                </button>
              </div>
            </div>

            <!-- Amount -->
            <div>
              <label class="label">Amount (AED)</label>
              <input v-model="obForm.amount" type="number" min="0.01" step="0.01" class="input" placeholder="0.00" />
            </div>

            <!-- Notes -->
            <div>
              <label class="label">Notes <span class="text-slate-400 normal-case tracking-normal">(optional)</span></label>
              <input v-model="obForm.notes" class="input" placeholder="e.g. Splitwise balance as of June 2026" maxlength="100" />
            </div>

            <p v-if="obFormError" class="text-xs text-rose-600 px-1">{{ obFormError }}</p>

            <button class="w-full py-3 rounded-xl font-bold text-white text-sm transition active:scale-[.98]"
              style="background:linear-gradient(135deg,#f59e0b,#d97706)"
              :disabled="obFormSaving"
              @click="saveOb">
              {{ obFormSaving ? 'Saving…' : '⚖️ Save Opening Balance' }}
            </button>
          </div>
        </div>
      </div>
    </Teleport>

    <!-- ══════════════════════════ DELETE OPENING BALANCE CONFIRM ═════════ -->
    <Teleport to="body">
      <div v-if="confirmDelOb"
        class="fixed inset-0 z-50 flex items-center justify-center px-5"
        style="background:rgba(0,0,0,.75); backdrop-filter:blur(6px)"
        @click.self="confirmDelOb = null">
        <div class="w-full max-w-sm rounded-2xl p-6"
          style="background:#0d1a2e; border:1px solid rgba(251,191,36,.25); box-shadow:0 0 40px rgba(251,191,36,.1)">
          <div class="text-center mb-4">
            <div class="inline-flex w-14 h-14 rounded-2xl items-center justify-center text-3xl mb-3"
              style="background:rgba(251,191,36,.12); border:1px solid rgba(251,191,36,.25)">⚖️</div>
            <h3 class="font-display text-lg font-bold text-slate-100">Remove Opening Balance?</h3>
            <p class="text-sm text-slate-400 mt-1">The player's balance will be recalculated without it.</p>
          </div>
          <div class="flex gap-3">
            <button class="flex-1 py-3 rounded-xl text-sm font-semibold text-slate-300 border border-white/10 hover:border-white/25 hover:text-white transition"
              @click="confirmDelOb = null">Cancel</button>
            <button class="flex-1 py-3 rounded-xl text-sm font-bold text-white transition active:scale-[.97]"
              style="background:rgba(220,38,38,.85); border:1px solid rgba(244,63,94,.4)"
              @click="doDeleteOb">Yes, Remove</button>
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

    <!-- ══════════════════════════ DELETE NOTE CONFIRM ════════════════════ -->
    <Teleport to="body">
      <div v-if="confirmDelNoteId"
        class="fixed inset-0 z-50 flex items-center justify-center px-5"
        style="background:rgba(0,0,0,.75); backdrop-filter:blur(6px)"
        @click.self="confirmDelNoteId = null">
        <div class="w-full max-w-sm rounded-2xl p-6"
          style="background:#0d1a2e; border:1px solid rgba(244,63,94,.25); box-shadow:0 0 40px rgba(244,63,94,.12)">
          <div class="text-center mb-4">
            <div class="text-3xl mb-2">🗑️</div>
            <p class="font-semibold text-slate-100 mb-1">Delete this note?</p>
            <p class="text-xs text-slate-400">This will permanently remove the note.</p>
          </div>
          <div class="flex gap-3">
            <button class="flex-1 py-3 rounded-xl text-sm font-semibold text-slate-300 border border-white/10 hover:border-white/25 hover:text-white transition"
              @click="confirmDelNoteId = null">Cancel</button>
            <button class="flex-1 py-3 rounded-xl text-sm font-bold text-white transition active:scale-[.97]"
              style="background:rgba(220,38,38,.85); border:1px solid rgba(244,63,94,.4)"
              @click="deleteNote">Yes, Delete</button>
          </div>
        </div>
      </div>
    </Teleport>

  </template>
</template>
