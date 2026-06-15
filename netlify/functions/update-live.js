// Actualiza marcadores desde ESPN API (sin API key).
// Llama este endpoint desde el panel admin o configura un cron.

const TEAM_MAP = {
  'Spain': 'España', 'Mexico': 'México', 'United States': 'EE.UU.', 'USA': 'EE.UU.',
  'Netherlands': 'Países Bajos', 'Germany': 'Alemania', 'France': 'Francia',
  'Brazil': 'Brasil', 'Argentina': 'Argentina', 'Portugal': 'Portugal',
  'England': 'Inglaterra', 'Morocco': 'Marruecos', 'Japan': 'Japón',
  'South Korea': 'Rep. Corea', 'Korea Republic': 'Rep. Corea', 'Sweden': 'Suecia',
  'Belgium': 'Bélgica', 'Tunisia': 'Túnez', 'Switzerland': 'Suiza',
  'Ecuador': 'Ecuador', 'Uruguay': 'Uruguay', 'Colombia': 'Colombia',
  'Australia': 'Australia', 'Turkey': 'Turquía', 'Türkiye': 'Turquía',
  'Iran': 'RI de Irán', 'IR Iran': 'RI de Irán', 'Senegal': 'Senegal',
  'Denmark': 'Dinamarca', 'Poland': 'Polonia', 'Croatia': 'Croacia',
  'Canada': 'Canadá', 'South Africa': 'Sudáfrica', 'Czech Republic': 'Chequia',
  'Czechia': 'Chequia', 'Qatar': 'Catar', 'Ivory Coast': 'Costa de Marfil',
  "Côte d'Ivoire": 'Costa de Marfil', "Cote d'Ivoire": 'Costa de Marfil',
  'Cape Verde': 'Islas de Cabo Verde', 'Curaçao': 'Curazao', 'Curacao': 'Curazao',
  'Haiti': 'Haití', 'Scotland': 'Escocia', 'Norway': 'Noruega',
  'New Zealand': 'Nueva Zelanda', 'Saudi Arabia': 'Arabia Saudí', 'Iraq': 'Irak',
  'Jordan': 'Jordania', 'Algeria': 'Argelia', 'DR Congo': 'RD Congo',
  'Uzbekistan': 'Uzbekistán', 'Ghana': 'Ghana', 'Panama': 'Panamá',
  'Bosnia and Herzegovina': 'Bosnia y Herz.', 'Bosnia & Herzegovina': 'Bosnia y Herz.',
  'Paraguay': 'Paraguay', 'Egypt': 'Egipto', 'Chile': 'Chile',
  'Peru': 'Perú', 'Bolivia': 'Bolivia', 'Venezuela': 'Venezuela',
  'Serbia': 'Serbia', 'Ukraine': 'Ucrania', 'Romania': 'Rumania',
  'Slovakia': 'Eslovaquia', 'Hungary': 'Hungría', 'Austria': 'Austria',
  'Greece': 'Grecia', 'Israel': 'Israel', 'Wales': 'Gales',
  'Northern Ireland': 'Irlanda del Norte', 'Ireland': 'Irlanda',
  'Finland': 'Finlandia', 'Iceland': 'Islandia',
};

function mapTeam(name) {
  return TEAM_MAP[name] || name;
}

exports.handler = async (event) => {
  const SB_URL = process.env.SUPABASE_URL || 'https://hugleolrwojikdqidesk.supabase.co';
  const SB_KEY = process.env.SUPABASE_SERVICE_KEY;

  if (!SB_KEY) {
    return { statusCode: 500, body: JSON.stringify({ error: 'Missing SUPABASE_SERVICE_KEY' }) };
  }

  const sbHeaders = {
    'apikey': SB_KEY,
    'Authorization': `Bearer ${SB_KEY}`,
    'Content-Type': 'application/json',
  };

  try {
    // 1. Obtener partidos activos de Supabase (enabled, no finalizados aún)
    const matchRes = await fetch(
      `${SB_URL}/rest/v1/matches?enabled=eq.true&select=id,home_team,away_team,status&order=match_number`,
      { headers: sbHeaders }
    );
    const supaMatches = await matchRes.json();

    // 2. Obtener marcadores de ESPN
    const espnRes = await fetch(
      'https://site.api.espn.com/apis/site/v2/sports/soccer/fifa.world/scoreboard',
      { headers: { 'Accept': 'application/json' } }
    );
    if (!espnRes.ok) {
      return { statusCode: 502, body: JSON.stringify({ error: 'ESPN API error: ' + espnRes.status }) };
    }
    const espnData = await espnRes.json();
    const events = espnData.events || [];

    const results = [];
    let updated = 0;

    for (const supaMatch of supaMatches) {
      // Buscar partido en ESPN por nombres de equipo
      const espnEvent = events.find(e => {
        const comp = e.competitions?.[0];
        if (!comp) return false;
        const home = comp.competitors?.find(c => c.homeAway === 'home');
        const away = comp.competitors?.find(c => c.homeAway === 'away');
        if (!home || !away) return false;
        const hn = mapTeam(home.team?.displayName || '');
        const an = mapTeam(away.team?.displayName || '');
        return hn === supaMatch.home_team && an === supaMatch.away_team;
      });

      if (!espnEvent) continue;

      const comp = espnEvent.competitions[0];
      const homeComp = comp.competitors.find(c => c.homeAway === 'home');
      const awayComp = comp.competitors.find(c => c.homeAway === 'away');
      const homeScore = parseInt(homeComp?.score) || 0;
      const awayScore = parseInt(awayComp?.score) || 0;

      const espnStatus = espnEvent.status?.type?.name || '';
      const isFinal  = espnStatus === 'STATUS_FINAL' || espnStatus === 'STATUS_FULL_TIME' || espnEvent.status?.type?.completed;
      const isLive   = espnStatus === 'STATUS_IN_PROGRESS' || espnStatus === 'STATUS_HALFTIME';
      const clock    = espnEvent.status?.displayClock || null;

      if (isFinal && supaMatch.status !== 'FINALIZADO') {
        // Calcular puntos vía set_result
        // Intentar extraer goleadores del ESPN (si están disponibles)
        let homeScorers = '';
        let awayScorers = '';
        try {
          const detail = comp.details || [];
          const hGoals = detail.filter(d => d.type?.text === 'Goal' && d.team?.id === homeComp.team?.id);
          const aGoals = detail.filter(d => d.type?.text === 'Goal' && d.team?.id === awayComp.team?.id);
          homeScorers = hGoals.map(d => d.athletesInvolved?.[0]?.displayName || '').filter(Boolean).join(', ');
          awayScorers = aGoals.map(d => d.athletesInvolved?.[0]?.displayName || '').filter(Boolean).join(', ');
        } catch (_) {}

        const rpcRes = await fetch(`${SB_URL}/rest/v1/rpc/set_result`, {
          method: 'POST',
          headers: sbHeaders,
          body: JSON.stringify({
            p_match_id: supaMatch.id,
            p_home: homeScore,
            p_away: awayScore,
            p_home_scorers: homeScorers,
            p_away_scorers: awayScorers,
          }),
        });
        const rpcData = await rpcRes.json();
        results.push(`FINAL: ${supaMatch.home_team} ${homeScore}-${awayScore} ${supaMatch.away_team} → ${rpcData}`);
        updated++;

      } else if (isLive) {
        // Solo actualizar estado y marcador en vivo
        await fetch(`${SB_URL}/rest/v1/matches?id=eq.${supaMatch.id}`, {
          method: 'PATCH',
          headers: { ...sbHeaders, 'Prefer': 'return=minimal' },
          body: JSON.stringify({
            status: 'EN_JUEGO',
            home_goals: homeScore,
            away_goals: awayScore,
            live_clock: clock,
          }),
        });
        results.push(`LIVE: ${supaMatch.home_team} ${homeScore}-${awayScore} ${supaMatch.away_team} (${clock})`);
        updated++;
      }
    }

    return {
      statusCode: 200,
      body: JSON.stringify({ ok: true, espn_events: events.length, updated, results }),
    };
  } catch (err) {
    return {
      statusCode: 500,
      body: JSON.stringify({ error: err.message }),
    };
  }
};
