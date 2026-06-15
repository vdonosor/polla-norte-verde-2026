// Crea un usuario Supabase Auth via Admin API (service role).
// Llamada desde el frontend cuando alguien crea su PIN por primera vez.
exports.handler = async (event) => {
  if (event.httpMethod !== 'POST') {
    return { statusCode: 405, body: 'Method Not Allowed' };
  }

  try {
    const { profileId, pin } = JSON.parse(event.body || '{}');

    if (!profileId || !/^\d{4}$/.test(String(pin))) {
      return { statusCode: 400, body: JSON.stringify({ error: 'INVALID_PARAMS' }) };
    }

    const email    = `profile${profileId}@nortverde.app`;
    const password = `Pf26#${pin}`;
    const SB_URL   = process.env.SUPABASE_URL || 'https://hugleolrwojikdqidesk.supabase.co';
    const url      = `${SB_URL}/auth/v1/admin/users`;

    const res = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'apikey': process.env.SUPABASE_SERVICE_KEY,
        'Authorization': `Bearer ${process.env.SUPABASE_SERVICE_KEY}`
      },
      body: JSON.stringify({
        email,
        password,
        email_confirm: true,
        user_metadata: { profile_id: profileId }
      })
    });

    const data = await res.json();

    if (!res.ok) {
      const msg = data.msg || data.message || JSON.stringify(data);
      // Usuario ya existe → dejar que el frontend intente signIn
      if (/already registered|already been registered/i.test(msg)) {
        return { statusCode: 200, body: JSON.stringify({ ok: true, existing: true }) };
      }
      return { statusCode: 400, body: JSON.stringify({ error: msg }) };
    }

    return { statusCode: 200, body: JSON.stringify({ ok: true }) };
  } catch (err) {
    return { statusCode: 500, body: JSON.stringify({ error: err.message }) };
  }
};
