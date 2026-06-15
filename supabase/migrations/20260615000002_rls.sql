-- ============================================================
-- POLLA NORTE VERDE 2026 — ROW LEVEL SECURITY
-- Migración 002: Políticas de acceso por tabla
-- ============================================================

ALTER TABLE teams             ENABLE ROW LEVEL SECURITY;
ALTER TABLE players           ENABLE ROW LEVEL SECURITY;
ALTER TABLE profiles          ENABLE ROW LEVEL SECURITY;
ALTER TABLE matches           ENABLE ROW LEVEL SECURITY;
ALTER TABLE predictions       ENABLE ROW LEVEL SECURITY;
ALTER TABLE bonus_predictions ENABLE ROW LEVEL SECURITY;
ALTER TABLE phase_submissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE app_config        ENABLE ROW LEVEL SECURITY;
ALTER TABLE rank_snapshots    ENABLE ROW LEVEL SECURITY;

-- ── TEAMS: lectura pública, escritura solo admin vía service role ──
CREATE POLICY "teams_select_all"
  ON teams FOR SELECT USING (true);

-- ── PLAYERS: lectura pública ──────────────────────────────────
CREATE POLICY "players_select_all"
  ON players FOR SELECT USING (true);

-- ── PROFILES: lectura pública, escritura propia + service role ──
CREATE POLICY "profiles_select_all"
  ON profiles FOR SELECT USING (true);

CREATE POLICY "profiles_insert_own"
  ON profiles FOR INSERT
  WITH CHECK (auth.uid() = auth_user_id);

CREATE POLICY "profiles_update_own"
  ON profiles FOR UPDATE
  USING (auth.uid() = auth_user_id);

-- ── MATCHES: lectura pública ──────────────────────────────────
CREATE POLICY "matches_select_all"
  ON matches FOR SELECT USING (true);

-- ── PREDICTIONS: lectura pública (si predicciones_visible) o propia ──
-- Lectura: propias siempre; de otros solo si predictions_visible=true
CREATE POLICY "predictions_select"
  ON predictions FOR SELECT
  USING (
    participant_id = (
      SELECT id FROM profiles WHERE auth_user_id = auth.uid() LIMIT 1
    )
    OR
    (SELECT value FROM app_config WHERE key = 'predictions_visible') = 'true'
  );

CREATE POLICY "predictions_insert_own"
  ON predictions FOR INSERT
  WITH CHECK (
    participant_id = (
      SELECT id FROM profiles WHERE auth_user_id = auth.uid() LIMIT 1
    )
  );

CREATE POLICY "predictions_update_own"
  ON predictions FOR UPDATE
  USING (
    participant_id = (
      SELECT id FROM profiles WHERE auth_user_id = auth.uid() LIMIT 1
    )
  );

-- ── BONUS PREDICTIONS: lectura pública, escritura propia ──────
CREATE POLICY "bonus_select_all"
  ON bonus_predictions FOR SELECT USING (true);

CREATE POLICY "bonus_insert_own"
  ON bonus_predictions FOR INSERT
  WITH CHECK (
    participant_id = (
      SELECT id FROM profiles WHERE auth_user_id = auth.uid() LIMIT 1
    )
  );

CREATE POLICY "bonus_update_own"
  ON bonus_predictions FOR UPDATE
  USING (
    participant_id = (
      SELECT id FROM profiles WHERE auth_user_id = auth.uid() LIMIT 1
    )
  );

-- ── PHASE_SUBMISSIONS: lectura pública, escritura propia ──────
CREATE POLICY "phase_submissions_select"
  ON phase_submissions FOR SELECT USING (true);

CREATE POLICY "phase_submissions_insert_own"
  ON phase_submissions FOR INSERT
  WITH CHECK (
    participant_id = (
      SELECT id FROM profiles WHERE auth_user_id = auth.uid() LIMIT 1
    )
  );

-- ── APP_CONFIG: lectura pública ───────────────────────────────
CREATE POLICY "app_config_select_all"
  ON app_config FOR SELECT USING (true);

-- ── RANK_SNAPSHOTS: lectura pública ───────────────────────────
CREATE POLICY "rank_snapshots_select_all"
  ON rank_snapshots FOR SELECT USING (true);
