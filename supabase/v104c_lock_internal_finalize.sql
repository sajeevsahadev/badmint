-- v104c_lock_internal_finalize
-- Applied migration exported from Supabase (project bdmiirppiyopmdfrztoz), archived for rebuild parity.

-- _finalize_tournament is an internal helper with no auth check; it must not be
-- callable directly. record_tournament_result (SECURITY DEFINER) still reaches
-- it as the function owner.
REVOKE EXECUTE ON FUNCTION public._finalize_tournament(uuid) FROM public, anon, authenticated;;
