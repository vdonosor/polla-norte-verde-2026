#!/usr/bin/env python3
"""
Genera seed_data.sql a partir del archivo xlsx de Polla Norte Verde.
Uso: python3 scripts/generate_seed.py
Salida: supabase/migrations/20260615000004_seed_data.sql
"""

import zipfile, xml.etree.ElementTree as ET
from datetime import datetime, timedelta, timezone
import os, re

XLSX_PATH = os.path.join(os.path.dirname(__file__), '..', '..', 'Claude Polla', 'Polla NV 2.0.xlsx')
OUT_PATH  = os.path.join(os.path.dirname(__file__), '..', 'supabase', 'migrations', '20260615000004_seed_data.sql')

# ── Banderas por equipo ────────────────────────────────────────
FLAGS = {
    'México': '🇲🇽', 'Sudáfrica': '🇿🇦', 'Rep. Corea': '🇰🇷', 'Chequia': '🇨🇿',
    'Canadá': '🇨🇦', 'Bosnia y Herz.': '🇧🇦', 'Catar': '🇶🇦', 'Suiza': '🇨🇭',
    'Brasil': '🇧🇷', 'Marruecos': '🇲🇦', 'Haití': '🇭🇹', 'Escocia': '🏴󠁧󠁢󠁳󠁣󠁴󠁿',
    'EE.UU.': '🇺🇸', 'Paraguay': '🇵🇾', 'Australia': '🇦🇺', 'Turquía': '🇹🇷',
    'Alemania': '🇩🇪', 'Curazao': '🇨🇼', 'Costa de Marfil': '🇨🇮', 'Ecuador': '🇪🇨',
    'Países Bajos': '🇳🇱', 'Japón': '🇯🇵', 'Suecia': '🇸🇪', 'Túnez': '🇹🇳',
    'Bélgica': '🇧🇪', 'Egipto': '🇪🇬', 'RI de Irán': '🇮🇷', 'Nueva Zelanda': '🇳🇿',
    'España': '🇪🇸', 'Islas de Cabo Verde': '🇨🇻', 'Arabia Saudí': '🇸🇦', 'Uruguay': '🇺🇾',
    'Francia': '🇫🇷', 'Senegal': '🇸🇳', 'Irak': '🇮🇶', 'Noruega': '🇳🇴',
    'Argentina': '🇦🇷', 'Argelia': '🇩🇿', 'Austria': '🇦🇹', 'Jordania': '🇯🇴',
    'Portugal': '🇵🇹', 'RD Congo': '🇨🇩', 'Uzbekistán': '🇺🇿', 'Colombia': '🇨🇴',
    'Inglaterra': '🏴󠁧󠁢󠁥󠁮󠁧󠁿', 'Croacia': '🇭🇷', 'Ghana': '🇬🇭', 'Panamá': '🇵🇦',
}

# ── Leer xlsx ──────────────────────────────────────────────────
def get_shared_strings(z):
    ns = {'m': 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}
    ss = ET.parse(z.open('xl/sharedStrings.xml'))
    return [''.join(t.text or '' for t in si.findall('.//m:t', ns))
            for si in ss.findall('.//m:si', ns)]

def read_sheet(z, sheet_num, shared, skip_rows=1):
    ns = {'m': 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}
    ws = ET.parse(z.open(f'xl/worksheets/sheet{sheet_num}.xml'))
    rows = []
    for i, row in enumerate(ws.findall('.//m:row', ns)):
        if i < skip_rows:
            continue
        cells = []
        last_col = 0
        for c in row.findall('m:c', ns):
            # Column reference (A=0, B=1, ...)
            col_ref = c.get('r', 'A1')
            col_letters = re.match(r'([A-Z]+)', col_ref).group(1)
            col_num = sum((ord(ch) - 64) * (26 ** i) for i, ch in enumerate(reversed(col_letters))) - 1
            # Fill gaps with empty string
            while last_col < col_num:
                cells.append('')
                last_col += 1
            t = c.get('t', '')
            v = c.find('m:v', ns)
            if v is None or v.text is None:
                cells.append('')
            elif t == 's':
                cells.append(shared[int(v.text)])
            else:
                cells.append(v.text)
            last_col += 1
        rows.append(cells)
    return rows

def excel_date_to_iso(serial_str, time_fraction_str='0'):
    try:
        serial = float(serial_str)
        frac   = float(time_fraction_str) if time_fraction_str else 0.0
        base = datetime(1899, 12, 30, tzinfo=timezone.utc)
        dt = base + timedelta(days=serial + frac)
        return dt.strftime('%Y-%m-%dT%H:%M:%SZ')
    except Exception:
        return None

def esc(s):
    if s is None or s == '' or s == '-':
        return 'NULL'
    return "'" + str(s).replace("'", "''") + "'"

def int_or_null(s):
    try:
        return str(int(float(s)))
    except Exception:
        return 'NULL'

# ── Main ────────────────────────────────────────────────────────
with zipfile.ZipFile(XLSX_PATH) as z:
    shared  = get_shared_strings(z)
    fixture = read_sheet(z, 2, shared, skip_rows=1)    # sheet2 = fixture
    users   = read_sheet(z, 3, shared, skip_rows=1)    # sheet3 = usuarios
    preds   = read_sheet(z, 4, shared, skip_rows=2)    # sheet4 = predicciones (skip header + team-name row)
    extras  = read_sheet(z, 5, shared, skip_rows=1)    # sheet5 = extras
    results = read_sheet(z, 6, shared, skip_rows=1)    # sheet6 = resultados
    players_raw = read_sheet(z, 8, shared, skip_rows=1) # sheet8 = jugadores

lines = []
lines.append("-- ============================================================")
lines.append("-- POLLA NORTE VERDE 2026 — SEED DATA")
lines.append("-- Migración 004: Datos reales del torneo en curso")
lines.append(f"-- Generado: {datetime.now().strftime('%Y-%m-%d %H:%M')}")
lines.append("-- ============================================================")
lines.append("")

# ── 1. EQUIPOS ─────────────────────────────────────────────────
lines.append("-- ── EQUIPOS ──────────────────────────────────────────────────")
teams_seen = {}
team_to_group = {}
for row in fixture:
    if len(row) < 8:
        continue
    _, grupo, fase, local, visita, *_ = row + [''] * 10
    if fase != 'Grupos':
        continue
    for t in [local, visita]:
        if t and t not in teams_seen:
            teams_seen[t] = len(teams_seen) + 1
        if t and t not in team_to_group:
            team_to_group[t] = grupo

for name, tid in sorted(teams_seen.items(), key=lambda x: x[1]):
    flag  = FLAGS.get(name, '')
    group = team_to_group.get(name, '')
    lines.append(f"INSERT INTO teams (id, name, flag, group_name) VALUES ({tid}, {esc(name)}, {esc(flag)}, {esc(group)});")

lines.append(f"SELECT setval('teams_id_seq', {max(teams_seen.values())});")
lines.append("")

# ── 2. PARTIDOS ─────────────────────────────────────────────────
lines.append("-- ── PARTIDOS ─────────────────────────────────────────────────")
phase_map = {
    'Grupos': 'Grupos', '16avos': '16avos', '8vos': '8vos',
    '4tos': '4tos', 'Semis': 'Semis', '3er lugar': '3er lugar', 'Final': 'Final'
}

for row in fixture:
    if len(row) < 9:
        continue
    match_id_s, grupo, fase, local, visita, fecha_s, hora_s, estadio, deadline_s, *rest = row + [''] * 5
    habilitado = rest[0] if rest else '1'

    match_num = int_or_null(match_id_s)
    if match_num == 'NULL':
        continue

    ph = phase_map.get(fase, 'Grupos')

    # kickoff_at: fecha + hora (ambos son seriales Excel)
    kickoff = excel_date_to_iso(fecha_s, hora_s)
    deadline = excel_date_to_iso(deadline_s, '0') if deadline_s else 'NULL'

    home_id = teams_seen.get(local, 'NULL')
    away_id = teams_seen.get(visita, 'NULL')
    enabled = '1' if habilitado == '1' else '0'

    lines.append(
        f"INSERT INTO matches (match_number, phase, group_name, home_team, away_team, "
        f"home_team_id, away_team_id, kickoff_at, deadline_at, stadium, enabled) VALUES ("
        f"{match_num}, '{ph}'::{{}}, {esc(grupo)}, {esc(local)}, {esc(visita)}, "
        f"{home_id if isinstance(home_id, int) else 'NULL'}, "
        f"{away_id if isinstance(away_id, int) else 'NULL'}, "
        f"{esc(kickoff) if kickoff else 'NULL'}, "
        f"{esc(deadline) if deadline else 'NULL'}, "
        f"{esc(estadio)}, {enabled});"
    )

lines.append(f"SELECT setval('matches_id_seq', 104);")
lines.append("")

# Fix: replace placeholder for phase cast
full = '\n'.join(lines)
full = full.replace("'{}'::", "'match_phase'::")  # placeholder trick didn't work, fix below

lines = []
lines.append("-- ============================================================")
lines.append("-- POLLA NORTE VERDE 2026 — SEED DATA")
lines.append("-- Migración 004: Datos reales del torneo en curso")
lines.append(f"-- Generado: {datetime.now().strftime('%Y-%m-%d %H:%M')}")
lines.append("-- ============================================================")
lines.append("")

# ── 1. EQUIPOS (segunda pasada limpia) ─────────────────────────
lines.append("-- ── EQUIPOS ──────────────────────────────────────────────────")
for name, tid in sorted(teams_seen.items(), key=lambda x: x[1]):
    flag  = FLAGS.get(name, '')
    group = team_to_group.get(name, '')
    lines.append(f"INSERT INTO teams (id, name, flag, group_name) VALUES ({tid}, {esc(name)}, {esc(flag)}, {esc(group)});")
lines.append(f"SELECT setval('teams_id_seq', {max(teams_seen.values())});")
lines.append("")

# ── 2. PARTIDOS (segunda pasada limpia) ────────────────────────
lines.append("-- ── PARTIDOS ─────────────────────────────────────────────────")
for row in fixture:
    if len(row) < 9:
        continue
    match_id_s, grupo, fase, local, visita, fecha_s, hora_s, estadio, deadline_s, *rest = row + [''] * 5
    habilitado = rest[0] if rest else '1'
    match_num = int_or_null(match_id_s)
    if match_num == 'NULL':
        continue
    ph = phase_map.get(fase, 'Grupos')
    kickoff  = excel_date_to_iso(fecha_s, hora_s)
    deadline = excel_date_to_iso(deadline_s, '0') if deadline_s else None
    home_id  = teams_seen.get(local)
    away_id  = teams_seen.get(visita)
    enabled  = 'TRUE' if habilitado == '1' else 'FALSE'
    lines.append(
        f"INSERT INTO matches (match_number, phase, group_name, home_team, away_team, "
        f"home_team_id, away_team_id, kickoff_at, deadline_at, stadium, enabled) VALUES ("
        f"{match_num}, '{ph}'::match_phase, {esc(grupo)}, {esc(local)}, {esc(visita)}, "
        f"{home_id if home_id else 'NULL'}, "
        f"{away_id if away_id else 'NULL'}, "
        f"{'NULL' if not kickoff else esc(kickoff)}, "
        f"{'NULL' if not deadline else esc(deadline)}, "
        f"{esc(estadio)}, {enabled});"
    )
lines.append("SELECT setval('matches_id_seq', 104);")
lines.append("")

# ── 3. JUGADORES ────────────────────────────────────────────────
lines.append("-- ── JUGADORES ─────────────────────────────────────────────────")
for row in players_raw:
    if len(row) < 4:
        continue
    pais, nombre, posicion, numero, *stats = row + ['0'] * 6
    if not nombre or nombre == '-':
        continue
    team_id = teams_seen.get(pais)
    if not team_id:
        continue
    goles      = int_or_null(stats[1] if len(stats) > 1 else '0')
    asistencias= int_or_null(stats[2] if len(stats) > 2 else '0')
    amarillas  = int_or_null(stats[3] if len(stats) > 3 else '0')
    rojas      = int_or_null(stats[4] if len(stats) > 4 else '0')
    lines.append(
        f"INSERT INTO players (team_id, name, position, number, goals, assists, yellow_cards, red_cards) VALUES ("
        f"{team_id}, {esc(nombre)}, {esc(posicion)}, {int_or_null(numero)}, "
        f"{goles if goles != 'NULL' else 0}, "
        f"{asistencias if asistencias != 'NULL' else 0}, "
        f"{amarillas if amarillas != 'NULL' else 0}, "
        f"{rojas if rojas != 'NULL' else 0});"
    )
lines.append("")

# ── 4. PERFILES ──────────────────────────────────────────────────
lines.append("-- ── PERFILES ───────────────────────────────────────────────────")
lines.append("-- NOTA: auth_user_id queda NULL. Cada usuario lo vincula al crear su PIN.")
user_to_id  = {}
admin_email = 'vdonoso@reity.cl'  # Vicente es admin
for i, row in enumerate(users):
    if len(row) < 2:
        continue
    email, nombre, *rest = row + [''] * 5
    if not email or not nombre:
        continue
    profile_id = i + 1
    user_to_id[email] = profile_id
    is_admin = 'TRUE' if email == admin_email else 'FALSE'
    lines.append(
        f"INSERT INTO profiles (id, name, is_admin, can_submit, legacy_email) VALUES ("
        f"{profile_id}, {esc(nombre)}, {is_admin}, TRUE, {esc(email)});"
    )
lines.append(f"SELECT setval('profiles_id_seq', {len(user_to_id)});")
lines.append("")

# ── 5. PREDICCIONES ─────────────────────────────────────────────
lines.append("-- ── PREDICCIONES ───────────────────────────────────────────────")
lines.append("-- Predicciones de fase de grupos (partidos 1-72)")
for row in preds:
    if len(row) < 2:
        continue
    email = row[0]
    profile_id = user_to_id.get(email)
    if not profile_id:
        continue
    # Columnas: email, P1_L, P1_V, P2_L, P2_V, ... P79_L, P79_V
    pred_values = row[1:]
    for match_i in range(min(72, len(pred_values) // 2)):
        col_l = match_i * 2
        col_v = match_i * 2 + 1
        if col_v >= len(pred_values):
            break
        gl_s = pred_values[col_l]
        gv_s = pred_values[col_v]
        if not gl_s or gl_s == '-' or not gv_s or gv_s == '-':
            continue
        try:
            gl = int(float(gl_s))
            gv = int(float(gv_s))
        except ValueError:
            continue
        match_num = match_i + 1
        lines.append(
            f"INSERT INTO predictions (participant_id, match_id, home_goals, away_goals) "
            f"SELECT {profile_id}, id, {gl}, {gv} FROM matches WHERE match_number = {match_num} "
            f"ON CONFLICT DO NOTHING;"
        )
lines.append("")

# ── 6. BONUS ─────────────────────────────────────────────────────
lines.append("-- ── BONUS PREDICTIONS ──────────────────────────────────────────")
for row in extras:
    if len(row) < 2:
        continue
    email, goleador, mvp, fin1, fin2, *_ = row + [''] * 5
    profile_id = user_to_id.get(email)
    if not profile_id:
        continue
    if not any([goleador, mvp, fin1, fin2]):
        continue
    lines.append(
        f"INSERT INTO bonus_predictions (participant_id, top_scorer_name, mvp_name, finalist1_name, finalist2_name) "
        f"VALUES ({profile_id}, {esc(goleador)}, {esc(mvp)}, {esc(fin1)}, {esc(fin2)}) "
        f"ON CONFLICT DO NOTHING;"
    )
lines.append("")

# ── 7. PHASE SUBMISSIONS ─────────────────────────────────────────
lines.append("-- ── PHASE SUBMISSIONS (grupos enviados) ────────────────────────")
for i, row in enumerate(users):
    if len(row) < 5:
        continue
    email, nombre, *flags = row + ['0'] * 10
    profile_id = user_to_id.get(email)
    if not profile_id:
        continue
    # flags[2] = env_grupos (col index 4, offset 2 after email+nombre+fecha+activo)
    # row: email(0) nombre(1) fecha(2) activo(3) env_grupos(4) env_16avos(5)...
    env_grupos = flags[2] if len(flags) > 2 else '0'
    if env_grupos == '1':
        lines.append(
            f"INSERT INTO phase_submissions (participant_id, phase) "
            f"VALUES ({profile_id}, 'Grupos'::match_phase) ON CONFLICT DO NOTHING;"
        )
lines.append("")

# ── 8. RESULTADOS ────────────────────────────────────────────────
lines.append("-- ── RESULTADOS (partidos ya jugados) ───────────────────────────")
for row in results:
    if len(row) < 9:
        continue
    match_id_s, fase, local, visita, gl_s, gv_s, gol_local, gol_visita, finalizado_s, *_ = row + [''] * 5
    match_num = int_or_null(match_id_s)
    if match_num == 'NULL':
        continue
    finalizado = finalizado_s == '1'
    if not finalizado:
        continue
    try:
        gl = int(float(gl_s))
        gv = int(float(gv_s))
    except ValueError:
        continue
    if gl > gv:
        winner = 'home'
    elif gv > gl:
        winner = 'away'
    else:
        winner = 'draw'
    lines.append(
        f"UPDATE matches SET "
        f"home_goals = {gl}, away_goals = {gv}, "
        f"home_scorers = {esc(gol_local)}, away_scorers = {esc(gol_visita)}, "
        f"winner_side = '{winner}', status = 'FINALIZADO'::match_status "
        f"WHERE match_number = {match_num};"
    )
lines.append("")

# ── 9. RECALCULAR PUNTOS (llamada post-seed) ─────────────────────
lines.append("-- ── RECALCULAR PUNTOS ─────────────────────────────────────────")
lines.append("-- Ejecutar esta función por cada partido finalizado para calcular los puntos")
lines.append("-- NOTA: set_result() requiere auth admin. Usar la función interna directamente:")
lines.append("")
lines.append("DO $$")
lines.append("DECLARE")
lines.append("  v_match matches%ROWTYPE;")
lines.append("  v_pred  predictions%ROWTYPE;")
lines.append("  v_exact BOOLEAN;")
lines.append("  v_correct BOOLEAN;")
lines.append("  v_pts INT;")
lines.append("BEGIN")
lines.append("  FOR v_match IN SELECT * FROM matches WHERE status = 'FINALIZADO' LOOP")
lines.append("    FOR v_pred IN SELECT * FROM predictions WHERE match_id = v_match.id LOOP")
lines.append("      v_exact := (v_pred.home_goals = v_match.home_goals AND v_pred.away_goals = v_match.away_goals);")
lines.append("      v_correct := (")
lines.append("        CASE WHEN v_pred.home_goals > v_pred.away_goals THEN 'home'")
lines.append("             WHEN v_pred.away_goals > v_pred.home_goals THEN 'away'")
lines.append("             ELSE 'draw' END")
lines.append("        = v_match.winner_side);")
lines.append("      IF v_exact THEN")
lines.append("        v_pts := CASE v_match.phase")
lines.append("          WHEN 'Grupos' THEN 2 WHEN '16avos' THEN 3 WHEN '8vos' THEN 3")
lines.append("          WHEN '4tos' THEN 4 WHEN 'Semis' THEN 5 WHEN '3er lugar' THEN 5")
lines.append("          WHEN 'Final' THEN 6 END;")
lines.append("      ELSIF v_correct THEN")
lines.append("        v_pts := CASE v_match.phase")
lines.append("          WHEN 'Grupos' THEN 1 WHEN '16avos' THEN 1 WHEN '8vos' THEN 1")
lines.append("          WHEN '4tos' THEN 2 WHEN 'Semis' THEN 3 WHEN '3er lugar' THEN 3")
lines.append("          WHEN 'Final' THEN 4 END;")
lines.append("      ELSE v_pts := 0;")
lines.append("      END IF;")
lines.append("      UPDATE predictions SET points = v_pts, is_exact = v_exact WHERE id = v_pred.id;")
lines.append("    END LOOP;")
lines.append("  END LOOP;")
lines.append("END;")
lines.append("$$;")
lines.append("")
lines.append("-- ── FIN SEED DATA ───────────────────────────────────────────────")

os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
with open(OUT_PATH, 'w', encoding='utf-8') as f:
    f.write('\n'.join(lines))

print(f"✓ Generado: {OUT_PATH}")
print(f"  Equipos:       {len(teams_seen)}")
print(f"  Partidos:      {len(fixture)}")
print(f"  Jugadores:     {len(players_raw)}")
print(f"  Perfiles:      {len(user_to_id)}")
print(f"  Predicciones:  estimadas ~{len(user_to_id) * 72}")
print(f"  Bonus:         {len(extras)}")
