-- ============================================================
-- POLLA NORTE VERDE 2026 — register_profile v2
-- Migración 006: Actualiza register_profile para manejar
-- perfiles migrados (auth_user_id=NULL) usando el profile_id
-- pasado como metadata en el signUp del frontend.
--
-- Lógica:
--   1. Perfil ya vinculado a este auth.uid() → retornarlo
--   2. profile_id en raw_user_meta_data → vincular y retornar
--   3. Sin match → crear perfil nuevo (requiere p_name)
-- ============================================================

CREATE OR REPLACE FUNCTION register_profile(p_name TEXT DEFAULT NULL)
RETURNS JSON LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_uid     UUID := auth.uid();
  v_profile profiles%ROWTYPE;
  v_meta_id INT;
BEGIN
  IF v_uid IS NULL THEN
    RETURN json_build_object('error', 'NOT_AUTHENTICATED');
  END IF;

  -- 1. Perfil ya vinculado
  SELECT * INTO v_profile FROM profiles WHERE auth_user_id = v_uid LIMIT 1;
  IF v_profile.id IS NOT NULL THEN
    RETURN json_build_object(
      'id',         v_profile.id,
      'name',       v_profile.name,
      'is_admin',   v_profile.is_admin,
      'can_submit', v_profile.can_submit,
      'avatar_url', v_profile.avatar_url
    );
  END IF;

  -- 2. Vincular perfil migrado usando metadata del signUp
  SELECT (raw_user_meta_data->>'profile_id')::INT
  INTO v_meta_id FROM auth.users WHERE id = v_uid;

  IF v_meta_id IS NOT NULL THEN
    UPDATE profiles
      SET auth_user_id = v_uid, has_pin = TRUE
    WHERE id = v_meta_id AND auth_user_id IS NULL
    RETURNING * INTO v_profile;

    IF v_profile.id IS NOT NULL THEN
      RETURN json_build_object(
        'id',         v_profile.id,
        'name',       v_profile.name,
        'is_admin',   v_profile.is_admin,
        'can_submit', v_profile.can_submit,
        'avatar_url', v_profile.avatar_url
      );
    END IF;
  END IF;

  -- 3. Crear perfil nuevo
  IF p_name IS NULL THEN
    RETURN json_build_object('error', 'NAME_REQUIRED');
  END IF;

  INSERT INTO profiles (name, auth_user_id, has_pin)
  VALUES (p_name, v_uid, TRUE)
  RETURNING * INTO v_profile;

  RETURN json_build_object(
    'id',         v_profile.id,
    'name',       v_profile.name,
    'is_admin',   v_profile.is_admin,
    'can_submit', v_profile.can_submit,
    'avatar_url', v_profile.avatar_url
  );
END;
$$;
