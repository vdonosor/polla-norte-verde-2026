-- ============================================================
-- POLLA NORTE VERDE 2026 — create_pin_user
-- Migración 007: Crea el usuario Auth directamente en auth.users
-- (evita el flujo signUp que puede fallar por configuración SMTP).
-- Vincula el perfil migrado en la misma transacción.
-- Permite ser llamada por anon (antes de autenticarse).
-- ============================================================

CREATE OR REPLACE FUNCTION create_pin_user(p_profile_id INT, p_pin TEXT)
RETURNS JSON LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_profile profiles%ROWTYPE;
  v_email   TEXT;
  v_uid     UUID;
BEGIN
  IF p_pin !~ '^[0-9]{4}$' THEN
    RETURN json_build_object('error', 'INVALID_PIN');
  END IF;

  v_email := 'profile' || p_profile_id || '@nortverde.app';

  -- Si ya existe cuenta con ese email, retornar ok para que el frontend haga signIn
  IF EXISTS (SELECT 1 FROM auth.users WHERE email = v_email) THEN
    RETURN json_build_object('ok', TRUE, 'existing', TRUE);
  END IF;

  SELECT * INTO v_profile FROM profiles
  WHERE id = p_profile_id AND auth_user_id IS NULL;
  IF v_profile.id IS NULL THEN
    RETURN json_build_object('error', 'PROFILE_NOT_AVAILABLE');
  END IF;

  v_uid := gen_random_uuid();

  INSERT INTO auth.users (
    id, aud, role, email,
    encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at,
    is_sso_user
  ) VALUES (
    v_uid, 'authenticated', 'authenticated', v_email,
    crypt('Pf26#' || p_pin, gen_salt('bf')),
    NOW(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object('profile_id', p_profile_id),
    NOW(), NOW(),
    FALSE
  );

  UPDATE profiles SET auth_user_id = v_uid, has_pin = TRUE
  WHERE id = p_profile_id AND auth_user_id IS NULL;

  RETURN json_build_object('ok', TRUE);
EXCEPTION
  WHEN not_null_violation THEN
    -- Si falta alguna columna obligatoria, reintentar sin is_sso_user
    BEGIN
      v_uid := gen_random_uuid();
      INSERT INTO auth.users (
        id, aud, role, email,
        encrypted_password, email_confirmed_at,
        raw_app_meta_data, raw_user_meta_data,
        created_at, updated_at
      ) VALUES (
        v_uid, 'authenticated', 'authenticated', v_email,
        crypt('Pf26#' || p_pin, gen_salt('bf')),
        NOW(),
        '{"provider":"email","providers":["email"]}'::jsonb,
        jsonb_build_object('profile_id', p_profile_id),
        NOW(), NOW()
      );
      UPDATE profiles SET auth_user_id = v_uid, has_pin = TRUE
      WHERE id = p_profile_id AND auth_user_id IS NULL;
      RETURN json_build_object('ok', TRUE);
    EXCEPTION WHEN OTHERS THEN
      RETURN json_build_object('error', SQLERRM);
    END;
  WHEN OTHERS THEN
    RETURN json_build_object('error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION create_pin_user TO anon;
