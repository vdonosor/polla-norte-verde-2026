const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const TEAM_MAP: Record<string, string> = {
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

function mapTeam(name: string): string {
  return TEAM_MAP[name] || name;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  const SB_URL = Deno.env.get('SUPABASE_URL') ?? 'https://hugleolrwojikdqidesk.supabase.co';
  const SB_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

  if (!SB_KEY) {
    return new Response(JSON.stringify({ error: 'Missing SUPABASE_SERVICE_KEY' }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }

  const sbHeaders = {
    'apikey': SB_KEY,
    'Authorization': `Bearer ${SB_KEY}`,
    'Content-Type': 'application/json',
  };

  try {
    const matchRes = await fetch(
      `${SB_URL}/rest/v1/matches?enabled=eq.true&select=id,home_team,away_team,status,home_scorers,away_scorers&order=match_number`,
      { headers: sbHeaders }
    );
    const supaMatches = await matchRes.json();

    const today = new Date().toISOString().slice(0, 10).replace(/-/g, '');
    const espnRes = await fetch(
      `https://site.api.espn.com/apis/site/v2/sports/soccer/fifa.world/scoreboard?dates=${today}`,
      { headers: { 'Accept': 'application/json' } }
    );
    if (!espnRes.ok) {
      return new Response(JSON.stringify({ error: 'ESPN API error: ' + espnRes.status }), {
        status: 502,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }
    const espnData = await espnRes.json();
    const events = espnData.events || [];

    const results: string[] = [];
    let updated = 0;

    for (const supaMatch of supaMatches) {
      const espnEvent = events.find((e: any) => {
        const comp = e.competitions?.[0];
        if (!comp) return false;
        const home = comp.competitors?.find((c: any) => c.homeAway === 'home');
        const away = comp.competitors?.find((c: any) => c.homeAway === 'away');
        if (!home || !away) return false;
        const hn = mapTeam(home.team?.displayName || '');
        const an = mapTeam(away.team?.displayName || '');
        return hn === supaMatch.home_team && an === supaMatch.away_team;
      });

      if (!espnEvent) continue;

      const comp = espnEvent.competitions[0];
      const homeComp = comp.competitors.find((c: any) => c.homeAway === 'home');
      const awayComp = comp.competitors.find((c: any) => c.homeAway === 'away');
      const homeScore = parseInt(homeComp?.score) || 0;
      const awayScore = parseInt(awayComp?.score) || 0;

      const espnStatus = espnEvent.status?.type?.name || '';
      const isFinal = espnStatus === 'STATUS_FINAL' || espnStatus === 'STATUS_FULL_TIME' || espnEvent.status?.type?.completed;
      const isLive = espnStatus === 'STATUS_IN_PROGRESS' || espnStatus === 'STATUS_HALFTIME';
      const clock = espnEvent.status?.displayClock || null;

      if (isFinal) {
        let homeScorers = '';
        let awayScorers = '';
        try {
          const detail = comp.details || [];
          const hGoals = detail.filter((d: any) => d.type?.text === 'Goal' && d.team?.id === homeComp.team?.id);
          const aGoals = detail.filter((d: any) => d.type?.text === 'Goal' && d.team?.id === awayComp.team?.id);
          homeScorers = hGoals.map((d: any) => d.athletesInvolved?.[0]?.displayName || '').filter(Boolean).join(', ');
          awayScorers = aGoals.map((d: any) => d.athletesInvolved?.[0]?.displayName || '').filter(Boolean).join(', ');
        } catch (_) { /* ignore scorer extraction errors */ }

        const alreadyFinal = supaMatch.status === 'FINALIZADO';
        const missingScorers = !supaMatch.home_scorers && !supaMatch.away_scorers && (homeScorers || awayScorers);

        if (alreadyFinal && !missingScorers) continue;

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

    // Siempre refrescar goles de jugadores al final del scan
    await fetch(`${SB_URL}/rest/v1/rpc/refresh_player_goals`, {
      method: 'POST', headers: sbHeaders, body: JSON.stringify({}),
    });

    const espnTeams = events.map((e: any) => {
      const comp = e.competitions?.[0];
      const home = comp?.competitors?.find((c: any) => c.homeAway === 'home');
      const away = comp?.competitors?.find((c: any) => c.homeAway === 'away');
      return { home: home?.team?.displayName, away: away?.team?.displayName, status: e.status?.type?.name };
    });

    return new Response(
      JSON.stringify({ ok: true, espn_events: events.length, updated, results, espnTeams }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  } catch (err) {
    return new Response(JSON.stringify({ error: (err as Error).message }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
