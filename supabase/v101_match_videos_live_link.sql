-- Link a recorded video to the live match it was filmed during. match_id stays null until the
-- live match is finished (which creates the matches row); we backfill it then (client-side in
-- LiveMatch.finishMatch). Applied to bdmiirppiyopmdfrztoz via MCP.
alter table public.match_videos
  add column if not exists live_match_id uuid references public.live_matches(id) on delete set null;
create index if not exists idx_match_videos_live on public.match_videos(live_match_id);
