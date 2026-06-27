-- Agrega submitted por predicción individual.
-- Permite bloquear partidos uno a uno en fases eliminatorias,
-- sin necesidad de enviar toda la fase de golpe.

ALTER TABLE predictions ADD COLUMN IF NOT EXISTS submitted BOOLEAN DEFAULT FALSE;

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
BEGIN
  SELECT id INTO v_profile_id FROM profiles WHERE auth_user_id = v_uid LIMIT 1;
  IF v_profile_id IS NULL THEN RETURN 'NOT_AUTHENTICATED'; END IF;

  -- Bloqueo de fase completa (retrocompat con Grupos ya enviados)
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

    -- Saltar predicciones ya enviadas individualmente
    IF EXISTS (
      SELECT 1 FROM predictions
      WHERE participant_id = v_profile_id AND match_id = v_match.id AND submitted = TRUE
    ) THEN CONTINUE; END IF;

    -- Saltar si pasó el deadline
    IF v_match.deadline_at IS NOT NULL AND NOW() > v_match.deadline_at THEN
      CONTINUE;
    END IF;

    INSERT INTO predictions (participant_id, match_id, home_goals, away_goals, updated_at, submitted)
      VALUES (
        v_profile_id,
        v_match.id,
        (v_item->>'home_goals')::INT,
        (v_item->>'away_goals')::INT,
        NOW(),
        p_final
      )
    ON CONFLICT (participant_id, match_id) DO UPDATE
      SET home_goals  = EXCLUDED.home_goals,
          away_goals  = EXCLUDED.away_goals,
          updated_at  = NOW(),
          submitted   = CASE WHEN p_final THEN TRUE ELSE predictions.submitted END;
  END LOOP;

  RETURN 'OK';
END;
$$;
