-- Recalcula players.goals contando apariciones en home_scorers/away_scorers.
-- Usa matching sin acentos: primer y último nombre de ESPN deben aparecer
-- en el nombre completo de la DB (ej. "Kylian Mbappé" → "Kylian Mbappe Lottin").

CREATE EXTENSION IF NOT EXISTS unaccent;

GRANT EXECUTE ON FUNCTION refresh_player_goals() TO authenticated;

CREATE OR REPLACE FUNCTION refresh_player_goals()
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE players p
  SET goals = (
    SELECT COUNT(*)
    FROM (
      SELECT TRIM(UNNEST(string_to_array(m.home_scorers, ','))) AS scorer
      FROM matches m
      WHERE m.status = 'FINALIZADO'
        AND m.home_scorers IS NOT NULL AND m.home_scorers <> ''
      UNION ALL
      SELECT TRIM(UNNEST(string_to_array(m.away_scorers, ','))) AS scorer
      FROM matches m
      WHERE m.status = 'FINALIZADO'
        AND m.away_scorers IS NOT NULL AND m.away_scorers <> ''
    ) scored
    WHERE
      -- Primer nombre de ESPN aparece en nombre DB (sin acentos)
      unaccent(lower(p.name)) LIKE
        '%' || unaccent(lower(split_part(trim(scored.scorer), ' ', 1))) || '%'
      AND
      -- Último nombre de ESPN aparece en nombre DB (sin acentos)
      -- reverse() trick para obtener el último token
      unaccent(lower(p.name)) LIKE
        '%' || unaccent(lower(reverse(split_part(reverse(trim(scored.scorer)), ' ', 1)))) || '%'
  );
END;
$$;
