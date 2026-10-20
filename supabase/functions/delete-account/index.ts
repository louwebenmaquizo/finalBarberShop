import { createClient } from 'npm:@supabase/supabase-js@2';

// Lets a signed-in customer permanently delete their own account, as required
// by Google Play and the App Store. Staff accounts are removed by an admin.
//
// Deletes: avatar files, the customer row (cascades to appointments and
// feedback), and the auth user (cascades to profile and AI chat history).
// Keeps: transactions, with customer_id set to NULL, for the shop's books.

function getCorsHeaders(request: Request): Record<string, string> {
  const origin = request.headers.get('Origin') ?? '';
  const configured = (Deno.env.get('ALLOWED_ORIGINS') ?? '')
    .split(',')
    .map((o) => o.trim())
    .filter(Boolean);
  const isAllowed = !origin ||
    configured.includes(origin) ||
    origin.startsWith('http://localhost:') ||
    origin.startsWith('http://127.0.0.1:');

  return {
    'Access-Control-Allow-Origin': isAllowed && origin ? origin : (configured[0] ?? 'http://localhost:3000'),
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    Vary: 'Origin',
  };
}

Deno.serve(async (request) => {
  const cors = getCorsHeaders(request);
  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), {
      status,
      headers: { ...cors, 'Content-Type': 'application/json' },
    });

  if (request.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (request.method !== 'POST') return json({ error: 'Method not allowed' }, 405);

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const publishableKey =
    Deno.env.get('SUPABASE_ANON_KEY') ?? Deno.env.get('SB_PUBLISHABLE_KEY');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!supabaseUrl || !publishableKey || !serviceRoleKey) {
    return json({ error: 'Server authentication is not configured' }, 500);
  }

  const authorization = request.headers.get('Authorization');
  if (!authorization) return json({ error: 'Authentication required' }, 401);

  const callerClient = createClient(supabaseUrl, publishableKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false },
  });
  const { data: userData, error: userError } = await callerClient.auth.getUser();
  if (userError || !userData.user) return json({ error: 'Authentication required' }, 401);
  const userId = userData.user.id;

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: profile } = await admin
    .from('profiles')
    .select('role')
    .eq('id', userId)
    .maybeSingle();
  if (profile && profile.role !== 'customer') {
    return json(
      { error: 'Staff and admin accounts must be removed by a shop administrator.' },
      403,
    );
  }

  try {
    const { data: customer } = await admin
      .from('customers')
      .select('id')
      .eq('user_id', userId)
      .maybeSingle();

    const bucket = admin.storage.from('customer-avatars');
    for (const folder of [customer?.id, userId].filter(Boolean) as string[]) {
      const { data: files } = await bucket.list(folder, { limit: 1000 });
      if (files?.length) {
        await bucket.remove(files.map((f) => `${folder}/${f.name}`));
      }
    }

    if (customer?.id) {
      const { error: deleteCustomerError } = await admin
        .from('customers')
        .delete()
        .eq('id', customer.id);
      if (deleteCustomerError) throw deleteCustomerError;
    }

    const { error: deleteUserError } = await admin.auth.admin.deleteUser(userId);
    if (deleteUserError) throw deleteUserError;

    return json({ success: true });
  } catch (err) {
    console.error('delete-account failed', err);
    return json({ error: 'Could not delete the account. Please try again or contact the shop.' }, 500);
  }
});
