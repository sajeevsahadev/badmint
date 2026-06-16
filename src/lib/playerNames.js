import { supabase } from './supabase'

/**
 * Enriches an array of player rows (must include user_id) by resolving
 * user_profiles nicknames. Returns the same array with display_name
 * replaced by the player's nickname where one has been set.
 * Guest players (no user_id) keep their original display_name.
 */
export async function withNicknames(players) {
  if (!players?.length) return players ?? []
  const linked = players.filter(p => p.user_id).map(p => p.user_id)
  if (!linked.length) return players
  const { data } = await supabase.rpc('get_public_profiles', { p_user_ids: linked })
  const nickMap = Object.fromEntries(
    (data ?? []).filter(p => p.nickname).map(p => [p.user_id, p.nickname])
  )
  return players.map(p => ({
    ...p,
    display_name: (p.user_id && nickMap[p.user_id]) || p.display_name
  }))
}

/**
 * Builds a player_id → resolved display name map from a list of player IDs.
 * Used when only IDs are available (e.g. match participant nested queries).
 */
export async function buildNameMap(playerIds) {
  if (!playerIds?.length) return {}
  const { data: rows } = await supabase
    .from('players')
    .select('id, display_name, user_id')
    .in('id', playerIds)
  const resolved = await withNicknames(rows ?? [])
  return Object.fromEntries(resolved.map(p => [p.id, p.display_name]))
}
