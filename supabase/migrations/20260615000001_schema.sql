-- ============================================================
-- POLLA NORTE VERDE 2026 — SCHEMA COMPLETO
-- Migración 001: Tablas, tipos, vistas
-- ============================================================

-- Tipos ENUM
CREATE TYPE match_phase AS ENUM (
  'Grupos', '16avos', '8vos', '4tos', 'Semis', '3er lugar', 'Final'
);

CREATE TYPE match_status AS ENUM (
  'PROGRAMADO', 'EN_JUEGO', 'FINALIZADO'
);

-- ── EQUIPOS ──────────────────────────────────────────────────
CREATE TABLE teams (
  id   SERIAL PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  flag TEXT,
  group_name TEXT
);

-- ── JUGADORES ─────────────────────────────────────────────────
CREATE TABLE players (
  id            SERIAL PRIMARY KEY,
  team_id       INT REFERENCES teams(id) ON DELETE CASCADE,
  name          TEXT NOT NULL,
  position      TEXT,         -- GK, DF, MF, FW
  number        INT,
  goals         INT DEFAULT 0,
  assists       INT DEFAULT 0,
  yellow_cards  INT DEFAULT 0,
  red_cards     INT DEFAULT 0,
  api_player_id INT
);

-- ── PERFILES (usuarios de la polla) ──────────────────────────
CREATE TABLE profiles (
  id           SERIAL PRIMARY KEY,
  name         TEXT NOT NULL,
  avatar_url   TEXT,          -- base64 o URL
  has_pin      BOOLEAN DEFAULT FALSE,
  is_admin     BOOLEAN DEFAULT FALSE,
  can_submit   BOOLEAN DEFAULT TRUE,
  auth_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  legacy_email TEXT UNIQUE,   -- email del sistema anterior (solo para migración)
  created_at   TIMESTAMPTZ DEFAULT NOW()
);

-- ── PARTIDOS ──────────────────────────────────────────────────
CREATE TABLE matches (
  id             SERIAL PRIMARY KEY,
  match_number   INT UNIQUE NOT NULL,   -- 1..104 (numeración original)
  phase          match_phase NOT NULL,
  group_name     TEXT,                  -- A..L, NULL para eliminatorias
  home_team      TEXT NOT NULL,         -- nombre del equipo (o "1º Grupo A")
  away_team      TEXT NOT NULL,
  home_team_id   INT REFERENCES teams(id),
  away_team_id   INT REFERENCES teams(id),
  kickoff_at     TIMESTAMPTZ,
  deadline_at    TIMESTAMPTZ,
  stadium        TEXT,
  enabled        BOOLEAN DEFAULT FALSE,
  status         match_status DEFAULT 'PROGRAMADO',
  live_clock     INT,                   -- minuto en vivo
  home_goals     INT,
  away_goals     INT,
  home_scorers   TEXT,
  away_scorers   TEXT,
  winner_side    TEXT,                  -- 'home' | 'away' | 'draw'
  api_fixture_id INT
);

-- ── PREDICCIONES ──────────────────────────────────────────────
CREATE TABLE predictions (
  id             SERIAL PRIMARY KEY,
  participant_id INT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  match_id       INT NOT NULL REFERENCES matches(id) ON DELETE CASCADE,
  home_goals     INT NOT NULL,
  away_goals     INT NOT NULL,
  points         INT DEFAULT 0,
  is_exact       BOOLEAN DEFAULT FALSE,
  created_at     TIMESTAMPTZ DEFAULT NOW(),
  updated_at     TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(participant_id, match_id)
);

-- ── PREDICCIONES BONUS ────────────────────────────────────────
CREATE TABLE bonus_predictions (
  participant_id   INT PRIMARY KEY REFERENCES profiles(id) ON DELETE CASCADE,
  top_scorer_name  TEXT,    -- nombre del goleador predicho
  mvp_name         TEXT,    -- nombre del MVP predicho
  finalist1_name   TEXT,    -- nombre del finalista 1
  finalist2_name   TEXT,    -- nombre del finalista 2
  pts_top_scorer   INT DEFAULT 0,
  pts_mvp          INT DEFAULT 0,
  pts_finalists    INT DEFAULT 0
);

-- ── ENVÍOS POR FASE ───────────────────────────────────────────
-- Cuando un usuario "envía definitivo" una fase, se registra aquí y queda bloqueado
CREATE TABLE phase_submissions (
  participant_id INT REFERENCES profiles(id) ON DELETE CASCADE,
  phase          match_phase NOT NULL,
  submitted_at   TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY(participant_id, phase)
);

-- ── CONFIGURACIÓN DE LA APP ───────────────────────────────────
CREATE TABLE app_config (
  key   TEXT PRIMARY KEY,
  value TEXT
);

-- Valores iniciales de configuración
INSERT INTO app_config (key, value) VALUES
  ('predictions_visible', 'true'),
  ('submissions_open',    'false'),
  ('bonus_top_scorer',    '5'),
  ('bonus_mvp',           '5'),
  ('bonus_one_finalist',  '2'),
  ('bonus_both_finalists','6'),
  ('mvp_real',            ''),
  ('top_scorer_real',     ''),
  ('nombre_polla',        'Polla Norte Verde 2026');

-- ── SNAPSHOTS DE RANKING (para flechas ▲▼) ───────────────────
CREATE TABLE rank_snapshots (
  profile_id INT REFERENCES profiles(id) ON DELETE CASCADE,
  rank       INT NOT NULL,
  snap_date  DATE NOT NULL DEFAULT CURRENT_DATE,
  PRIMARY KEY(profile_id, snap_date)
);

-- ── VISTA: TABLA DE POSICIONES ─────────────────────────────────
CREATE VIEW leaderboard AS
SELECT
  p.id,
  p.name,
  p.avatar_url,
  p.is_admin,
  COALESCE(SUM(
    CASE WHEN m.phase = 'Grupos' THEN pr.points ELSE 0 END
  ), 0)::INT AS pts_grupos,
  COALESCE(SUM(
    CASE WHEN m.phase != 'Grupos' THEN pr.points ELSE 0 END
  ), 0)::INT AS pts_eliminatorias,
  COALESCE(
    (SELECT pts_top_scorer + pts_mvp + pts_finalists
     FROM bonus_predictions WHERE participant_id = p.id), 0
  )::INT AS pts_bonus,
  (
    COALESCE(SUM(pr.points), 0) +
    COALESCE(
      (SELECT pts_top_scorer + pts_mvp + pts_finalists
       FROM bonus_predictions WHERE participant_id = p.id), 0
    )
  )::INT AS pts_total,
  COALESCE(SUM(CASE WHEN pr.is_exact THEN 1 ELSE 0 END), 0)::INT AS exact_count
FROM profiles p
LEFT JOIN predictions pr ON pr.participant_id = p.id
LEFT JOIN matches m      ON m.id = pr.match_id
GROUP BY p.id, p.name, p.avatar_url, p.is_admin
ORDER BY pts_total DESC, exact_count DESC;

-- ── ÍNDICES ────────────────────────────────────────────────────
CREATE INDEX idx_predictions_participant ON predictions(participant_id);
CREATE INDEX idx_predictions_match       ON predictions(match_id);
CREATE INDEX idx_matches_phase           ON matches(phase);
CREATE INDEX idx_matches_status          ON matches(status);
CREATE INDEX idx_players_team            ON players(team_id);
