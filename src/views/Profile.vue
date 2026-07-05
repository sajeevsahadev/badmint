<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { useRouter } from 'vue-router'
import { supabase } from '../lib/supabase'
import { useAuth } from '../composables/useAuth'
import { useClub } from '../composables/useClub'
import { useSession } from '../composables/useSession'
import { compressImageToDataUrl } from '../lib/imageCompress'
import Avatar from '../components/Avatar.vue'
import pkg from '../../package.json'

const router = useRouter()
const { user, signOut } = useAuth()
const { clubs } = useClub()
const { endSession } = useSession()

const appVersion = pkg.version

const profile  = ref(null)   // user_profiles row
const myStats  = ref([])     // leaderboard entries for all clubs this user is a player in
const loading  = ref(true)
const saving   = ref(false)
const saved    = ref(false)
const error    = ref(null)

// Edit form
const form = ref({ nickname: '', phone: '', bio: '', gender: '', avatar_url: '' })
const avatarBusy = ref(false)
const avatarError = ref('')

async function onAvatarFile(e) {
  const file = e.target.files?.[0]
  if (!file) return
  avatarError.value = ''
  avatarBusy.value = true
  try {
    form.value.avatar_url = await compressImageToDataUrl(file)
  } catch (err) {
    avatarError.value = err.message || 'Could not process image.'
  } finally {
    avatarBusy.value = false
    e.target.value = ''  // allow re-selecting same file
  }
}
function removeAvatar() { form.value.avatar_url = '' }

let _savedTimer = null
onUnmounted(() => clearTimeout(_savedTimer))

const GENDER_OPTIONS = [
  { value: '',            label: 'Prefer not to set' },
  { value: 'male',        label: 'Male' },
  { value: 'female',      label: 'Female' },
  { value: 'non_binary',  label: 'Non-binary' },
  { value: 'unspecified', label: 'Rather not to say' },
]

async function load() {
  if (!user.value) return
  loading.value = true

  const [{ data: prof }, { data: playerRows }] = await Promise.all([
    supabase.from('user_profiles').select('*').eq('user_id', user.value.id).maybeSingle(),
    supabase.from('players').select('id, display_name, elo, club_id').eq('user_id', user.value.id),
  ])

  profile.value = prof

  // Load leaderboard stats for each club this user is in
  if (playerRows?.length) {
    const playerIds = playerRows.map(p => p.id)
    const { data: lbRows } = await supabase
      .from('v_leaderboard')
      .select('id, club_id, display_name, elo, composite, club_rank, games, wins, win_pct, days_played')
      .in('id', playerIds)
    myStats.value = lbRows ?? []
  }

  // Pre-fill form
  form.value.nickname    = prof?.nickname   ?? user.value.user_metadata?.full_name ?? ''
  form.value.phone       = prof?.phone      ?? ''
  form.value.bio         = prof?.bio        ?? ''
  form.value.gender      = prof?.gender     ?? ''
  form.value.avatar_url  = prof?.avatar_url ?? ''
  loading.value = false
}

onMounted(load)

async function save() {
  if (!form.value.nickname.trim()) { error.value = 'Nickname is required.'; return }
  saving.value = true; error.value = null; saved.value = false
  const { error: err } = await supabase.rpc('upsert_profile', {
    p_nickname:  form.value.nickname.trim(),
    p_full_name: profile.value?.full_name ?? null,
    p_phone:     form.value.phone.trim() || null,
    p_bio:       form.value.bio.trim()   || null,
    p_emirate:   profile.value?.emirate  ?? null,
    p_country:   profile.value?.country  ?? null,
    p_gender:    form.value.gender || null,
  })
  if (err) { saving.value = false; error.value = err.message; return }

  // avatar_url is not a param of upsert_profile â€” update directly on own row
  const avatarVal = form.value.avatar_url.trim() || null
  await supabase.from('user_profiles')
    .update({ avatar_url: avatarVal })
    .eq('user_id', user.value.id)

  saving.value = false
  saved.value = true
  if (!profile.value) profile.value = {}
  profile.value.nickname   = form.value.nickname.trim()
  profile.value.gender     = form.value.gender || null
  profile.value.avatar_url = avatarVal
  clearTimeout(_savedTimer)
  _savedTimer = setTimeout(() => { saved.value = false }, 3000)
}

const initials = computed(() => {
  const name = form.value.nickname || user.value?.email || '?'
  return name.split(' ').map(w => w[0]).slice(0, 2).join('').toUpperCase()
})

const clubName = (clubId) => clubs.value.find(c => c.club_id === clubId)?.clubs?.name ?? clubId
const clubRole = (clubId) => clubs.value.find(c => c.club_id === clubId)?.role ?? 'player'

const leaving     = ref(null)   // club_id being left
const leaveError  = ref(null)
const leaveNote   = ref(null)

async function leaveClub(clubId) {
  if (!confirm(`Leave "${clubName(clubId)}"?\n\nYou will be removed from this club. You can rejoin later by requesting again.`)) return
  leaving.value = clubId; leaveError.value = null; leaveNote.value = null
  const { error } = await supabase.rpc('leave_club', { p_club_id: clubId })
  leaving.value = null
  if (error) {
    leaveError.value = error.message
  } else {
    // Reload so the club disappears from the list
    await load()
    leaveNote.value = 'You have left the club.'
  }
}

// â”€â”€ Sign out â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
const loggingOut = ref(false)
async function logout() {
  loggingOut.value = true
  await endSession().catch(() => {})
  await signOut()
  router.push('/login')
}

// â”€â”€ Delete Account (GDPR) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
const showDeleteModal  = ref(false)
const deleteConfirmText = ref('')
const deleteChecked    = ref(false)
const deleting         = ref(false)
const deleteError      = ref(null)
const deleteCheckResult = ref(null)  // { can_delete, reason, details }

async function openDeleteModal() {
  deleteConfirmText.value = ''
  deleteChecked.value = false
  deleteError.value = null
  deleteCheckResult.value = null
  deleting.value = false
  showDeleteModal.value = true
  // Run pre-check so user sees their block reason immediately
  const { data } = await supabase.rpc('check_can_delete_account')
  deleteCheckResult.value = data
}

async function confirmDelete() {
  if (deleteConfirmText.value !== 'DELETE') { deleteError.value = 'Type DELETE to confirm'; return }
  if (!deleteChecked.value) { deleteError.value = 'Please tick the confirmation box'; return }
  deleteError.value = null
  deleting.value = true
  try {
    const { data: { session } } = await supabase.auth.getSession()
    const resp = await fetch(
      `${import.meta.env.VITE_SUPABASE_URL}/functions/v1/delete-account`,
      {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${session.access_token}`,
          'Content-Type': 'application/json',
        },
      }
    )
    const body = await resp.json()
    if (!resp.ok) throw new Error(body.error || 'Deletion failed')
    // Account deleted â€” sign out and redirect
    await supabase.auth.signOut()
    window.location.href = '/login'
  } catch (e) {
    deleteError.value = e.message
    deleting.value = false
  }
}
</script>

<template>
  <div v-if="loading" class="space-y-3">
    <div v-for="i in 3" :key="i" class="h-20 shimmer rounded-2xl" />
  </div>

  <template v-else>
    <!-- Avatar + header -->
    <div class="flex items-center gap-4 mb-6 fade-up">
      <Avatar :name="form.nickname" :src="profile?.avatar_url" :size="56" />
      <div>
        <h2 class="font-display text-xl font-bold gradient-text leading-tight">
          {{ profile?.nickname || 'Set your nickname' }}
        </h2>
        <p class="text-xs text-slate-500 mt-0.5">{{ user?.email }}</p>
        <p class="text-[10px] text-slate-600 mt-0.5">{{ clubs.length }} club{{ clubs.length !== 1 ? 's' : '' }}</p>
      </div>
    </div>

    <!-- Edit form -->
    <div class="card p-4 mb-4 fade-up">
      <div class="label">Edit Profile</div>

      <div class="space-y-3">
        <div>
          <label class="label">Nickname / Public Name <span class="text-rose-400">*</span></label>
          <input v-model="form.nickname" class="input" placeholder="How others see you (e.g. Flash)" maxlength="30" />
          <p class="text-[10px] text-slate-500 mt-1">This name appears publicly on leaderboards and explore page.</p>
        </div>
        <div>
          <label class="label">Profile Photo <span class="text-slate-600">(optional)</span></label>
          <div class="mt-1 flex items-center gap-4">
            <Avatar :name="form.nickname" :src="form.avatar_url" :size="72" />
            <div class="flex flex-col gap-2">
              <label class="btn-ghost cursor-pointer inline-flex items-center gap-1 text-sm">
                ðŸ“· Upload Photo
                <input type="file" accept="image/*" class="hidden" @change="onAvatarFile" />
              </label>
              <button v-if="form.avatar_url" type="button" class="text-[11px] text-rose-500 text-left" @click="removeAvatar">
                Remove
              </button>
            </div>
          </div>
          <p v-if="avatarBusy" class="text-[10px] text-neon mt-2">Compressingâ€¦</p>
          <p v-if="avatarError" class="text-[10px] text-rose-500 mt-2">{{ avatarError }}</p>
          <p class="text-[10px] text-slate-500 mt-1">Stored compressed in your profile Â· appears as your avatar across the app.</p>
        </div>
        <div>
          <label class="label">Phone Number <span class="text-slate-600">(optional)</span></label>
          <input v-model="form.phone" class="input" type="tel" placeholder="+971 50 123 4567" />
        </div>
        <div>
          <label class="label">Gender <span class="text-slate-600">(optional)</span></label>
          <select v-model="form.gender" class="input">
            <option v-for="opt in GENDER_OPTIONS" :key="opt.value" :value="opt.value">{{ opt.label }}</option>
          </select>
        </div>
        <div>
          <label class="label">Bio <span class="text-slate-600">(optional)</span></label>
          <textarea v-model="form.bio" class="input resize-none" rows="2"
            placeholder="Tell the court about yourselfâ€¦" maxlength="120" />
        </div>
      </div>

      <p v-if="error" class="mt-3 text-xs text-rose-400">{{ error }}</p>
      <p v-if="saved" class="mt-3 text-xs text-emerald-400">âœ… Profile saved!</p>

      <button class="btn-primary w-full mt-4" :disabled="saving" @click="save">
        {{ saving ? 'Savingâ€¦' : 'Save Profile' }}
      </button>
    </div>

    <!-- Settings -->
    <div class="card overflow-hidden mb-4 fade-up">
      <div class="px-4 py-3 border-b" style="border-color:rgba(15,23,42,.06)">
        <div class="text-xs font-bold text-slate-700">Settings</div>
      </div>
      <RouterLink to="/settings/email"
        class="flex items-center gap-3 px-4 py-3.5 border-b hover:bg-black/[0.02] transition"
        style="border-color:rgba(15,23,42,.04)">
        <span class="text-lg w-6 text-center shrink-0">ðŸ“§</span>
        <span class="text-sm font-medium text-slate-700 flex-1">Email Settings</span>
        <span class="text-slate-300">â€º</span>
      </RouterLink>
      <RouterLink to="/settings/notifications"
        class="flex items-center gap-3 px-4 py-3.5 border-b hover:bg-black/[0.02] transition"
        style="border-color:rgba(15,23,42,.04)">
        <span class="text-lg w-6 text-center shrink-0">ðŸ””</span>
        <span class="text-sm font-medium text-slate-700 flex-1">Device &amp; Push Notifications</span>
        <span class="text-slate-300">â€º</span>
      </RouterLink>
      <RouterLink to="/settings/security"
        class="flex items-center gap-3 px-4 py-3.5 border-b hover:bg-black/[0.02] transition"
        style="border-color:rgba(15,23,42,.04)">
        <span class="text-lg w-6 text-center shrink-0">ðŸ”’</span>
        <span class="text-sm font-medium text-slate-700 flex-1">Security</span>
        <span class="text-slate-300">â€º</span>
      </RouterLink>
      <RouterLink to="/settings/appearance"
        class="flex items-center gap-3 px-4 py-3.5 hover:bg-black/[0.02] transition">
        <span class="text-lg w-6 text-center shrink-0">ðŸŽ¨</span>
        <span class="text-sm font-medium text-slate-700 flex-1">Appearance</span>
        <span class="text-slate-300">â€º</span>
      </RouterLink>
    </div>

    <!-- Sign out -->
    <button class="card w-full flex items-center gap-3 px-4 py-3.5 mb-4 hover:bg-black/[0.02] transition text-left fade-up"
      :disabled="loggingOut" @click="logout">
      <span class="text-lg w-6 text-center shrink-0">ðŸšª</span>
      <span class="text-sm font-medium text-slate-700 flex-1">{{ loggingOut ? 'Signing outâ€¦' : 'Sign Out' }}</span>
    </button>

    <!-- Club stats + leave -->
    <div v-if="myStats.length" class="card overflow-hidden mb-4 fade-up">
      <div class="px-4 py-3 border-b" style="border-color:rgba(15,23,42,.06)">
        <div class="text-xs font-bold text-slate-700">My Club Rankings</div>
      </div>
      <div v-for="s in myStats" :key="s.id"
        class="flex items-center justify-between px-4 py-3 border-b last:border-0 gap-2" style="border-color:rgba(15,23,42,.04)">
        <Avatar :name="s.display_name" :src="profile?.avatar_url" :size="32" class="shrink-0" />
        <div class="flex-1 min-w-0">
          <div class="text-sm font-semibold text-slate-700">{{ clubName(s.club_id) }}</div>
          <div class="text-[11px] text-slate-500">{{ s.display_name }}</div>
        </div>
        <div class="text-right shrink-0">
          <div class="text-sm font-extrabold text-neon">Rank #{{ s.club_rank }}</div>
          <div class="text-[11px] text-slate-500">Elo {{ s.elo }} Â· {{ s.games }}G Â· {{ s.win_pct }}% W</div>
        </div>
        <!-- Leave club button â€” hidden for owners or players with match history -->
        <button v-if="clubRole(s.club_id) !== 'owner' && s.games === 0"
          class="text-[10px] text-rose-500/60 hover:text-rose-400 transition shrink-0 px-1 py-0.5"
          :disabled="leaving === s.club_id"
          @click="leaveClub(s.club_id)">
          {{ leaving === s.club_id ? 'â€¦' : 'Leave' }}
        </button>
      </div>
    </div>

    <p v-if="leaveNote" class="text-xs text-emerald-400 mb-3 px-1">âœ… {{ leaveNote }}</p>
    <p v-if="leaveError" class="text-xs text-rose-400 mb-3 px-1">{{ leaveError }}</p>

    <!-- â”€â”€ Danger Zone â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€ -->
    <div class="mt-6 mb-2 fade-up">
      <div class="rounded-2xl border border-rose-200/60 overflow-hidden" style="background:#fff9f9;">
        <div class="px-4 py-3 border-b border-rose-100 flex items-center gap-2">
          <span class="text-base">âš ï¸</span>
          <span class="text-xs font-bold text-rose-600 uppercase tracking-widest">Danger Zone</span>
        </div>
        <div class="px-4 py-4">
          <div class="text-sm font-semibold text-slate-800 mb-1">Delete My Account</div>
          <p class="text-xs text-slate-500 leading-relaxed mb-3">
            Permanently remove your account and all personal data from Badminton 360.
            Club match history is preserved (anonymised) so Elo rankings stay accurate.
          </p>
          <button
            @click="openDeleteModal"
            class="text-xs font-bold text-rose-600 border border-rose-300 rounded-xl px-4 py-2 hover:bg-rose-50 transition"
          >
            Delete My Accountâ€¦
          </button>
        </div>
      </div>
    </div>

    <!-- Footer -->
    <div class="text-center py-8 fade-up">
      <p class="text-xs text-slate-400 mb-2">Made with ðŸ¸ and â¤ï¸ for badminton communities everywhere</p>
      <p class="text-[11px]">
        <RouterLink to="/privacy" class="text-slate-400 hover:text-cyan-600 transition">Privacy Policy</RouterLink>
      </p>
      <p class="text-[10px] text-slate-300 mt-2">Badminton 360 v{{ appVersion }}</p>
    </div>

  </template>

  <!-- â”€â”€ Delete Account Modal â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€ -->
  <Teleport to="body">
    <Transition name="modal-fade">
      <div v-if="showDeleteModal"
        class="fixed inset-0 z-[300] flex items-end sm:items-center justify-center"
        style="background:rgba(5,13,26,.82); backdrop-filter:blur(6px);">
        <div
          class="w-full sm:max-w-md bg-white rounded-t-3xl sm:rounded-3xl flex flex-col overflow-hidden"
          style="max-height:90dvh; box-shadow:0 24px 64px rgba(0,0,0,.4);">

          <!-- Header stripe -->
          <div class="h-1.5 shrink-0" style="background:linear-gradient(90deg,#ef4444,#b91c1c)" />

          <div class="overflow-y-auto flex-1">
            <div class="px-6 pt-6 pb-2">
              <div class="text-3xl mb-3">ðŸ—‘ï¸</div>
              <h2 class="text-xl font-extrabold text-slate-800 mb-1">Delete Your Account</h2>
              <p class="text-sm text-slate-500 leading-relaxed">
                This is permanent and cannot be undone.
              </p>
            </div>

            <!-- Pre-check result: blocked -->
            <div v-if="deleteCheckResult && !deleteCheckResult.can_delete"
              class="mx-6 mt-4 p-4 rounded-2xl border text-sm leading-relaxed"
              style="background:#fff7f7; border-color:#fecaca; color:#991b1b;">
              <div class="font-bold mb-1">âŒ Can't delete right now</div>
              <p>{{ deleteCheckResult.details }}</p>
            </div>

            <!-- Pre-check: clear to delete -->
            <div v-else class="px-6 mt-4 space-y-4">

              <!-- What gets deleted -->
              <div class="text-xs text-slate-600 space-y-2 bg-slate-50 rounded-xl p-4">
                <div class="font-bold text-slate-700 mb-2">What gets permanently deleted:</div>
                <div>ðŸ—‘ï¸ Your profile (name, phone, bio)</div>
                <div>ðŸ—‘ï¸ All club memberships &amp; join requests</div>
                <div>ðŸ—‘ï¸ Your Split Pay expenses &amp; notes</div>
                <div>ðŸ—‘ï¸ Session &amp; activity history</div>
                <div class="border-t border-slate-200 pt-2 mt-1 text-slate-500">
                  <div>âœ… Match results stay (anonymised) so club rankings remain accurate</div>
                  <div>âœ… Other players' expenses are unaffected</div>
                </div>
              </div>

              <!-- Confirmation checkbox -->
              <label class="flex items-start gap-3 cursor-pointer select-none">
                <input
                  v-model="deleteChecked"
                  type="checkbox"
                  class="mt-0.5 w-4 h-4 rounded accent-rose-500 shrink-0"
                />
                <span class="text-xs text-slate-600 leading-relaxed">
                  I understand this is <strong>permanent</strong>. I have settled all Split Pay
                  balances and no longer need this account.
                </span>
              </label>

              <!-- Type DELETE -->
              <div>
                <label class="text-[10px] font-bold uppercase tracking-widest text-slate-400 block mb-1.5">
                  Type DELETE to confirm
                </label>
                <input
                  v-model="deleteConfirmText"
                  type="text"
                  placeholder="DELETE"
                  class="w-full px-4 py-3 rounded-xl text-sm border font-mono text-slate-800 placeholder-slate-300 focus:outline-none focus:ring-2 focus:ring-rose-300"
                  style="border-color:rgba(239,68,68,.3);"
                />
              </div>

              <p v-if="deleteError" class="text-xs text-rose-600">âš  {{ deleteError }}</p>

            </div>
          </div>

          <!-- Actions -->
          <div class="px-6 pb-6 pt-4 border-t flex flex-col gap-2 shrink-0" style="border-color:rgba(0,0,0,.07);">
            <button
              v-if="deleteCheckResult?.can_delete"
              @click="confirmDelete"
              :disabled="deleting || deleteConfirmText !== 'DELETE' || !deleteChecked"
              class="w-full py-3 rounded-2xl text-sm font-bold text-white transition disabled:opacity-40"
              style="background:linear-gradient(135deg,#ef4444,#b91c1c);"
            >
              {{ deleting ? 'Deletingâ€¦' : 'ðŸ—‘ï¸ Permanently Delete My Account' }}
            </button>
            <button
              @click="showDeleteModal = false"
              class="w-full py-3 rounded-2xl text-sm font-semibold border transition hover:bg-slate-50"
              style="border-color:rgba(0,0,0,.12); color:#475569;"
            >
              Cancel
            </button>
          </div>

        </div>
      </div>
    </Transition>
  </Teleport>
</template>

<style scoped>
.modal-fade-enter-active { transition: opacity .2s ease; }
.modal-fade-leave-active { transition: opacity .15s ease; }
.modal-fade-enter-from, .modal-fade-leave-to { opacity: 0; }
</style>
