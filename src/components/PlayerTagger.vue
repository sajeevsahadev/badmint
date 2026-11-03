<script setup>
// Tap-to-name player mapping. The vision pipeline produces person "tracks"; here a human assigns
// each track to a roster player (or a placeholder like "Opponent A"). If no tracks exist yet
// (pre-pipeline, or a fresh upload), we synthesise one slot per expected court position so the
// user can still name who is where. This is the only identity step — we never use face recognition.
import { ref, onMounted, computed } from 'vue'
import { supabase } from '../lib/supabase'
import { withNicknames } from '../lib/playerNames'
import { getPlaybackUrl } from '../lib/videoStorage'

const props = defineProps({
  videoId:      { type: String, required: true },
  clubId:       { type: String, required: true },
  gameType:     { type: String, default: 'doubles' },
  tracks:       { type: Array,  default: () => [] },   // from the pipeline (may be empty)
  existingTags: { type: Array,  default: () => [] },
  thumbBase:    { type: String, default: '' },
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

const expectedSides = computed(() =>
  props.gameType === 'doubles'
    ? ['near_left', 'near_right', 'far_left', 'far_right']
    : ['near', 'far'])

onMounted(async () => {
  const { data } = await supabase.from('players')
    .select('id, display_name, user_id')
    .eq('club_id', props.clubId).eq('is_active', true).order('display_name')
  roster.value = await withNicknames(data ?? [])

  // Build one slot per real track, or synthesise slots per expected court position.
  const base = props.tracks.length
    ? props.tracks.map(t => ({ track_id: t.id, court_side: t.court_side, thumb_path: t.thumb_path, label_hint: t.track_label }))
    : expectedSides.value.map((s, i) => ({ track_id: null, court_side: s, thumb_path: null, label_hint: 'P' + (i + 1) }))

  slots.value = base.map((b) => {
    const prior = props.existingTags.find(g => (b.track_id && g.track_id === b.track_id) || (!b.track_id && g.court_side === b.court_side))
    return {
      ...b,
      assign: prior?.player_id ? ('p:' + prior.player_id) : (prior?.label ? 'label' : ''),
      label: prior?.label || '',
      is_subject: prior ? prior.is_subject : true,
    }
  })
})

const thumbUrls = ref({})
onMounted(async () => {
  for (const t of props.tracks) {
    if (t.thumb_path) { try { thumbUrls.value[t.id] = await getPlaybackUrl(t.thumb_path) } catch { /* ignore */ } }
  }
})

const complete = computed(() => slots.value.every(s =>
  (s.assign && s.assign.startsWith('p:')) || (s.assign === 'label' && s.label.trim())))

async function save() {
  err.value = ''
  saving.value = true
  try {
    const tags = slots.value.map(s => ({
      track_id:  s.track_id || null,
      player_id: s.assign?.startsWith('p:') ? s.assign.slice(2) : null,
      label:     s.assign === 'label' ? s.label.trim() : null,
      court_side: s.court_side || null,
      is_subject: !!s.is_subject,
    }))
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
      Tap to name each person on court. We analyse everyone, so name opponents too (reports are
      generated for anyone marked “analyse”). You can fix this later if a name is wrong.
    </p>

    <div class="space-y-3">
      <div v-for="(s, i) in slots" :key="i" class="rounded-xl border border-slate-200 p-3">
        <div class="flex items-center gap-3">
          <div class="flex h-12 w-12 shrink-0 items-center justify-center overflow-hidden rounded-lg bg-slate-100 text-xs font-bold text-slate-400">
            <img v-if="s.track_id && thumbUrls[s.track_id]" :src="thumbUrls[s.track_id]" class="h-full w-full object-cover" />
            <span v-else>{{ s.label_hint }}</span>
          </div>
          <div class="min-w-0 flex-1">
            <div class="text-[11px] font-semibold uppercase tracking-wide text-slate-400">{{ sideLabel(s.court_side) }}</div>
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
