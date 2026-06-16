-- Permitir que service role (Edge Functions) llame set_result sin auth.uid().
-- Si hay uid → debe ser admin. Si no hay uid → es service role, se permite.

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
  -- Si hay usuario autenticado, verificar que sea admin.
  -- Si no hay uid (llamada desde service role / Edge Function), permitir.
  IF v_uid IS NOT NULL THEN
    SELECT is_admin INTO v_is_admin FROM profiles WHERE auth_user_id = v_uid LIMIT 1;
    IF NOT COALESCE(v_is_admin, FALSE) THEN RETURN 'NOT_ADMIN'; END IF;
  END IF;

  SELECT * INTO v_match FROM matches WHERE id = p_match_id;
  IF v_match.id IS NULL THEN RETURN 'MATCH_NOT_FOUND'; END IF;

  v_winner := winner_side(p_home, p_away);

  UPDATE matches SET
    home_goals     = p_home,
    away_goals     = p_away,
    home_scorers   = p_home_scorers,
    away_scorers   = p_away_scorers,
    winner_side    = v_winner,
    status         = 'FINALIZADO'
  WHERE id = p_match_id;

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
