const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  if (req.method !== 'POST') {
    return new Response('Method Not Allowed', { status: 405, headers: corsHeaders });
  }

  try {
    const { profileId, pin } = await req.json();

    if (!profileId || !/^\d{4}$/.test(String(pin))) {
      return new Response(JSON.stringify({ error: 'INVALID_PARAMS' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const email = `profile${profileId}@nortverde.app`;
    const password = `Pf26#${pin}`;
    const SB_URL = Deno.env.get('SUPABASE_URL') ?? 'https://hugleolrwojikdqidesk.supabase.co';
    const SB_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_KEY')!;

    const res = await fetch(`${SB_URL}/auth/v1/admin/users`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'apikey': SB_SERVICE_KEY,
        'Authorization': `Bearer ${SB_SERVICE_KEY}`,
      },
      body: JSON.stringify({
        email,
        password,
        email_confirm: true,
        user_metadata: { profile_id: profileId },
      }),
    });

    const data = await res.json();

    if (!res.ok) {
      const msg = data.msg || data.message || JSON.stringify(data);
      if (/already registered|already been registered/i.test(msg)) {
        return new Response(JSON.stringify({ ok: true, existing: true }), {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });
      }
      return new Response(JSON.stringify({ error: msg }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    return new Response(JSON.stringify({ ok: true }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: (err as Error).message }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
