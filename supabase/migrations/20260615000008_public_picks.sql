-- ============================================================
-- POLLA NORTE VERDE 2026 — Migración 008
-- RPCs públicas para El Resto:
--   get_all_bonus_picks  → apuestas especiales de todos
--   get_match_predictions → pronósticos de todos para un partido
-- Solo visibles cuando predictions_visible = true (o admin).
-- ============================================================

CREATE OR REPLACE FUNCTION get_all_bonus_picks()
RETURNS JSON LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_visible BOOLEAN := FALSE;
BEGIN
  SELECT (value = 'true') INTO v_visible FROM app_config WHERE key = 'predictions_visible';

  IF NOT v_visible THEN
    IF NOT EXISTS (
      SELECT 1 FROM profiles WHERE auth_user_id = auth.uid() AND is_admin = TRUE
    ) THEN
      RETURN '[]'::JSON;
    END IF;
  END IF;

  RETURN COALESCE(
    (SELECT json_agg(r ORDER BY r.profile_name)
     FROM (
       SELECT
         bp.top_scorer_name,
         bp.mvp_name,
         bp.finalist1_name,
         bp.finalist2_name,
         p.id        AS profile_id,
         p.name      AS profile_name,
         p.avatar_url
       FROM bonus_predictions bp
       JOIN profiles p ON p.id = bp.participant_id
     ) r),
    '[]'::JSON
  );
END;
$$;

CREATE OR REPLACE FUNCTION get_match_predictions(p_match_id INT)
RETURNS JSON LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_visible BOOLEAN := FALSE;
BEGIN
  SELECT (value = 'true') INTO v_visible FROM app_config WHERE key = 'predictions_visible';

  IF NOT v_visible THEN
    IF NOT EXISTS (
      SELECT 1 FROM profiles WHERE auth_user_id = auth.uid() AND is_admin = TRUE
    ) THEN
      RETURN '[]'::JSON;
    END IF;
  END IF;

  RETURN COALESCE(
    (SELECT json_agg(r ORDER BY r.profile_name)
     FROM (
       SELECT
         pr.home_goals,
         pr.away_goals,
         pr.points,
         pr.is_exact,
         p.id        AS profile_id,
         p.name      AS profile_name,
         p.avatar_url
       FROM predictions pr
       JOIN profiles p ON p.id = pr.participant_id
       WHERE pr.match_id = p_match_id
     ) r),
    '[]'::JSON
  );
END;
$$;
