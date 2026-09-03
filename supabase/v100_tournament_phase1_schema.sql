-- v100_tournament_phase1_schema
-- Applied migration exported from Supabase (project bdmiirppiyopmdfrztoz), archived for rebuild parity.

-- Tournament rebuild — Phase 1 additive schema (registration/approval/payment,
-- public share pages, location, and columns future phases will use).

-- Registrations: payment tracking, optional links to real B360 players, contact.
ALTER TABLE tournament_registrations
  ADD COLUMN IF NOT EXISTS payment_status   text DEFAULT 'pending',   -- pending | confirmed
  ADD COLUMN IF NOT EXISTS player_a_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS player_b_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS contact_phone    text;

-- Tournaments: draw type, courts, shareable code, souvenir photos, podium.
ALTER TABLE tournaments
  ADD COLUMN IF NOT EXISTS draw_type              text DEFAULT 'knockout',  -- knockout | round_robin | groups_knockout
  ADD COLUMN IF NOT EXISTS courts                 integer DEFAULT 1,
  ADD COLUMN IF NOT EXISTS share_code             text,
  ADD COLUMN IF NOT EXISTS cover_photo_url        text,
  ADD COLUMN IF NOT EXISTS group_photo_url        text,
  ADD COLUMN IF NOT EXISTS runner_up_registration_id uuid,
  ADD COLUMN IF NOT EXISTS third_registration_id  uuid,
  ADD COLUMN IF NOT EXISTS groups_count           integer DEFAULT 0,
  ADD COLUMN IF NOT EXISTS advance_per_group      integer DEFAULT 2;

-- Seed draw_type from the legacy format for existing rows.
UPDATE tournaments
   SET draw_type = CASE WHEN format = 'round_robin' THEN 'round_robin' ELSE 'knockout' END
 WHERE draw_type IS NULL;

-- Matches: court + group stage support (for concurrent play + groups→knockout).
ALTER TABLE tournament_matches
  ADD COLUMN IF NOT EXISTS court       text,
  ADD COLUMN IF NOT EXISTS stage       text DEFAULT 'knockout',  -- group | knockout
  ADD COLUMN IF NOT EXISTS group_label text;

-- Backfill a short share_code for every existing tournament and enforce uniqueness.
UPDATE tournaments
   SET share_code = lower(substr(replace(id::text,'-',''), 1, 8))
 WHERE share_code IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS tournaments_share_code_key ON tournaments(share_code);

-- Souvenir photo gallery (uses R2 storage via the existing r2-upload-url function).
CREATE TABLE IF NOT EXISTS tournament_photos (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tournament_id uuid NOT NULL REFERENCES tournaments(id) ON DELETE CASCADE,
  url           text NOT NULL,
  caption       text,
  kind          text DEFAULT 'gallery',  -- gallery | group | podium
  created_by    uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at    timestamptz DEFAULT now()
);
ALTER TABLE tournament_photos ENABLE ROW LEVEL SECURITY;

-- Player achievements — drives "winner shown on profile".
CREATE TABLE IF NOT EXISTS player_tournament_results (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  tournament_id   uuid NOT NULL REFERENCES tournaments(id) ON DELETE CASCADE,
  registration_id uuid REFERENCES tournament_registrations(id) ON DELETE SET NULL,
  placement       integer,   -- 1,2,3
  created_at      timestamptz DEFAULT now(),
  UNIQUE (user_id, tournament_id)
);
ALTER TABLE player_tournament_results ENABLE ROW LEVEL SECURITY;
CREATE POLICY ptr_read ON player_tournament_results FOR SELECT USING (true);

CREATE INDEX IF NOT EXISTS idx_treg_tournament ON tournament_registrations(tournament_id);
CREATE INDEX IF NOT EXISTS idx_tmatch_tournament ON tournament_matches(tournament_id);
CREATE INDEX IF NOT EXISTS idx_tphotos_tournament ON tournament_photos(tournament_id);;
