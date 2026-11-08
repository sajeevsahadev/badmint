<script setup>
// Tap-to-name player mapping. The vision pipeline produces person "tracks"; here a human assigns
// each track to a roster player (or a placeholder like "Opponent A"). If no tracks exist yet
// (pre-pipeline, or a fresh upload), we synthesise one slot per expected court position so the
// user can still name who is where. Players who OPTED IN to face recognition (Settings → Security)
// may be pre-filled as a suggestion; a human still confirms every tag by saving.
import { ref, onMounted, computed, watch } from 'vue'
import { supabase } from '../lib/supabase'
import { withNicknames } from '../lib/playerNames'
import { getPlaybackUrl } from '../lib/videoStorage'
import { expectedSides as sidesFor, slotsComplete, buildTags } from '../lib/videoAnalysis'

const props = defineProps({
  videoId:      { type: String, required: true },
  clubId:       { type: String, required: true },
  gameType:     { type: String, default: 'doubles' },
  tracks:       { type: Array,  default: () => [] },   // from the pipeline (may be empty)
  existingTags: { type: Array,  default: () => [] },
  photos:       { type: Object, default: () => ({}) }, // R2 key -> presigned URL (from the parent)
})
const emit = defineEmits(['saved', 'cancel'])

const roster  = ref([])
const slots    = ref([])
const saving  = ref(false)
const err     = ref('')

const sideLabel = (s) => ({
  near: 'Near side', far: 'Far side',
  near_left: 'Near · left', near_right: 'Near · right',
  far_left: 'Far · left', far_right: 'Far · right',
}[s] || s || '')

const expectedSides = computed(() => sidesFor(props.gameType))

// One slot per expected court position (in a fixed order), filled from the detected track at that
// position when we have one — so a photo of the person appears next to the name picker.
function buildSlots() {
  const prevBySide = Object.fromEntries(slots.value.map(s => [s.court_side, s]))
  slots.value = expectedSides.value.map((side, i) => {
    const tr = props.tracks.find(t => t.court_side === side)
    const b = { track_id: tr?.id || null, court_side: side, thumb_path: tr?.thumb_path || null, label_hint: 'P' + (i + 1) }
    const cur = prevBySide[side]
    if (cur) return { ...b, assign: cur.assign, label: cur.label, is_subject: cur.is_subject }   // keep in-progress edits
    const prior = props.existingTags.find(g => (b.track_id && g.track_id === b.track_id) || g.court_side === side)
    return {
      ...b,
      assign: prior?.player_id ? ('p:' + prior.player_id) : (prior?.label ? 'label' : ''),
      label: prior?.label || '',
      is_subject: prior ? prior.is_subject : true,
    }
  })
}

onMounted(async () => {
  buildSlots()
  const { data } = await supabase.from('players')
    .select('id, display_name, user_id')
    .eq('club_id', props.clubId).eq('is_active', true).order('display_name')
  roster.value = await withNicknames(data ?? [])
  suggest()
})
// Photos can arrive while the tagger is open (the people-detection pass finishes in the background).
watch(() => props.tracks.map(t => `${t.id}:${t.court_side}:${t.thumb_path}`).join('|'), () => { buildSlots(); suggest() })

// Opt-in face recognition: fill EMPTY slots only (never overwrite a choice), and mark them so the
// user can see it was a suggestion. Nothing is saved until they press Save.
const suggested = ref({})   // court_side -> { pid, score, confident }
async function suggest() {
  const { data } = await supabase.rpc('suggest_video_tags', { p_video_id: props.videoId })
  if (!data?.length) return
  const map = { ...suggested.value }
  for (const r of data) {
    const s = slots.value.find(x => x.court_side === r.court_side)
    if (!s || !roster.value.some(p => p.id === r.player_id)) continue
    if (slots.value.some(x => x.assign === 'p:' + r.player_id && x !== s)) continue
    if (!s.assign) s.assign = 'p:' + r.player_id
    map[r.court_side] = { pid: r.player_id, score: r.score, confident: r.confident }
  }
  suggested.value = map
}
function suggestionFor(s) {
  const g = suggested.value[s.court_side]
  return g && s.assign === 'p:' + g.pid ? g : null
}

const fetched = ref({})
function photoFor(s) {
  if (!s.thumb_path) return ''
  if (props.photos[s.thumb_path]) return props.photos[s.thumb_path]
  if (!(s.thumb_path in fetched.value)) {
    fetched.value = { ...fetched.value, [s.thumb_path]: '' }
    getPlaybackUrl(s.thumb_path).then(u => { fetched.value = { ...fetched.value, [s.thumb_path]: u || '' } }).catch(() => {})
  }
  return fetched.value[s.thumb_path] || ''
}

const complete = computed(() => slotsComplete(slots.value))

async function save() {
  err.value = ''
  saving.value = true
  try {
    const tags = buildTags(slots.value)
    const { error } = await supabase.rpc('set_video_tags', { p_video_id: props.videoId, p_tags: tags })
    if (error) throw error
    emit('saved')
  } catch (e) {
    err.value = e?.message || 'Could not save tags.'
  } finally {
    saving.value = false
  }
}
</script>

<template>
  <div class="card p-4">
    <div class="mb-1 text-sm font-bold text-slate-800">Who's who in this video?</div>
    <p class="mb-3 text-xs text-slate-500">
      Name each person by where they stand <b>at the start of the video</b>. We analyse everyone, so name
      opponents too (reports are generated for anyone marked “analyse”). You can fix this later.
    </p>

    <div class="space-y-3">
      <div v-for="(s, i) in slots" :key="i" class="rounded-xl border border-slate-200 p-3">
        <div class="flex items-center gap-3">
          <div class="flex h-16 w-12 shrink-0 items-center justify-center overflow-hidden rounded-lg bg-slate-100 text-xs font-bold text-slate-400">
            <img v-if="photoFor(s)" :src="photoFor(s)" alt="Player photo" class="h-full w-full object-cover object-top" />
            <span v-else>{{ s.label_hint }}</span>
          </div>
          <div class="min-w-0 flex-1">
            <div class="flex items-center justify-between gap-2">
              <span class="text-[11px] font-semibold uppercase tracking-wide text-slate-400">{{ sideLabel(s.court_side) }}</span>
              <span v-if="suggestionFor(s)" class="rounded-full px-2 py-0.5 text-[10px] font-bold"
                :class="suggestionFor(s).confident ? 'bg-emerald-100 text-emerald-700' : 'bg-amber-100 text-amber-700'">
                ✨ {{ suggestionFor(s).confident ? 'Recognised' : 'Maybe' }} · check
              </span>
            </div>
            <select v-model="s.assign"
              class="mt-1 w-full rounded-lg border border-slate-200 px-2 py-1.5 text-sm focus:border-cyan-400 focus:outline-none">
              <option value="">— Select —</option>
              <optgroup label="Club players">
                <option v-for="p in roster" :key="p.id" :value="'p:' + p.id">{{ p.display_name }}</option>
              </optgroup>
              <option value="label">Opponent / guest (type a name)</option>
            </select>
            <input v-if="s.assign === 'label'" v-model="s.label" type="text" placeholder="e.g. Opponent A"
              class="mt-2 w-full rounded-lg border border-slate-200 px-2 py-1.5 text-sm focus:border-cyan-400 focus:outline-none" />
          </div>
        </div>
        <label class="mt-2 flex items-center gap-2 text-xs text-slate-500">
          <input type="checkbox" v-model="s.is_subject" class="h-4 w-4 accent-cyan-600" />
          Generate a full report for this player
        </label>
      </div>
    </div>

    <p v-if="Object.keys(suggested).length" class="mt-3 text-xs text-slate-500">
      ✨ Some players were recognised by face (only players who turned this on). Please check them before saving.
    </p>
    <p v-if="err" class="mt-3 text-sm text-red-600">{{ err }}</p>
    <div class="mt-4 flex gap-2">
      <button :disabled="!complete || saving" @click="save"
        class="btn-primary flex-1 py-2.5 disabled:opacity-40">
        {{ saving ? 'Saving…' : 'Save tags' }}
      </button>
      <button @click="emit('cancel')" class="btn-ghost px-4 py-2.5 text-sm">Cancel</button>
    </div>
  </div>
</template>
