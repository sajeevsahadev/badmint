-- v43: Fix delete_match blocked by live_matches FK constraint.
-- live_matches.match_id references matches(id) without ON DELETE SET NULL,
-- so deleting a match that was recorded via live scoring fails with FK violation.
-- Fix: drop and re-add the constraint with ON DELETE SET NULL so the link is
-- cleared when the match is deleted (the live session record is preserved).

ALTER TABLE live_matches DROP CONSTRAINT IF EXISTS live_matches_match_id_fkey;

ALTER TABLE live_matches
  ADD CONSTRAINT live_matches_match_id_fkey
  FOREIGN KEY (match_id) REFERENCES matches(id) ON DELETE SET NULL;
