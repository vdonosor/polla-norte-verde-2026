-- ============================================================
-- POLLA NORTE VERDE 2026 — FUNCIONES RPC
-- Migración 003: Todas las funciones de negocio (PL/pgSQL)
-- ============================================================

-- ── HELPER: puntaje según fase y tipo de acierto ─────────────
CREATE OR REPLACE FUNCTION score_for_phase(p_phase match_phase, p_exact BOOLEAN)
RETURNS INT LANGUAGE plpgsql AS $$
BEGIN
  IF p_exact THEN
    RETURN CASE p_phase
      WHEN 'Grupos'     THEN 2
      WHEN '16avos'     THEN 3
      WHEN '8vos'       THEN 3
      WHEN '4tos'       THEN 4
      WHEN 'Semis'      THEN 5
      WHEN '3er lugar'  THEN 5
      WHEN 'Final'      THEN 6
    END;
  ELSE
    RETURN CASE p_phase
      WHEN 'Grupos'     THEN 1
      WHEN '16avos'     THEN 1
      WHEN '8vos'       THEN 1
      WHEN '4tos'       THEN 2
      WHEN 'Semis'      THEN 3
      WHEN '3er lugar'  THEN 3
      WHEN 'Final'      THEN 4
    END;
  END IF;
END;
$$;

-- ── HELPER: determinar ganador ────────────────────────────────
CREATE OR REPLACE FUNCTION winner_side(p_home INT, p_away INT)
RETURNS TEXT LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE
    WHEN p_home > p_away THEN 'home'
    WHEN p_away > p_home THEN 'away'
    ELSE 'draw'
  END;
$$;

-- ── register_profile() ────────────────────────────────────────
-- Crea o recupera el perfil del usuario auth actual.
-- Llamar después de signUp/signIn.
CREATE OR REPLACE FUNCTION register_profile(p_name TEXT DEFAULT NULL)
RETURNS JSON LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_profile profiles%ROWTYPE;
  v_uid     UUID := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RETURN json_build_object('error', 'NOT_AUTHENTICATED');
  END IF;

  SELECT * INTO v_profile FROM profiles WHERE auth_user_id = v_uid LIMIT 1;

  IF v_profile.id IS NULL THEN
    -- Perfil nuevo: requiere nombre
    IF p_name IS NULL THEN
      RETURN json_build_object('error', 'NAME_REQUIRED');
    END IF;
    INSERT INTO profiles (name, auth_user_id, has_pin)
      VALUES (p_name, v_uid, TRUE)
      RETURNING * INTO v_profile;
  ELSE
    -- Perfil existente: marcar pin como confirmado
    UPDATE profiles SET has_pin = TRUE WHERE id = v_profile.id
      RETURNING * INTO v_profile;
  END IF;

  RETURN json_build_object(
    'id',        v_profile.id,
    'name',      v_profile.name,
    'is_admin',  v_profile.is_admin,
    'can_submit',v_profile.can_submit,
    'avatar_url',v_profile.avatar_url
  );
END;
$$;

-- ── list_profiles() ───────────────────────────────────────────
-- Lista pública de perfiles (para la pantalla de selección de usuario).
CREATE OR REPLACE FUNCTION list_profiles()
RETURNS JSON LANGUAGE sql SECURITY DEFINER AS $$
  SELECT json_agg(
    json_build_object(
      'id',       id,
      'name',     name,
      'avatar_url', avatar_url,
      'has_pin',  has_pin
    ) ORDER BY name
  )
  FROM profiles;
$$;

-- ── set_avatar(p_data) ────────────────────────────────────────
-- Guarda avatar del perfil autenticado (base64 o URL).
CREATE OR REPLACE FUNCTION set_avatar(p_data TEXT)
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_uid UUID := auth.uid();
BEGIN
  UPDATE profiles SET avatar_url = p_data
  WHERE auth_user_id = v_uid;
  IF NOT FOUND THEN RETURN 'NOT_FOUND'; END IF;
  RETURN 'OK';
END;
$$;

-- ── confirm_email(p_email) ────────────────────────────────────
-- Workaround para auto-confirmar email en signup (usa service role internamente).
-- Llamar desde el cliente justo después de signUp.
CREATE OR REPLACE FUNCTION confirm_email(p_email TEXT)
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE auth.users
    SET email_confirmed_at = NOW(),
        confirmed_at        = NOW()
  WHERE email = p_email
    AND email_confirmed_at IS NULL;
  RETURN 'OK';
END;
$$;

-- ── save_predictions(p_phase, p_items, p_final) ───────────────
-- Guarda predicciones de una fase. p_items es un array JSON:
-- [{"match_id": 1, "home_goals": 2, "away_goals": 1}, ...]
-- p_final = true → registra phase_submission (bloqueo definitivo)
CREATE OR REPLACE FUNCTION save_predictions(
  p_phase  match_phase,
  p_items  JSONB,
  p_final  BOOLEAN DEFAULT FALSE
)
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_profile_id INT;
  v_uid        UUID := auth.uid();
  v_item       JSONB;
  v_match      matches%ROWTYPE;
  v_deadline   TIMESTAMPTZ;
BEGIN
  SELECT id INTO v_profile_id FROM profiles WHERE auth_user_id = v_uid LIMIT 1;
  IF v_profile_id IS NULL THEN RETURN 'NOT_AUTHENTICATED'; END IF;

  -- Verificar que la fase no esté enviada
  IF EXISTS (
    SELECT 1 FROM phase_submissions
    WHERE participant_id = v_profile_id AND phase = p_phase
  ) THEN
    RETURN 'FASE_BLOQUEADA';
  END IF;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    v_match := NULL;
    SELECT * INTO v_match FROM matches
      WHERE id = (v_item->>'match_id')::INT AND phase = p_phase;

    IF v_match.id IS NULL THEN CONTINUE; END IF;

    -- Verificar deadline del partido
    IF v_match.deadline_at IS NOT NULL AND NOW() > v_match.deadline_at THEN
      CONTINUE;  -- saltar partidos ya cerrados (no error, solo ignorar)
    END IF;

    INSERT INTO predictions (participant_id, match_id, home_goals, away_goals, updated_at)
      VALUES (
        v_profile_id,
        v_match.id,
        (v_item->>'home_goals')::INT,
        (v_item->>'away_goals')::INT,
        NOW()
      )
    ON CONFLICT (participant_id, match_id) DO UPDATE
      SET home_goals = EXCLUDED.home_goals,
          away_goals = EXCLUDED.away_goals,
          updated_at = NOW();
  END LOOP;

  -- Envío definitivo: bloquear fase
  IF p_final THEN
    INSERT INTO phase_submissions (participant_id, phase)
      VALUES (v_profile_id, p_phase)
      ON CONFLICT DO NOTHING;
  END IF;

  RETURN 'OK';
END;
$$;

-- ── save_bonus(p_top, p_mvp, p_f1, p_f2) ─────────────────────
-- Guarda predicciones de bonus. Solo antes del deadline de grupos.
CREATE OR REPLACE FUNCTION save_bonus(
  p_top TEXT,
  p_mvp TEXT,
  p_f1  TEXT,
  p_f2  TEXT
)
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_profile_id INT;
  v_uid        UUID := auth.uid();
  v_deadline   TIMESTAMPTZ;
BEGIN
  SELECT id INTO v_profile_id FROM profiles WHERE auth_user_id = v_uid LIMIT 1;
  IF v_profile_id IS NULL THEN RETURN 'NOT_AUTHENTICATED'; END IF;

  -- Deadline de grupos = deadline del primer partido habilitado
  SELECT MIN(deadline_at) INTO v_deadline FROM matches WHERE phase = 'Grupos';
  IF v_deadline IS NOT NULL AND NOW() > v_deadline THEN
    RETURN 'DEADLINE_PASADO';
  END IF;

  INSERT INTO bonus_predictions (participant_id, top_scorer_name, mvp_name, finalist1_name, finalist2_name)
    VALUES (v_profile_id, p_top, p_mvp, p_f1, p_f2)
  ON CONFLICT (participant_id) DO UPDATE
    SET top_scorer_name = EXCLUDED.top_scorer_name,
        mvp_name        = EXCLUDED.mvp_name,
        finalist1_name  = EXCLUDED.finalist1_name,
        finalist2_name  = EXCLUDED.finalist2_name;

  RETURN 'OK';
END;
$$;

-- ── set_result(p_match_id, p_home, p_away, ...) ───────────────
-- Admin: registra resultado y recalcula puntos de todas las predicciones.
CREATE OR REPLACE FUNCTION set_result(
  p_match_id     INT,
  p_home         INT,
  p_away         INT,
  p_home_scorers TEXT DEFAULT '',
  p_away_scorers TEXT DEFAULT ''
)
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_uid         UUID := auth.uid();
  v_is_admin    BOOLEAN;
  v_match       matches%ROWTYPE;
  v_exact       BOOLEAN;
  v_correct     BOOLEAN;
  v_pts         INT;
  v_pred        predictions%ROWTYPE;
  v_winner      TEXT;
BEGIN
  SELECT is_admin INTO v_is_admin FROM profiles WHERE auth_user_id = v_uid LIMIT 1;
  IF NOT COALESCE(v_is_admin, FALSE) THEN RETURN 'NOT_ADMIN'; END IF;

  SELECT * INTO v_match FROM matches WHERE id = p_match_id;
  IF v_match.id IS NULL THEN RETURN 'MATCH_NOT_FOUND'; END IF;

  v_winner := winner_side(p_home, p_away);

  -- Actualizar resultado del partido
  UPDATE matches SET
    home_goals     = p_home,
    away_goals     = p_away,
    home_scorers   = p_home_scorers,
    away_scorers   = p_away_scorers,
    winner_side    = v_winner,
    status         = 'FINALIZADO'
  WHERE id = p_match_id;

  -- Recalcular puntos para cada predicción de este partido
  FOR v_pred IN
    SELECT * FROM predictions WHERE match_id = p_match_id
  LOOP
    v_exact   := (v_pred.home_goals = p_home AND v_pred.away_goals = p_away);
    v_correct := (winner_side(v_pred.home_goals, v_pred.away_goals) = v_winner);

    IF v_exact THEN
      v_pts := score_for_phase(v_match.phase, TRUE);
    ELSIF v_correct THEN
      v_pts := score_for_phase(v_match.phase, FALSE);
    ELSE
      v_pts := 0;
    END IF;

    UPDATE predictions SET
      points   = v_pts,
      is_exact = v_exact
    WHERE id = v_pred.id;
  END LOOP;

  RETURN 'OK';
END;
$$;

-- ── enable_phase(p_phase) ─────────────────────────────────────
-- Admin: habilita los partidos de una fase eliminatoria.
CREATE OR REPLACE FUNCTION enable_phase(p_phase match_phase)
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_uid      UUID := auth.uid();
  v_is_admin BOOLEAN;
BEGIN
  SELECT is_admin INTO v_is_admin FROM profiles WHERE auth_user_id = v_uid LIMIT 1;
  IF NOT COALESCE(v_is_admin, FALSE) THEN RETURN 'NOT_ADMIN'; END IF;

  UPDATE matches SET enabled = TRUE WHERE phase = p_phase;
  RETURN 'OK';
END;
$$;

-- ── set_flags(p_predictions_visible, p_submissions_open) ──────
-- Admin: activa/desactiva flags globales de la app.
CREATE OR REPLACE FUNCTION set_flags(
  p_predictions_visible BOOLEAN,
  p_submissions_open    BOOLEAN
)
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_uid      UUID := auth.uid();
  v_is_admin BOOLEAN;
BEGIN
  SELECT is_admin INTO v_is_admin FROM profiles WHERE auth_user_id = v_uid LIMIT 1;
  IF NOT COALESCE(v_is_admin, FALSE) THEN RETURN 'NOT_ADMIN'; END IF;

  UPDATE app_config SET value = p_predictions_visible::TEXT
    WHERE key = 'predictions_visible';
  UPDATE app_config SET value = p_submissions_open::TEXT
    WHERE key = 'submissions_open';

  RETURN 'OK';
END;
$$;

-- ── set_mvp_real(p_name) ──────────────────────────────────────
-- Admin: registra MVP real y recalcula puntos bonus.
CREATE OR REPLACE FUNCTION set_mvp_real(p_name TEXT)
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_uid      UUID := auth.uid();
  v_is_admin BOOLEAN;
BEGIN
  SELECT is_admin INTO v_is_admin FROM profiles WHERE auth_user_id = v_uid LIMIT 1;
  IF NOT COALESCE(v_is_admin, FALSE) THEN RETURN 'NOT_ADMIN'; END IF;

  UPDATE app_config SET value = p_name WHERE key = 'mvp_real';

  -- Recalcular pts_mvp para todos
  UPDATE bonus_predictions SET
    pts_mvp = CASE WHEN LOWER(TRIM(mvp_name)) = LOWER(TRIM(p_name)) THEN 5 ELSE 0 END;

  RETURN 'OK';
END;
$$;

-- ── recalculate_bonus() ───────────────────────────────────────
-- Recalcula puntos bonus basado en configuración actual.
-- Llamar después de set_mvp_real o cuando el goleador cambia.
CREATE OR REPLACE FUNCTION recalculate_bonus()
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_uid         UUID := auth.uid();
  v_is_admin    BOOLEAN;
  v_top_scorer  TEXT;
  v_mvp         TEXT;
  v_finalist1   TEXT;
  v_finalist2   TEXT;
  v_bp          bonus_predictions%ROWTYPE;
  v_pts_top     INT;
  v_pts_mvp     INT;
  v_pts_fin     INT;
  v_bonus_top   INT;
  v_bonus_mvp   INT;
  v_bonus_one   INT;
  v_bonus_both  INT;
BEGIN
  SELECT is_admin INTO v_is_admin FROM profiles WHERE auth_user_id = v_uid LIMIT 1;
  IF NOT COALESCE(v_is_admin, FALSE) THEN RETURN 'NOT_ADMIN'; END IF;

  SELECT value INTO v_top_scorer FROM app_config WHERE key = 'top_scorer_real';
  SELECT value INTO v_mvp        FROM app_config WHERE key = 'mvp_real';
  -- Finalistas: los dos equipos de la final (fase Final)
  SELECT home_team, away_team INTO v_finalist1, v_finalist2
    FROM matches WHERE phase = 'Final' LIMIT 1;

  SELECT value::INT INTO v_bonus_top  FROM app_config WHERE key = 'bonus_top_scorer';
  SELECT value::INT INTO v_bonus_mvp  FROM app_config WHERE key = 'bonus_mvp';
  SELECT value::INT INTO v_bonus_one  FROM app_config WHERE key = 'bonus_one_finalist';
  SELECT value::INT INTO v_bonus_both FROM app_config WHERE key = 'bonus_both_finalists';

  FOR v_bp IN SELECT * FROM bonus_predictions LOOP
    -- Goleador
    v_pts_top := 0;
    IF v_top_scorer IS NOT NULL AND v_top_scorer != '' THEN
      IF LOWER(TRIM(v_bp.top_scorer_name)) = LOWER(TRIM(v_top_scorer)) THEN
        v_pts_top := v_bonus_top;
      END IF;
    END IF;

    -- MVP
    v_pts_mvp := 0;
    IF v_mvp IS NOT NULL AND v_mvp != '' THEN
      IF LOWER(TRIM(v_bp.mvp_name)) = LOWER(TRIM(v_mvp)) THEN
        v_pts_mvp := v_bonus_mvp;
      END IF;
    END IF;

    -- Finalistas
    v_pts_fin := 0;
    IF v_finalist1 IS NOT NULL AND v_finalist2 IS NOT NULL THEN
      DECLARE
        v_match_count INT := 0;
      BEGIN
        IF LOWER(TRIM(v_bp.finalist1_name)) IN (
             LOWER(TRIM(v_finalist1)), LOWER(TRIM(v_finalist2))
           ) THEN v_match_count := v_match_count + 1; END IF;
        IF LOWER(TRIM(v_bp.finalist2_name)) IN (
             LOWER(TRIM(v_finalist1)), LOWER(TRIM(v_finalist2))
           ) AND LOWER(TRIM(v_bp.finalist2_name)) != LOWER(TRIM(v_bp.finalist1_name))
        THEN v_match_count := v_match_count + 1; END IF;

        IF v_match_count >= 2 THEN
          v_pts_fin := v_bonus_both;
        ELSIF v_match_count = 1 THEN
          v_pts_fin := v_bonus_one;
        END IF;
      END;
    END IF;

    UPDATE bonus_predictions SET
      pts_top_scorer = v_pts_top,
      pts_mvp        = v_pts_mvp,
      pts_finalists  = v_pts_fin
    WHERE participant_id = v_bp.participant_id;
  END LOOP;

  RETURN 'OK';
END;
$$;

-- ── get_group_standings() ─────────────────────────────────────
-- Calcula tabla de posiciones por grupo.
CREATE OR REPLACE FUNCTION get_group_standings()
RETURNS JSON LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_result JSON;
BEGIN
  SELECT json_object_agg(grp, teams_arr) INTO v_result
  FROM (
    SELECT
      m.group_name AS grp,
      json_agg(
        json_build_object(
          'team',   t.name,
          'flag',   t.flag,
          'pj',     COALESCE(stats.pj, 0),
          'pg',     COALESCE(stats.pg, 0),
          'pe',     COALESCE(stats.pe, 0),
          'pp',     COALESCE(stats.pp, 0),
          'gf',     COALESCE(stats.gf, 0),
          'gc',     COALESCE(stats.gc, 0),
          'dg',     COALESCE(stats.gf - stats.gc, 0),
          'pts',    COALESCE(stats.pts, 0)
        )
        ORDER BY COALESCE(stats.pts, 0) DESC,
                 COALESCE(stats.gf - stats.gc, 0) DESC,
                 COALESCE(stats.gf, 0) DESC
      ) AS teams_arr
    FROM (SELECT DISTINCT group_name FROM matches WHERE phase = 'Grupos') m
    JOIN teams t ON t.group_name = m.group_name
    LEFT JOIN LATERAL (
      SELECT
        COUNT(*)::INT AS pj,
        SUM(CASE WHEN winner_side = 'home' AND home_team_id = t.id THEN 1
                 WHEN winner_side = 'away' AND away_team_id = t.id THEN 1
                 ELSE 0 END)::INT AS pg,
        SUM(CASE WHEN winner_side = 'draw' THEN 1 ELSE 0 END)::INT AS pe,
        SUM(CASE WHEN winner_side = 'home' AND away_team_id = t.id THEN 1
                 WHEN winner_side = 'away' AND home_team_id = t.id THEN 1
                 ELSE 0 END)::INT AS pp,
        SUM(CASE WHEN home_team_id = t.id THEN COALESCE(home_goals, 0)
                 WHEN away_team_id = t.id THEN COALESCE(away_goals, 0)
                 ELSE 0 END)::INT AS gf,
        SUM(CASE WHEN home_team_id = t.id THEN COALESCE(away_goals, 0)
                 WHEN away_team_id = t.id THEN COALESCE(home_goals, 0)
                 ELSE 0 END)::INT AS gc,
        SUM(CASE WHEN winner_side = 'home' AND home_team_id = t.id THEN 3
                 WHEN winner_side = 'away' AND away_team_id = t.id THEN 3
                 WHEN winner_side = 'draw' THEN 1
                 ELSE 0 END)::INT AS pts
      FROM matches
      WHERE status = 'FINALIZADO'
        AND group_name = m.group_name
        AND (home_team_id = t.id OR away_team_id = t.id)
    ) stats ON true
    GROUP BY m.group_name
  ) subq;

  RETURN v_result;
END;
$$;

-- ── get_scorers() ─────────────────────────────────────────────
-- Retorna top goleadores del torneo.
CREATE OR REPLACE FUNCTION get_scorers()
RETURNS JSON LANGUAGE sql SECURITY DEFINER AS $$
  SELECT json_agg(
    json_build_object(
      'name',  p.name,
      'team',  t.name,
      'flag',  t.flag,
      'goals', p.goals
    ) ORDER BY p.goals DESC, p.name
  )
  FROM players p
  JOIN teams t ON t.id = p.team_id
  WHERE p.goals > 0;
$$;

-- ── get_rank_snap() ───────────────────────────────────────────
-- Snapshot de ranking del día anterior para flechas ▲▼.
CREATE OR REPLACE FUNCTION get_rank_snap()
RETURNS JSON LANGUAGE sql SECURITY DEFINER AS $$
  SELECT json_object_agg(profile_id::TEXT, rank)
  FROM rank_snapshots
  WHERE snap_date = CURRENT_DATE - INTERVAL '1 day';
$$;

-- ── take_rank_snap() ──────────────────────────────────────────
-- Guarda snapshot diario del ranking. Llamar con pg_cron cada día.
CREATE OR REPLACE FUNCTION take_rank_snap()
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  INSERT INTO rank_snapshots (profile_id, rank, snap_date)
  SELECT id, ROW_NUMBER() OVER (ORDER BY pts_total DESC, exact_count DESC), CURRENT_DATE
  FROM leaderboard
  ON CONFLICT (profile_id, snap_date) DO UPDATE SET rank = EXCLUDED.rank;
  RETURN 'OK';
END;
$$;
