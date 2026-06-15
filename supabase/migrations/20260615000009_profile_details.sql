-- ============================================================
-- POLLA NORTE VERDE 2026 — Migración 009
-- RPC get_profile_predictions: retorna todos los pronósticos
-- finalizados de un participante con datos del partido.
-- Acceso: propio perfil siempre; otros solo si predictions_visible.
-- ============================================================

CREATE OR REPLACE FUNCTION get_profile_predictions(p_profile_id INT)
RETURNS JSON LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_visible          BOOLEAN := FALSE;
  v_caller_id        INT;
BEGIN
  SELECT (value = 'true') INTO v_visible FROM app_config WHERE key = 'predictions_visible';
  SELECT id INTO v_caller_id FROM profiles WHERE auth_user_id = auth.uid();

  IF NOT v_visible AND (v_caller_id IS DISTINCT FROM p_profile_id) THEN
    IF NOT EXISTS (
      SELECT 1 FROM profiles WHERE auth_user_id = auth.uid() AND is_admin = TRUE
    ) THEN
      RETURN '[]'::JSON;
    END IF;
  END IF;

  RETURN COALESCE(
    (SELECT json_agg(r ORDER BY r.match_number)
     FROM (
       SELECT
         pr.home_goals       AS pred_home,
         pr.away_goals       AS pred_away,
         pr.points,
         pr.is_exact,
         m.id                AS match_id,
         m.match_number,
         m.home_team,
         m.away_team,
         m.home_goals        AS actual_home,
         m.away_goals        AS actual_away,
         m.home_scorers,
         m.away_scorers,
         m.status,
         m.phase,
         m.group_name
       FROM predictions pr
       JOIN matches m ON m.id = pr.match_id
       WHERE pr.participant_id = p_profile_id
         AND m.status = 'FINALIZADO'
     ) r),
    '[]'::JSON
  );
END;
$$;
