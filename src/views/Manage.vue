<script setup>
import { ref, watch, onMounted, computed } from 'vue'
import { RouterLink } from 'vue-router'
import { supabase } from '../lib/supabase'
import { useClub } from '../composables/useClub'
import PageHeader from '../components/PageHeader.vue'
import Avatar from '../components/Avatar.vue'
import { usePlayerAvatars } from '../composables/usePlayerAvatars'
import { CURRENCIES } from '../utils/currency'
import { DAYS, HOURS, TIMEZONES, describeSchedule } from '../utils/schedule'
import { useGeo } from '../composables/useGeo'
import { COUNTRIES, countryName } from '../utils/countries'
import { subdivisionsFor, regionLabelFor } from '../utils/regions'

const { flagEmoji } = useGeo()

const { clubs, currentClub, loadClubs, isManager } = useClub()
const { avatarMap, loadAvatars } = usePlayerAvatars()


const cfg          = ref(null)
const members      = ref([])
const requests     = ref([])
const inviteEmail  = ref('')
const inviteLink   = ref('')
const note         = ref(null)
const cfgNote      = ref(null)
const inviteNote   = ref(null)
const memberError  = ref(null)
let   _memberErrTimer = null
const facNote      = ref(null)
const busy         = ref(false)

// Guest players (no account linked)
const guestPlayers     = ref([])
const guestInviteId    = ref(null)
const guestInviteEmail = ref('')
const guestInviteLink  = ref('')
const guestInviteNote  = ref(null)
const guestInviteBusy  = ref(false)

// Club currency
const clubCurrency = ref('AED')
const currencyBusy = ref(false)
const currencyNote = ref(null)

// Club country + public/closed visibility
const clubCountryCode = ref('AE')
const clubIsPublic    = ref(true)
const countryBusy     = ref(false)
const countryNote     = ref(null)

// Region picker adapts to the club's country (emirates for UAE, states for
// India, …); countries without a subdivision list fall back to free text.
const regionInfo  = computed(() => subdivisionsFor(clubCountryCode.value))
const regionLabel = computed(() => regionLabelFor(clubCountryCode.value))
// How players join: 'closed' (invite only) | 'open' (request+approve) | 'public' (auto-join via link)
const clubJoinPolicy  = ref('open')
const joinPolicyBusy   = ref(false)
const joinPolicyNote   = ref(null)

// Shareable club join link — admin distributes this so members request to
// join THIS specific club directly, without searching among every club.
const joinLinkCopied = ref(false)
const joinLink = computed(() =>
  currentClub.value ? `${window.location.origin}/join/${currentClub.value.club_id}` : '')

function copyJoinLink() {
  navigator.clipboard.writeText(joinLink.value)
  joinLinkCopied.value = true
  setTimeout(() => { joinLinkCopied.value = false }, 2000)
}
function shareJoinLinkWhatsApp() {
  const clubName = currentClub.value?.clubs?.name ?? 'our club'
  const msg = `🏸 Join ${clubName} on Badminton 360!\n\nTap this link to request to join — no searching needed:\n${joinLink.value}\n\nYour request goes straight to the club admin for approval.`
  window.open(`https://wa.me/?text=${encodeURIComponent(msg)}`, '_blank')
}

// Weekly digest schedule (per club)
const digest      = ref({ dow: 0, hour: 21, tz: 'Asia/Dubai', enabled: true })
const digestBusy  = ref(false)
const digestNote  = ref(null)
const digestSending = ref(false)
const digestSummary = computed(() =>
  describeSchedule(digest.value.dow, digest.value.hour, digest.value.tz))

// Existing facility info (club's own fields)
const facility = ref({ emirates: '', facility_name: '', facility_address: '', maps_url: '', description: '' })

// Facility Master
const linkedFacility = ref(null)
const facSearch      = ref('')
const facResults     = ref([])
const newFac         = ref({ name:'', address:'', emirate:'', maps_url:'', image_url:'', phone:'', website:'', description:'' })
const newFacNote     = ref(null)

const pendingRequests = computed(() => requests.value.filter(r => r.status === 'pending'))
const historyRequests = computed(() => requests.value.filter(r => r.status !== 'pending'))
const showRequestHistory = ref(false)

async function load() {
  if (!currentClub.value) return
  const cid = currentClub.value.club_id
  const [{ data: c }, { data: m }, { data: r }, { data: playerNames }, { data: guests }] = await Promise.all([
    supabase.from('ranking_config').select('*').eq('club_id', cid).single(),
    supabase.from('club_members').select('user_id, role').eq('club_id', cid),
    isManager()
      ? supabase.from('join_requests').select('*').eq('club_id', cid).order('created_at', { ascending: false }).limit(200)
      : { data: [] },
    // player display_names for this club (linked accounts only)
    supabase.from('players').select('user_id, display_name').eq('club_id', cid).not('user_id', 'is', null),
    supabase.from('players').select('id, display_name').eq('club_id', cid).is('user_id', null).eq('is_active', true),
  ])
  cfg.value      = c
  requests.value = r ?? []

  // Enrich members with names from user_profiles (nickname > full_name) then players fallback
  const memberIds = (m ?? []).map(x => x.user_id)
  const { data: profiles } = memberIds.length
    ? await supabase.rpc('get_member_profile_names', { p_club_id: cid })
    : { data: [] }

  const profileMap = Object.fromEntries((profiles ?? []).map(p => [p.user_id, p]))
  const playerMap  = Object.fromEntries((playerNames ?? []).map(p => [p.user_id, p]))

  members.value = (m ?? []).map(member => ({
    ...member,
    display:
      profileMap[member.user_id]?.nickname ||
      profileMap[member.user_id]?.full_name ||
      playerMap[member.user_id]?.display_name ||
      '—',
  }))
  guestPlayers.value = guests ?? []

  // Avatars for linked members
  await loadAvatars(memberIds)

  // Load current club facility info
  const { data: clubInfo } = await supabase.from('clubs')
    .select('emirates, facility_name, facility_address, maps_url, description, facility_id, currency, digest_dow, digest_hour, digest_tz, digest_enabled, country_code, is_public, join_policy')
    .eq('id', cid).single()
  if (clubInfo) {
    clubCurrency.value              = clubInfo.currency          ?? 'AED'
    clubCountryCode.value           = clubInfo.country_code      ?? 'AE'
    clubIsPublic.value              = clubInfo.is_public          ?? true
    clubJoinPolicy.value            = clubInfo.join_policy        ?? 'open'
    digest.value = {
      dow:     clubInfo.digest_dow     ?? 0,
      hour:    clubInfo.digest_hour    ?? 21,
      tz:      clubInfo.digest_tz      ?? 'Asia/Dubai',
      enabled: clubInfo.digest_enabled ?? true,
    }
    facility.value.emirates         = clubInfo.emirates         ?? ''
    facility.value.facility_name    = clubInfo.facility_name    ?? ''
    facility.value.facility_address = clubInfo.facility_address ?? ''
    facility.value.maps_url         = clubInfo.maps_url         ?? ''
    facility.value.description      = clubInfo.description      ?? ''
    // Load linked facility master
    if (clubInfo.facility_id) {
      const { data: fac } = await supabase.from('facilities')
        .select('id, name, address, emirate').eq('id', clubInfo.facility_id).single()
      linkedFacility.value = fac ?? null
    } else {
      linkedFacility.value = null
    }
  }
}

onMounted(() => { loadClubs(); load() })
watch(currentClub, load)

// ── Ranking config ──
async function saveCfg() {
  const { elo_weight, participation_weight } = cfg.value
  const sum = Number(elo_weight) + Number(participation_weight)
  if (Math.abs(sum - 1) > 0.01) {
    cfgNote.value = { ok: false, t: `Skill + Attendance must total 1.0 (currently ${sum.toFixed(2)}).` }
    return
  }
  busy.value = true; cfgNote.value = null
  const { error } = await supabase.from('ranking_config')
    .update({ elo_weight, participation_weight, k_factor: 24 })
    .eq('club_id', currentClub.value.club_id)
  busy.value = false
  cfgNote.value = error
    ? { ok: false, t: `Save failed: ${error.message}` }
    : { ok: true, t: '✅ Weights saved. Leaderboard updates immediately.' }
}

// ── Join request actions ──
async function approveRequest(id) {
  const { error } = await supabase.rpc('approve_join', { p_request_id: id })
  if (error) { note.value = { ok: false, t: error.message }; return }
  requests.value = requests.value.map(r => r.id === id ? { ...r, status: 'approved' } : r)
}

async function rejectRequest(id) {
  const { error } = await supabase.rpc('reject_join', { p_request_id: id })
  if (error) { note.value = { ok: false, t: error.message }; return }
  requests.value = requests.value.map(r => r.id === id ? { ...r, status: 'rejected' } : r)
}

const confirmDelReqId = ref(null)

async function deleteRequest() {
  const id = confirmDelReqId.value
  confirmDelReqId.value = null
  if (!id) return
  const { error } = await supabase.rpc('delete_join_request', { p_request_id: id })
  if (error) { note.value = { ok: false, t: error.message }; return }
  requests.value = requests.value.filter(r => r.id !== id)
}

// ── Email invite ──
async function generateInvite() {
  if (!inviteEmail.value.trim()) return
  busy.value = true; inviteNote.value = null; inviteLink.value = ''
  const { data, error } = await supabase.rpc('invite_member', {
    p_club_id: currentClub.value.club_id,
    p_email: inviteEmail.value.trim(),
  })
  busy.value = false
  if (error) {
    inviteNote.value = { ok: false, t: error.message }
  } else {
    inviteLink.value = `${window.location.origin}/join?token=${data}`
    inviteNote.value = { ok: true, t: 'Invite link generated! Share it with the player.' }
    // Fire-and-forget push to the invitee if they already have a B360 account
    supabase.functions.invoke('notify-invite', {
      body: { club_id: currentClub.value.club_id, email: inviteEmail.value.trim() }
    }).catch(() => {})
  }
}

function copyLink() {
  navigator.clipboard.writeText(inviteLink.value)
  inviteNote.value = { ok: true, t: '✅ Link copied to clipboard!' }
}

function mailtoLink() {
  const club = currentClub.value?.clubs?.name ?? 'our club'
  const subj = encodeURIComponent(`You're invited to join ${club} on Badminton 360`)
  const body = encodeURIComponent(
    `Hi!\n\nYou've been invited to join "${club}" on Badminton 360 — the smart ranking app for badminton teams.\n\nClick the link below to join:\n${inviteLink.value}\n\nThe link expires in 7 days.\n\nSee you on the court! 🏸`
  )
  return `mailto:${inviteEmail.value}?subject=${subj}&body=${body}`
}

// ── Guest player linking (existing roster entry ↔ a Gmail account) ──
// 1) If the email already has a B360 account → link instantly, no invite/approval.
// 2) Otherwise fall back to generating a 7-day invite link they can claim.
const guestLinkSuccess = ref(null)

async function sendGuestInvite() {
  if (!guestInviteEmail.value.trim() || !guestInviteId.value) return
  guestInviteBusy.value = true; guestInviteNote.value = null; guestInviteLink.value = ''
  const email    = guestInviteEmail.value.trim()
  const playerId = guestInviteId.value

  // Step 1: try direct link (registered users)
  const { data: linkRes, error: linkErr } = await supabase.rpc('link_guest_player', {
    p_club_id:   currentClub.value.club_id,
    p_player_id: playerId,
    p_email:     email,
  })
  if (linkErr) {
    guestInviteBusy.value = false
    guestInviteNote.value = { ok: false, t: linkErr.message }
    return
  }
  if (linkRes?.linked) {
    const player = guestPlayers.value.find(p => p.id === playerId)
    guestLinkSuccess.value =
      `✅ Linked! ${email} now owns "${player?.display_name ?? 'this player'}" — Elo history and all. No approval needed.`
    guestInviteBusy.value = false
    guestInviteId.value   = null
    await load()   // player moves from Guests to Members
    return
  }

  // Step 2: not registered yet → generate the classic invite link
  const { data, error } = await supabase.rpc('invite_guest_player', {
    p_club_id:   currentClub.value.club_id,
    p_player_id: playerId,
    p_email:     email,
  })
  guestInviteBusy.value = false
  if (error) {
    guestInviteNote.value = { ok: false, t: error.message }
  } else {
    guestInviteLink.value = `${window.location.origin}/join?token=${data}`
    guestInviteNote.value = { ok: true, t: `${email} hasn't signed up yet — share this link so they can sign in and claim their Elo history.` }
  }
}

function copyGuestLink() {
  navigator.clipboard.writeText(guestInviteLink.value)
  guestInviteNote.value = { ok: true, t: '✅ Link copied to clipboard!' }
}

function guestWhatsApp() {
  const player = guestPlayers.value.find(p => p.id === guestInviteId.value)
  const club   = currentClub.value?.clubs?.name ?? 'our club'
  const msg    = encodeURIComponent(
    `Hi ${player?.display_name ?? 'there'}!\n\nYou've been added to "${club}" on Badminton 360. Click the link below to sign in with Google and claim your account — your Elo ranking and match history will be waiting for you:\n${guestInviteLink.value}\n\nThe link expires in 7 days. See you on the court! 🏸`
  )
  window.open(`https://wa.me/?text=${msg}`, '_blank')
}

// ── Save facility info ──
async function saveFacility() {
  busy.value = true; facNote.value = null
  const { error } = await supabase.rpc('update_club_facility', {
    p_club_id:          currentClub.value.club_id,
    p_emirates:         facility.value.emirates         || null,
    p_facility_name:    facility.value.facility_name    || null,
    p_facility_address: facility.value.facility_address || null,
    p_maps_url:         facility.value.maps_url         || null,
    p_description:      facility.value.description      || null,
  })
  busy.value = false
  facNote.value = error
    ? { ok: false, t: error.message }
    : { ok: true, t: '✅ Facility info saved. Visible on the Explore page.' }
}

// ── Save club currency ──
async function saveCurrency() {
  currencyBusy.value = true; currencyNote.value = null
  const { error } = await supabase.rpc('set_club_currency', {
    p_club_id:  currentClub.value.club_id,
    p_currency: clubCurrency.value,
  })
  currencyBusy.value = false
  if (error) {
    currencyNote.value = { ok: false, t: error.message }
    return
  }
  // Reflect immediately in the switcher + Split Pay without a reload
  if (currentClub.value?.clubs) currentClub.value.clubs.currency = clubCurrency.value
  await loadClubs()
  currencyNote.value = { ok: true, t: '✅ Currency updated.' }
}

// ── Save club country ──
async function saveCountry() {
  countryBusy.value = true; countryNote.value = null
  const { error } = await supabase.rpc('set_club_country', {
    p_club_id:     currentClub.value.club_id,
    p_country_code: clubCountryCode.value,
  })
  countryBusy.value = false
  countryNote.value = error
    ? { ok: false, t: error.message }
    : { ok: true, t: '✅ Country updated.' }
}

// ── Set how players join (closed | open | public) ──
// Keep the Explore listing flag (is_public) sensibly in sync: a closed club
// is hidden from Explore; open/public clubs stay listed.
async function setJoinPolicy(policy) {
  if (policy === clubJoinPolicy.value) return
  joinPolicyBusy.value = true; joinPolicyNote.value = null
  const { error } = await supabase.rpc('set_club_join_policy', {
    p_club_id: currentClub.value.club_id,
    p_policy:  policy,
  })
  if (error) { joinPolicyBusy.value = false; joinPolicyNote.value = { ok: false, t: error.message }; return }
  clubJoinPolicy.value = policy

  const shouldList = policy !== 'closed'
  if (shouldList !== clubIsPublic.value) {
    const { error: visErr } = await supabase.rpc('set_club_visibility', {
      p_club_id: currentClub.value.club_id, p_is_public: shouldList,
    })
    if (!visErr) clubIsPublic.value = shouldList
  }
  joinPolicyBusy.value = false
  joinPolicyNote.value = { ok: true, t:
    policy === 'closed' ? '✅ Closed — new members can only join via a manual invite.'
    : policy === 'public' ? '✅ Public — anyone with the join link joins instantly, no approval.'
    : '✅ Open — people request to join and you approve them below.' }
}

// ── Weekly digest schedule ──
async function saveDigest() {
  digestBusy.value = true; digestNote.value = null
  const { error } = await supabase.rpc('set_club_digest_schedule', {
    p_club_id: currentClub.value.club_id,
    p_dow:     digest.value.dow,
    p_hour:    digest.value.hour,
    p_tz:      digest.value.tz,
    p_enabled: digest.value.enabled,
  })
  digestBusy.value = false
  digestNote.value = error
    ? { ok: false, t: error.message }
    : { ok: true, t: `✅ Saved. Digest sends ${digestSummary.value}.` }
}

async function sendDigestNow() {
  digestSending.value = true; digestNote.value = null
  const { error } = await supabase.rpc('trigger_club_digest', {
    p_club_id: currentClub.value.club_id,
  })
  digestSending.value = false
  digestNote.value = error
    ? { ok: false, t: error.message }
    : { ok: true, t: '📧 Sending now — the digest is on its way to opted-in members.' }
}

// ── Facility Master functions ──
async function searchFacilities() {
  if (!facSearch.value.trim()) { facResults.value = []; return }
  const { data } = await supabase.rpc('get_facilities', { p_search: facSearch.value.trim() })
  facResults.value = (data ?? []).slice(0, 5)
}

async function linkFacility(f) {
  busy.value = true
  await supabase.rpc('set_club_facility', {
    p_club_id: currentClub.value.club_id,
    p_facility_id: f.id
  })
  linkedFacility.value = f
  facResults.value = []; facSearch.value = ''
  busy.value = false
}

async function unlinkFacility() {
  busy.value = true
  await supabase.rpc('set_club_facility', {
    p_club_id: currentClub.value.club_id,
    p_facility_id: null
  })
  linkedFacility.value = null
  busy.value = false
}

async function createAndLinkFacility() {
  if (!newFac.value.name.trim()) return
  busy.value = true; newFacNote.value = null
  const { data: fId, error } = await supabase.rpc('create_facility', {
    p_name:        newFac.value.name.trim(),
    p_address:     newFac.value.address     || null,
    p_emirate:     newFac.value.emirate     || null,
    p_maps_url:    newFac.value.maps_url    || null,
    p_image_url:   newFac.value.image_url   || null,
    p_phone:       newFac.value.phone       || null,
    p_website:     newFac.value.website     || null,
    p_description: newFac.value.description || null,
  })
  if (error) { newFacNote.value = { ok: false, t: error.message }; busy.value = false; return }
  await supabase.rpc('set_club_facility', { p_club_id: currentClub.value.club_id, p_facility_id: fId })
  linkedFacility.value = { id: fId, name: newFac.value.name, address: newFac.value.address }
  newFac.value = { name:'', address:'', emirate:'', maps_url:'', image_url:'', phone:'', website:'', description:'' }
  newFacNote.value = { ok: true, t: '✅ Facility created and linked!' }
  busy.value = false
}

function showMemberError(msg, selectEl = null) {
  memberError.value = msg
  if (selectEl) selectEl.value = members.value.find(m => m.user_id === selectEl.dataset.uid)?.role ?? selectEl.value
  clearTimeout(_memberErrTimer)
  _memberErrTimer = setTimeout(() => { memberError.value = null }, 5000)
}

async function changeRole(userId, newRole, selectEl = null) {
  const member = members.value.find(m => m.user_id === userId)
  if (member?.role === 'owner' && newRole !== 'owner') {
    const ownerCount = members.value.filter(m => m.role === 'owner').length
    if (ownerCount <= 1) {
      if (selectEl) selectEl.value = 'owner'
      showMemberError('At least one Owner must remain. Promote another member to Owner first.', null)
      return
    }
  }
  const { error } = await supabase
    .from('club_members')
    .update({ role: newRole })
    .eq('club_id', currentClub.value.club_id)
    .eq('user_id', userId)
  if (error) {
    if (selectEl) selectEl.value = member?.role ?? newRole
    showMemberError('Role update failed: ' + error.message, null)
  } else {
    memberError.value = null
    members.value = members.value.map(m =>
      m.user_id === userId ? { ...m, role: newRole } : m
    )
  }
}

const roleLabel = r => ({ owner: '👑 Owner', manager: '🛠 Manager', player: '🏸 Player' }[r] ?? r)

// ── Leave club ──
const leaving   = ref(null)   // club_id in progress
const leaveNote = ref(null)

// ── Delete club ──
const deleteTarget      = ref(null)   // club object to delete
const deleteConfirmText = ref('')     // user must type club name
const deleteBusy        = ref(false)
const deleteNote        = ref(null)
const deleteMatchCount  = ref(0)

function openDeleteModal(c) {
  deleteTarget.value      = c
  deleteConfirmText.value = ''
  deleteNote.value        = null
  deleteMatchCount.value  = 0
}
function closeDeleteModal() {
  deleteTarget.value = null
}

async function confirmDeleteClub() {
  if (!deleteTarget.value) return
  deleteBusy.value = true; deleteNote.value = null
  const { error } = await supabase.rpc('delete_club', { p_club_id: deleteTarget.value.club_id })
  deleteBusy.value = false
  if (error) {
    const matchMatch = error.message.match(/MATCH_COUNT:(\d+)/)
    if (matchMatch) {
      deleteMatchCount.value = Number(matchMatch[1])
      deleteNote.value = { ok: false, t: `This club has ${deleteMatchCount.value} recorded match(es). Delete all of them from the Matches page first.` }
    } else {
      deleteNote.value = { ok: false, t: error.message }
    }
  } else {
    closeDeleteModal()
    await loadClubs()
    leaveNote.value = { ok: true, t: 'Club deleted successfully.' }
  }
}

async function leaveClub(clubId) {
  const name = clubs.value.find(c => c.club_id === clubId)?.clubs?.name ?? 'this club'
  if (!confirm(`Leave "${name}"?\n\nYou can rejoin later by submitting a new request.`)) return
  leaving.value = clubId; leaveNote.value = null
  const { error } = await supabase.rpc('leave_club', { p_club_id: clubId })
  leaving.value = null
  if (error) {
    if (error.message.includes('match history')) {
      leaveNote.value = {
        ok: false,
        t: `You already have matches recorded in "${name}". You cannot leave directly — ask the club manager to mark you as Inactive from the Players page.`,
      }
    } else if (error.message.includes('owner')) {
      leaveNote.value = {
        ok: false,
        t: `You are the owner of "${name}". Transfer ownership to another member first (Manage → Members).`,
      }
    } else {
      leaveNote.value = { ok: false, t: error.message }
    }
  } else {
    leaveNote.value = { ok: true, t: `You have left "${name}".` }
    await loadClubs()
  }
}
</script>

<template>
  <PageHeader icon="⚙️" title="Manage" subtitle="Clubs, members, and ranking settings">
    <template #help>
      <div class="text-xs space-y-1.5">
        <p><strong class="text-slate-800">Create a Club</strong> — Each club has its own roster, matches, and leaderboard. You become the owner.</p>
        <p><strong class="text-slate-800">Roles:</strong> 👑 Owner has full control. 🛠 Manager records matches. 🏸 Player views dashboards.</p>
        <p><strong class="text-slate-800">Join Requests</strong> — Players who request to join appear here. Approve to add them.</p>
        <p><strong class="text-slate-800">Invite by Email</strong> — Generate a 7-day invite link and send it to anyone.</p>
        <p><strong class="text-slate-800">Ranking Weights</strong> — Tune skill vs attendance. Must add to 1.0. K-factor controls Elo swing per match.</p>
      </div>
    </template>
  </PageHeader>

  <!-- ── Pending Join Requests ── -->
  <div v-if="currentClub && isManager() && requests.length" class="card-violet p-4 mb-4 fade-up">
    <div class="flex items-center justify-between mb-3">
      <div class="label mb-0">Join Requests — {{ currentClub.clubs?.name }}</div>
      <span v-if="pendingRequests.length" class="badge-dot">{{ pendingRequests.length }}</span>
    </div>

    <!-- Pending (actionable) requests -->
    <div v-if="pendingRequests.length" class="space-y-2">
      <div v-for="r in pendingRequests" :key="r.id"
        class="flex items-center gap-3 py-2.5 px-3 rounded-xl bg-[rgba(15,23,42,0.03)] border border-[rgba(15,23,42,0.06)]">
        <div class="w-8 h-8 rounded-full flex items-center justify-center text-sm font-bold shrink-0"
          style="background: linear-gradient(135deg, rgba(168,85,247,.3), rgba(0,229,255,.2));">
          {{ (r.user_name || '?').charAt(0).toUpperCase() }}
        </div>
        <div class="flex-1 min-w-0">
          <div class="text-sm font-semibold text-slate-100 truncate">{{ r.user_name }}</div>
          <div class="text-[10px] text-slate-500 truncate">{{ r.user_email }}</div>
        </div>
        <div class="shrink-0 flex items-center gap-1.5">
          <button class="btn-success text-xs px-2.5 py-1" @click="approveRequest(r.id)">Approve</button>
          <button class="btn-danger text-xs px-2.5 py-1" @click="rejectRequest(r.id)">Decline</button>
        </div>
      </div>
    </div>

    <!-- No pending: minimized -->
    <p v-else class="text-xs text-slate-500">✓ No pending requests to approve.</p>

    <!-- Past requests (approved/rejected) — collapsed by default -->
    <div v-if="historyRequests.length" class="mt-2">
      <button class="text-[11px] text-slate-500 hover:text-neon transition"
        @click="showRequestHistory = !showRequestHistory">
        {{ showRequestHistory ? '▾ Hide' : '▸ Show' }} past requests ({{ historyRequests.length }})
      </button>
      <div v-if="showRequestHistory" class="space-y-2 mt-2 fade-up">
        <div v-for="r in historyRequests" :key="r.id"
          class="flex items-center gap-3 py-2.5 px-3 rounded-xl bg-[rgba(15,23,42,0.03)] border border-[rgba(15,23,42,0.06)]">
          <div class="w-8 h-8 rounded-full flex items-center justify-center text-sm font-bold shrink-0"
            style="background: linear-gradient(135deg, rgba(168,85,247,.3), rgba(0,229,255,.2));">
            {{ (r.user_name || '?').charAt(0).toUpperCase() }}
          </div>
          <div class="flex-1 min-w-0">
            <div class="text-sm font-semibold text-slate-100 truncate">{{ r.user_name }}</div>
            <div class="text-[10px] text-slate-500 truncate">{{ r.user_email }}</div>
          </div>
          <div class="shrink-0 flex items-center gap-1.5">
            <span :class="r.status === 'approved' ? 'badge-approved' : 'badge-rejected'">{{ r.status }}</span>
            <button v-if="r.status === 'rejected'"
              class="w-6 h-6 flex items-center justify-center rounded-lg text-slate-400 hover:text-rose-400 hover:bg-rose-500/10 transition-all"
              title="Delete request"
              @click="confirmDelReqId = r.id">🗑</button>
          </div>
        </div>
      </div>
    </div>
  </div>

  <!-- ── Invite by Email ── -->
  <div v-if="currentClub && isManager()" class="card p-4 mb-4 fade-up">
    <div class="label">Invite by Email — {{ currentClub.clubs?.name }}</div>
    <p class="text-[11px] text-slate-500 mb-3">
      Generate a personal invite link and share it via email, WhatsApp, or any channel.
      Links expire in 7 days.
    </p>

    <div class="flex gap-2 mb-3">
      <input v-model="inviteEmail" class="input" type="email"
        placeholder="player@email.com" @keyup.enter="generateInvite" />
      <button class="btn-violet shrink-0 px-4" :disabled="busy || !inviteEmail.trim()"
        @click="generateInvite">
        Generate
      </button>
    </div>

    <!-- Generated link -->
    <div v-if="inviteLink" class="rounded-xl bg-[rgba(15,23,42,0.04)] border border-[rgba(15,23,42,0.08)] p-3 mb-3 fade-up">
      <div class="label mb-1">Invite Link</div>
      <div class="text-xs text-slate-300 break-all font-mono mb-2.5 select-all">{{ inviteLink }}</div>
      <div class="flex gap-2">
        <button class="btn-primary flex-1 py-2 text-xs" @click="copyLink">
          📋 Copy Link
        </button>
        <a :href="mailtoLink()" class="btn-ghost flex-1 py-2 text-xs text-center">
          ✉️ Open in Email
        </a>
      </div>
    </div>

    <p v-if="inviteNote" class="text-xs rounded-xl px-3 py-2"
      :class="inviteNote.ok ? 'bg-emerald-500/15 text-emerald-300' : 'bg-rose-500/15 text-rose-300'">
      {{ inviteNote.t }}
    </p>
  </div>

  <!-- ── Ranking weights ── -->
  <div v-if="currentClub && isManager() && cfg" class="card p-4 mb-4 fade-up">
    <div class="label">Ranking Weights — {{ currentClub.clubs?.name }}</div>
    <div class="grid grid-cols-3 gap-3 mb-3">
      <div>
        <label class="label">Skill (Elo)</label>
        <input v-model.number="cfg.elo_weight" type="number" step="0.05" min="0" max="1" class="input text-center" />
        <div class="text-[10px] text-slate-500 mt-1">Skill weight</div>
      </div>
      <div>
        <label class="label">Attendance</label>
        <input v-model.number="cfg.participation_weight" type="number" step="0.05" min="0" max="1" class="input text-center" />
        <div class="text-[10px] text-slate-500 mt-1">Regularity weight</div>
      </div>
      <div>
        <label class="label">K-factor</label>
        <div class="input text-center text-slate-500 bg-[rgba(15,23,42,0.02)] cursor-not-allowed select-none">24</div>
        <div class="text-[10px] text-slate-600 mt-1">Fixed · not editable</div>
      </div>
    </div>

    <div class="rounded-xl px-3 py-2 text-xs text-slate-400 mb-3"
      style="background:rgba(255,255,255,.03); border:1px solid rgba(255,255,255,.06)">
      Split: Skill
      <strong class="text-neon">{{ Math.round(cfg.elo_weight * 100) }}%</strong>
      + Attendance
      <strong class="text-violet">{{ Math.round(cfg.participation_weight * 100) }}%</strong>
      = {{ Math.round((cfg.elo_weight + cfg.participation_weight) * 100) }}%
      <span v-if="Math.abs(cfg.elo_weight + cfg.participation_weight - 1) > 0.01"
        class="text-amber-400"> ⚠️ must equal 100%</span>
      <span v-else class="text-neon"> ✓</span>
    </div>

    <p v-if="cfgNote" class="text-xs rounded-xl px-3 py-2 mb-3"
      :class="cfgNote.ok ? 'bg-emerald-500/15 text-emerald-300' : 'bg-rose-500/15 text-rose-300'">
      {{ cfgNote.t }}
    </p>
    <button class="btn-ghost w-full" :disabled="busy" @click="saveCfg">Save Ranking Weights</button>
  </div>

  <!-- ── Members ── -->
  <div v-if="currentClub && (members.length || guestPlayers.length)" class="card p-4 mb-4 fade-up">
    <div class="label">Members — {{ currentClub.clubs?.name }}</div>

    <div v-if="memberError"
      class="flex items-center gap-2 mb-3 px-3 py-2 rounded-xl text-xs font-medium text-rose-300"
      style="background:rgba(239,68,68,.12); border:1px solid rgba(239,68,68,.25)">
      <span>⚠️</span>
      <span>{{ memberError }}</span>
    </div>

    <div v-for="m in members" :key="m.user_id"
      class="flex items-center justify-between py-2.5 border-b border-[rgba(15,23,42,0.05)] last:border-0 gap-2">
      <div class="flex items-center gap-2 flex-1 min-w-0">
        <Avatar :name="m.display" :src="avatarMap[m.user_id]" :size="32" />
        <div class="text-sm font-semibold text-slate-100 truncate">{{ m.display }}</div>
      </div>
      <select
        v-if="currentClub.role === 'owner' || (currentClub.role === 'manager' && m.role !== 'owner')"
        :value="m.role"
        class="text-xs rounded-lg border border-[rgba(15,23,42,0.10)] bg-[rgba(15,23,42,0.05)] px-2 py-1 outline-none cursor-pointer"
        @change="changeRole(m.user_id, $event.target.value, $event.target)">
        <option value="player">🏸 Player</option>
        <option value="manager">🛠 Manager</option>
        <option v-if="currentClub.role === 'owner'" value="owner">👑 Owner</option>
      </select>
      <span v-else class="text-xs shrink-0">{{ roleLabel(m.role) }}</span>
    </div>

    <!-- Guest link success (shown even after the row moves to Members) -->
    <div v-if="guestLinkSuccess"
      class="mt-2 text-xs px-3 py-2 rounded-lg text-emerald-600 bg-emerald-50 border border-emerald-200 flex items-start gap-2 fade-up">
      <span class="flex-1">{{ guestLinkSuccess }}</span>
      <button class="text-emerald-400 hover:text-emerald-600 shrink-0" @click="guestLinkSuccess = null">✕</button>
    </div>

    <!-- Guest players (added manually, no Google account linked yet) -->
    <div v-if="guestPlayers.length" class="mt-1 pt-3 border-t border-[rgba(15,23,42,0.06)]">
      <div class="text-[10px] uppercase tracking-widest text-slate-600 mb-2">Guest players — no account linked</div>

      <div v-for="gp in guestPlayers" :key="gp.id" class="mb-1">
        <div class="flex items-center justify-between py-2 gap-2">
          <div class="flex items-center gap-2 flex-1 min-w-0">
            <Avatar :name="gp.display_name" :src="''" :size="32" />
            <div class="text-sm text-slate-300 truncate">{{ gp.display_name }}</div>
          </div>
          <button
            class="text-xs px-3 py-1.5 rounded-lg font-medium transition"
            style="border:1px solid rgba(0,229,255,0.3); color:#00e5ff"
            @click="guestInviteId = gp.id; guestInviteEmail = ''; guestInviteLink = ''; guestInviteNote = null">
            Link Account
          </button>
        </div>

        <!-- Inline invite form for this player -->
        <div v-if="guestInviteId === gp.id"
          class="mb-3 p-3 rounded-xl fade-up"
          style="background:rgba(0,229,255,0.04); border:1px solid rgba(0,229,255,0.12)">
          <p class="text-[11px] text-slate-400 mb-2">
            Enter their Gmail — if they've already signed up, they're linked instantly.
            Otherwise you'll get an invite link to share.
          </p>
          <div class="flex gap-2 mb-2">
            <input v-model="guestInviteEmail" type="email" placeholder="their@gmail.com"
              class="input flex-1 text-sm"
              @keyup.enter="sendGuestInvite" />
            <button class="btn-primary px-3 text-sm shrink-0"
              :disabled="guestInviteBusy || !guestInviteEmail.trim()"
              @click="sendGuestInvite">
              {{ guestInviteBusy ? '…' : 'Link' }}
            </button>
          </div>
          <div v-if="guestInviteNote" class="text-xs mb-2 px-2 py-1 rounded-lg"
            :class="guestInviteNote.ok ? 'text-emerald-400' : 'text-rose-400'">
            {{ guestInviteNote.t }}
          </div>
          <div v-if="guestInviteLink" class="fade-up">
            <div class="text-xs text-slate-400 break-all font-mono mb-2 bg-[rgba(15,23,42,0.04)] rounded-lg p-2 select-all">
              {{ guestInviteLink }}
            </div>
            <div class="flex gap-2">
              <button class="flex-1 btn-ghost text-xs py-2" @click="copyGuestLink">📋 Copy</button>
              <button class="flex-1 text-xs py-2 rounded-xl font-semibold transition"
                style="background:rgba(37,211,102,0.15); border:1px solid rgba(37,211,102,0.3); color:#25d366"
                @click="guestWhatsApp">WhatsApp</button>
              <button class="text-slate-500 hover:text-slate-300 text-xs px-2 transition"
                @click="guestInviteId = null">✕</button>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>

  <!-- ── Club Currency ── -->
  <div v-if="currentClub && isManager()" class="card p-4 mb-4 fade-up">
    <div class="label">Currency — {{ currentClub.clubs?.name }}</div>
    <p class="text-[11px] text-slate-500 mb-3">
      Used for Split Pay and tournament fees across this club.
    </p>
    <div class="flex gap-2">
      <select v-model="clubCurrency" class="input flex-1">
        <option v-for="c in CURRENCIES" :key="c.code" :value="c.code">{{ c.label }}</option>
      </select>
      <button class="btn-primary px-4 shrink-0" :disabled="currencyBusy" @click="saveCurrency">
        {{ currencyBusy ? '…' : 'Save' }}
      </button>
    </div>
    <p v-if="currencyNote" class="mt-2 text-xs" :class="currencyNote.ok ? 'text-emerald-500' : 'text-rose-400'">
      {{ currencyNote.t }}
    </p>
  </div>

  <!-- ── Club Join Link ── -->
  <div v-if="currentClub && isManager()" class="card p-4 mb-4 fade-up">
    <div class="label">Club Join Link — {{ currentClub.clubs?.name }}</div>
    <p class="text-[11px] text-slate-500 mb-3">
      Share this in your WhatsApp group. Anyone who taps it goes straight to
      <strong>this club</strong> — no searching among other clubs.
      <template v-if="clubJoinPolicy === 'public'"> They <strong>join instantly</strong> after signing in — no approval needed.</template>
      <template v-else-if="clubJoinPolicy === 'closed'"> Note: this club is <strong>Closed</strong>, so the link won't let anyone join until you switch to Open or Public below.</template>
      <template v-else> Their request still needs your <strong>approval</strong> below.</template>
    </p>
    <div class="text-xs text-slate-400 break-all font-mono mb-3 bg-[rgba(15,23,42,0.04)] rounded-lg p-2 select-all">
      {{ joinLink }}
    </div>
    <div class="flex gap-2">
      <button class="flex-1 btn-ghost text-xs py-2" @click="copyJoinLink">
        {{ joinLinkCopied ? '✅ Copied!' : '📋 Copy Link' }}
      </button>
      <button class="flex-1 text-xs py-2 rounded-xl font-semibold transition"
        style="background:rgba(37,211,102,0.15); border:1px solid rgba(37,211,102,0.3); color:#25d366"
        @click="shareJoinLinkWhatsApp">
        💬 Share on WhatsApp
      </button>
    </div>
  </div>

  <!-- ── How players join & Country ── -->
  <div v-if="currentClub && isManager()" class="card p-4 mb-4 fade-up">
    <div class="label">How Players Join — {{ currentClub.clubs?.name }}</div>

    <p class="text-[11px] text-slate-500 mb-3">
      Choose how new players get into this club.
    </p>

    <div class="space-y-2">
      <button v-for="opt in [
          { key: 'open',   icon: '🙋', title: 'Open — request & approve', desc: 'Listed in Explore. People request to join; you approve them below.' },
          { key: 'public', icon: '🔗', title: 'Public link — instant join', desc: 'Anyone with your join link joins instantly after signing in. No approval.' },
          { key: 'closed', icon: '🔒', title: 'Closed — invite only', desc: 'Hidden from Explore. Only people you invite manually can join.' },
        ]" :key="opt.key"
        class="w-full text-left rounded-xl p-3 border transition flex items-start gap-3"
        :class="clubJoinPolicy === opt.key
          ? 'border-cyan-400 bg-cyan-50'
          : 'border-[rgba(15,23,42,0.12)] hover:border-[rgba(15,23,42,0.25)]'"
        :disabled="joinPolicyBusy" @click="setJoinPolicy(opt.key)">
        <span class="text-xl leading-none mt-0.5">{{ opt.icon }}</span>
        <span class="min-w-0">
          <span class="block text-sm font-semibold text-slate-800">{{ opt.title }}</span>
          <span class="block text-[11px] text-slate-500 mt-0.5">{{ opt.desc }}</span>
        </span>
        <span v-if="clubJoinPolicy === opt.key" class="ml-auto text-cyan-500 text-lg shrink-0">✓</span>
      </button>
    </div>
    <p v-if="joinPolicyNote" class="mt-2 mb-1 text-xs" :class="joinPolicyNote.ok ? 'text-emerald-500' : 'text-rose-400'">
      {{ joinPolicyNote.t }}
    </p>

    <div class="border-t border-[rgba(15,23,42,0.06)] pt-3 mt-3">
      <label class="label">Country</label>
      <div class="flex gap-2">
        <select v-model="clubCountryCode" class="input flex-1">
          <option v-for="code in COUNTRIES" :key="code" :value="code">
            {{ flagEmoji(code) }} {{ countryName(code) }}
          </option>
        </select>
        <button class="btn-primary px-4 shrink-0" :disabled="countryBusy" @click="saveCountry">
          {{ countryBusy ? '…' : 'Save' }}
        </button>
      </div>
      <p class="text-[11px] text-slate-500 mt-2">
        Used for the country filter on Explore &amp; Join pages.
      </p>
      <p v-if="countryNote" class="mt-2 text-xs" :class="countryNote.ok ? 'text-emerald-500' : 'text-rose-400'">
        {{ countryNote.t }}
      </p>
    </div>
  </div>

  <!-- ── Weekly Ranking Digest ── -->
  <div v-if="currentClub && isManager()" class="card p-4 mb-4 fade-up">
    <div class="label">Weekly Ranking Digest — {{ currentClub.clubs?.name }}</div>
    <p class="text-[11px] text-slate-500 mb-3">
      An email with the week's champion and standings, sent to members who opted in.
    </p>

    <label class="flex items-center gap-2 mb-3 cursor-pointer select-none">
      <input type="checkbox" v-model="digest.enabled" class="w-4 h-4 rounded accent-cyan-500" />
      <span class="text-sm text-slate-600">Send this club's weekly digest</span>
    </label>

    <div v-if="digest.enabled" class="grid grid-cols-2 gap-2 mb-2">
      <div>
        <label class="label">Day</label>
        <select v-model.number="digest.dow" class="input">
          <option v-for="d in DAYS" :key="d.value" :value="d.value">{{ d.label }}</option>
        </select>
      </div>
      <div>
        <label class="label">Time</label>
        <select v-model.number="digest.hour" class="input">
          <option v-for="h in HOURS" :key="h.value" :value="h.value">{{ h.label }}</option>
        </select>
      </div>
      <div class="col-span-2">
        <label class="label">Timezone</label>
        <select v-model="digest.tz" class="input">
          <option v-for="z in TIMEZONES" :key="z.value" :value="z.value">{{ z.label }}</option>
        </select>
      </div>
    </div>

    <p v-if="digest.enabled" class="text-[11px] text-slate-500 mb-3">Sends <strong>{{ digestSummary }}</strong>.</p>

    <div class="flex gap-2">
      <button class="btn-primary flex-1 py-2.5 text-sm" :disabled="digestBusy" @click="saveDigest">
        {{ digestBusy ? '…' : 'Save Schedule' }}
      </button>
      <button class="btn-ghost px-4 text-sm shrink-0" :disabled="digestSending" @click="sendDigestNow">
        {{ digestSending ? '…' : '📧 Send test now' }}
      </button>
    </div>
    <p v-if="digestNote" class="mt-2 text-xs" :class="digestNote.ok ? 'text-emerald-500' : 'text-rose-400'">
      {{ digestNote.t }}
    </p>
  </div>

  <!-- ── Facility / Location info ── -->
  <div v-if="currentClub && isManager()" class="card p-4 mb-4 fade-up">
    <div class="label">Club Location &amp; Facility — {{ currentClub.clubs?.name }}</div>
    <p class="text-[11px] text-slate-500 mb-3">
      Optional · Shown on the Explore page so new players can find your court.
    </p>
    <div class="space-y-3">
      <div>
        <label class="label">{{ regionLabel }}</label>
        <select v-if="regionInfo" v-model="facility.emirates" class="input">
          <option value="">— Select {{ regionInfo.label }} —</option>
          <option v-for="e in regionInfo.options" :key="e" :value="e">{{ e }}</option>
        </select>
        <input v-else v-model="facility.emirates" class="input" maxlength="60"
          :placeholder="`e.g. your ${regionLabel.toLowerCase()}`" />
        <p class="text-[10px] text-slate-400 mt-1">Based on the club's country (set above).</p>
      </div>
      <div>
        <label class="label">Facility / Academy Name</label>
        <input v-model="facility.facility_name" class="input"
          placeholder="e.g. Dubai Sports City, GEMS School Courts" maxlength="80" />
      </div>
      <div>
        <label class="label">Address</label>
        <input v-model="facility.facility_address" class="input"
          placeholder="e.g. Al Barsha, Dubai" maxlength="120" />
      </div>
      <div>
        <label class="label">Google Maps Link <span class="text-slate-600">(optional)</span></label>
        <input v-model="facility.maps_url" class="input" type="url"
          placeholder="https://maps.app.goo.gl/…" />
      </div>
      <div>
        <label class="label">Description <span class="text-slate-600">(optional)</span></label>
        <textarea v-model="facility.description" class="input resize-none" rows="2"
          placeholder="Who can join, what time you play…" maxlength="200" />
      </div>
    </div>
    <p v-if="facNote" class="mt-3 text-xs rounded-xl px-3 py-2"
      :class="facNote.ok ? 'bg-emerald-500/15 text-emerald-300' : 'bg-rose-500/15 text-rose-300'">
      {{ facNote.t }}
    </p>
    <button class="btn-ghost w-full mt-3" :disabled="busy" @click="saveFacility">
      Save Facility Info
    </button>
  </div>

  <!-- ── Facility Master: Create or link ── -->
  <div v-if="currentClub && isManager()" class="card p-4 mb-4 fade-up">
    <div class="label">🏟️ Facility Master — {{ currentClub.clubs?.name }}</div>
    <p class="text-[11px] text-slate-500 mb-3">
      Create a facility profile that any club can link to. Once linked, matches automatically
      show as bookings on the facility's public page.
    </p>

    <!-- Linked facility status -->
    <div v-if="linkedFacility" class="flex items-center justify-between mb-3 p-3 rounded-xl"
      style="background:rgba(0,229,255,.07); border:1px solid rgba(0,229,255,.2)">
      <div>
        <div class="text-sm font-semibold text-neon">{{ linkedFacility.name }}</div>
        <div class="text-[10px] text-slate-500">{{ linkedFacility.address }}</div>
      </div>
      <div class="flex gap-2">
        <RouterLink :to="'/facility/' + linkedFacility.id"
          class="text-xs text-neon hover:opacity-75 transition">View →</RouterLink>
        <button class="text-xs text-slate-500 hover:text-rose-400 transition"
          @click="unlinkFacility">Unlink</button>
      </div>
    </div>

    <!-- Search + link existing facility -->
    <div class="mb-3">
      <label class="label">Search &amp; Link Existing Facility</label>
      <div class="flex gap-2">
        <input v-model="facSearch" class="input text-sm" placeholder="Type facility name…"
          @input="searchFacilities" />
        <button class="btn-ghost shrink-0 px-3 text-sm" @click="searchFacilities">Search</button>
      </div>
      <div v-if="facResults.length" class="mt-2 space-y-1">
        <button v-for="f in facResults" :key="f.id"
          class="w-full text-left text-sm px-3 py-2 rounded-xl border border-[rgba(15,23,42,0.10)] hover:border-cyan-500/30 hover:bg-[rgba(15,23,42,0.03)] transition"
          @click="linkFacility(f)">
          <span class="font-medium text-slate-200">{{ f.name }}</span>
          <span v-if="f.address" class="text-slate-500 ml-2 text-xs">{{ f.address }}</span>
        </button>
      </div>
    </div>

    <!-- Create new facility -->
    <details class="group">
      <summary class="text-xs text-neon cursor-pointer hover:opacity-75 transition list-none flex items-center gap-1">
        <span class="group-open:rotate-90 transition-transform inline-block">▶</span>
        Create a New Facility Profile
      </summary>
      <div class="mt-3 space-y-2">
        <input v-model="newFac.name" class="input text-sm" placeholder="Facility name *" />
        <input v-model="newFac.address" class="input text-sm" placeholder="Address" />
        <select v-if="regionInfo" v-model="newFac.emirate" class="input text-sm">
          <option value="">— {{ regionInfo.label }} —</option>
          <option v-for="e in regionInfo.options" :key="e" :value="e">{{ e }}</option>
        </select>
        <input v-else v-model="newFac.emirate" class="input text-sm" maxlength="60"
          :placeholder="regionLabel" />
        <input v-model="newFac.maps_url" class="input text-sm" placeholder="Google Maps URL" />
        <input v-model="newFac.image_url" class="input text-sm" placeholder="Facility photo URL (paste image link)" />
        <input v-model="newFac.phone" class="input text-sm" placeholder="Phone" />
        <input v-model="newFac.website" class="input text-sm" placeholder="Website" />
        <textarea v-model="newFac.description" class="input resize-none text-sm" rows="2"
          placeholder="Description (courts available, parking, etc.)" />
        <p v-if="newFacNote" class="text-xs"
          :class="newFacNote.ok ? 'text-emerald-400' : 'text-rose-400'">{{ newFacNote.t }}</p>
        <button class="btn-violet w-full text-sm" :disabled="busy || !newFac.name.trim()"
          @click="createAndLinkFacility">
          🏟️ Create &amp; Link to This Club
        </button>
      </div>
    </details>
  </div>

  <!-- ── Browse / Join more clubs ── -->
  <RouterLink to="/join"
    class="card mb-4 p-4 flex items-center justify-between text-sm text-slate-400
           hover:border-[rgba(15,23,42,0.15)] transition-all duration-200 fade-up">
    <div class="flex items-center gap-3">
      <span class="text-2xl">🏟️</span>
      <div>
        <div class="font-semibold text-slate-200">Browse &amp; Join Other Clubs</div>
        <div class="text-[11px] text-slate-500">Find teams and request to join</div>
      </div>
    </div>
    <span class="text-slate-600 text-lg">→</span>
  </RouterLink>

  <!-- ── Club list with Leave option ── -->
  <div v-if="clubs.length" class="card p-4 fade-up">
    <div class="label mb-1">Your Clubs</div>
    <p class="text-[11px] text-slate-500 mb-3">
      You can leave a club if you have no recorded matches. If you have matches,
      ask the manager to mark you as Inactive instead.
    </p>

    <!-- Leave result message -->
    <div v-if="leaveNote" class="rounded-xl px-3 py-2.5 mb-3 text-xs"
      :class="leaveNote.ok ? 'bg-emerald-500/15 text-emerald-300' : 'bg-rose-500/15 text-rose-400'">
      {{ leaveNote.t }}
    </div>

    <div v-for="c in clubs" :key="c.club_id"
      class="flex items-center gap-2 py-2.5 border-b border-[rgba(15,23,42,0.05)] last:border-0">

      <!-- Club info -->
      <div class="flex-1 min-w-0">
        <div class="text-sm font-semibold text-slate-100 truncate">{{ c.clubs?.name }}</div>
        <div class="text-[10px] capitalize"
          :class="c.role === 'owner' ? 'text-amber-500' : 'text-slate-500'">
          {{ roleLabel(c.role) }}
        </div>
      </div>

      <!-- Active badge -->
      <span v-if="currentClub?.club_id === c.club_id"
        class="badge-member shrink-0">Active</span>

      <!-- Leave button — hidden for owners -->
      <button v-if="c.role !== 'owner'"
        class="shrink-0 text-[11px] px-2.5 py-1 rounded-lg border transition-all duration-150"
        :class="leaving === c.club_id
          ? 'border-[rgba(15,23,42,0.10)] text-slate-600 cursor-wait'
          : 'border-rose-500/25 text-rose-500/70 hover:border-rose-400/50 hover:text-rose-400'"
        :disabled="!!leaving"
        @click="leaveClub(c.club_id)">
        {{ leaving === c.club_id ? '…' : 'Leave' }}
      </button>

      <!-- Owner: Delete button -->
      <button v-else
        class="shrink-0 text-[11px] px-2.5 py-1 rounded-lg border transition-all duration-150
               border-rose-500/30 text-rose-500/60 hover:border-rose-400/60 hover:text-rose-400"
        @click="openDeleteModal(c)">
        🗑 Delete
      </button>
    </div>
  </div>

  <!-- ── Delete Club Modal ── -->
  <Teleport to="body">
    <div v-if="deleteTarget"
      class="fixed inset-0 z-50 flex items-end sm:items-center justify-center"
      style="background:rgba(0,0,0,.7); backdrop-filter:blur(4px)"
      @click.self="closeDeleteModal">

      <div class="w-full max-w-md rounded-t-3xl sm:rounded-3xl overflow-hidden"
        style="background:#0d1829; border:1px solid rgba(239,68,68,.25)">

        <!-- Header -->
        <div class="px-5 pt-5 pb-4 border-b border-white/[0.06]">
          <div class="flex items-center gap-3 mb-1">
            <div class="w-10 h-10 rounded-2xl flex items-center justify-center text-xl shrink-0"
              style="background:rgba(239,68,68,.12); border:1px solid rgba(239,68,68,.25)">
              🗑
            </div>
            <div>
              <h3 class="font-display font-bold text-slate-100">Delete Club</h3>
              <p class="text-[11px] text-rose-400">This action is permanent and cannot be undone</p>
            </div>
            <button class="ml-auto text-slate-500 hover:text-slate-300 text-xl transition"
              @click="closeDeleteModal">✕</button>
          </div>
        </div>

        <div class="px-5 py-4 space-y-4">

          <!-- Club name -->
          <div class="rounded-xl px-4 py-3"
            style="background:rgba(239,68,68,.07); border:1px solid rgba(239,68,68,.2)">
            <p class="text-xs text-slate-400 mb-0.5">Club to delete</p>
            <p class="font-bold text-rose-300 text-base">{{ deleteTarget.clubs?.name }}</p>
          </div>

          <!-- What gets deleted -->
          <div class="space-y-1.5 text-xs text-slate-400">
            <p class="font-semibold text-slate-300 mb-1">The following will be permanently deleted:</p>
            <p>• All players and their Elo history</p>
            <p>• All Split Pay expenses, wallet, and balances</p>
            <p>• All schedules, polls, and attendees</p>
            <p>• All join requests and invites</p>
            <p>• All facility bookings for this club</p>
          </div>

          <!-- Error / match blocker -->
          <div v-if="deleteNote" class="rounded-xl px-4 py-3 text-xs"
            :class="deleteNote.ok ? 'bg-emerald-500/15 text-emerald-300' : 'bg-rose-500/15 text-rose-300'">
            <p class="font-semibold mb-1">{{ deleteNote.ok ? '✅ Done' : '⚠️ Cannot delete yet' }}</p>
            <p>{{ deleteNote.t }}</p>
            <RouterLink v-if="deleteMatchCount > 0" to="/matches"
              class="mt-2 inline-block underline text-rose-400 hover:text-rose-300"
              @click="closeDeleteModal">
              Go to Matches →
            </RouterLink>
          </div>

          <!-- Confirm by typing name (only shown when no match blocker) -->
          <div v-if="!deleteMatchCount">
            <label class="label text-slate-400">
              Type <strong class="text-slate-200">{{ deleteTarget.clubs?.name }}</strong> to confirm
            </label>
            <input v-model="deleteConfirmText" class="input"
              :placeholder="deleteTarget.clubs?.name" />
          </div>

          <!-- Buttons -->
          <div class="flex gap-3 pt-1">
            <button class="btn-ghost flex-1" @click="closeDeleteModal">Cancel</button>
            <button v-if="!deleteMatchCount"
              class="flex-1 rounded-xl py-2.5 text-sm font-semibold transition-all"
              :class="deleteConfirmText === deleteTarget.clubs?.name && !deleteBusy
                ? 'bg-rose-600 hover:bg-rose-500 text-white'
                : 'bg-rose-900/40 text-rose-700 cursor-not-allowed'"
              :disabled="deleteConfirmText !== deleteTarget.clubs?.name || deleteBusy"
              @click="confirmDeleteClub">
              {{ deleteBusy ? 'Deleting…' : '🗑 Delete Club Permanently' }}
            </button>
          </div>
        </div>

      </div>
    </div>
  </Teleport>

  <!-- ── Delete join request confirm ── -->
  <Teleport to="body">
    <div v-if="confirmDelReqId" class="fixed inset-0 z-50 flex items-center justify-center px-5"
      style="background:rgba(0,0,0,.75);backdrop-filter:blur(6px)"
      @click.self="confirmDelReqId = null">
      <div class="w-full max-w-sm rounded-2xl p-6"
        style="background:#0d1a2e; border:1px solid rgba(244,63,94,.25); box-shadow:0 0 40px rgba(244,63,94,.12)">
        <div class="text-center mb-4">
          <div class="text-3xl mb-2">🗑️</div>
          <p class="font-semibold text-slate-100 mb-1">Delete this request?</p>
          <p class="text-xs text-slate-400">This will permanently remove the rejected join request.</p>
        </div>
        <div class="flex gap-3">
          <button class="flex-1 py-3 rounded-xl text-sm font-semibold text-slate-300 border border-white/10 hover:border-white/25 hover:text-white transition"
            @click="confirmDelReqId = null">Cancel</button>
          <button class="flex-1 py-3 rounded-xl text-sm font-bold text-white transition active:scale-[.97]"
            style="background:rgba(220,38,38,.85); border:1px solid rgba(244,63,94,.4)"
            @click="deleteRequest">Yes, Delete</button>
        </div>
      </div>
    </div>
  </Teleport>
</template>
