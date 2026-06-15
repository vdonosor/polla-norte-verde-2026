-- ============================================================
-- POLLA NORTE VERDE 2026 — LINK PROFILE FUNCTION
-- Migración 005: Vincula un perfil migrado (auth_user_id=NULL)
-- con la cuenta de Supabase Auth recién creada por el usuario.
-- Ya ejecutada directamente en Supabase; este archivo es el
-- registro en control de versiones.
-- ============================================================

CREATE OR REPLACE FUNCTION link_profile(p_profile_id INT)
RETURNS JSON LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_uid     UUID := auth.uid();
  v_profile profiles%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RETURN json_build_object('error', 'NOT_AUTHENTICATED');
  END IF;

  -- Solo vincula si el perfil aún no tiene auth_user_id (no permite robo de perfil)
  UPDATE profiles
    SET auth_user_id = v_uid, has_pin = TRUE
  WHERE id = p_profile_id AND auth_user_id IS NULL
  RETURNING * INTO v_profile;

  IF v_profile.id IS NULL THEN
    RETURN json_build_object('error', 'PROFILE_NOT_FOUND_OR_TAKEN');
  END IF;

  RETURN json_build_object(
    'id',         v_profile.id,
    'name',       v_profile.name,
    'is_admin',   v_profile.is_admin,
    'can_submit', v_profile.can_submit,
    'avatar_url', v_profile.avatar_url
  );
END;
$$;
