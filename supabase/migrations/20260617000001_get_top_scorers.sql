-- Función que retorna ranking de goleadores directamente desde home_scorers/away_scorers.
-- Usa UNNEST para contar apariciones (un jugador que mete 2 goles aparece 2 veces en el string).

CREATE OR REPLACE FUNCTION get_top_scorers()
RETURNS TABLE(player_name TEXT, team_name TEXT, team_flag TEXT, goals BIGINT)
LANGUAGE sql SECURITY DEFINER AS $$
  SELECT
    scorer AS player_name,
    s.team_name,
    COALESCE(t.flag, '') AS team_flag,
    COUNT(*) AS goals
  FROM (
    SELECT
      TRIM(UNNEST(string_to_array(m.home_scorers, ','))) AS scorer,
      m.home_team AS team_name
    FROM matches m
    WHERE m.status = 'FINALIZADO'
      AND m.home_scorers IS NOT NULL
      AND m.home_scorers <> ''
    UNION ALL
    SELECT
      TRIM(UNNEST(string_to_array(m.away_scorers, ','))) AS scorer,
      m.away_team AS team_name
    FROM matches m
    WHERE m.status = 'FINALIZADO'
      AND m.away_scorers IS NOT NULL
      AND m.away_scorers <> ''
  ) s
  LEFT JOIN teams t ON t.name = s.team_name
  WHERE s.scorer <> ''
  GROUP BY scorer, s.team_name, t.flag
  ORDER BY goals DESC, player_name;
$$;

GRANT EXECUTE ON FUNCTION get_top_scorers() TO authenticated, anon;
