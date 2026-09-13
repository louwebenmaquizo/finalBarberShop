import { createClient } from 'npm:@supabase/supabase-js@2';

function getCorsHeaders(request: Request) {
  const origin = request.headers.get('Origin') ?? '';
  const isAllowed = !origin ||
    origin.startsWith('http://localhost:') ||
    origin.startsWith('http://127.0.0.1:') ||
    origin.endsWith('.supabase.co') ||
    origin.endsWith('.vercel.app');

  return {
    'Access-Control-Allow-Origin': isAllowed ? (origin || '*') : 'http://localhost:3000',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
  };
}

const json = (body: unknown, status = 200, cors: Record<string, string> = {}) =>
  new Response(JSON.stringify(body), {
    status,
    headers: {...cors, 'Content-Type': 'application/json'},
  });

Deno.serve(async (request) => {
  const corsHeaders = getCorsHeaders(request);
  if (request.method === 'OPTIONS') {
    return new Response('ok', {headers: corsHeaders});
  }
  if (request.method !== 'POST') {
    return json({error: 'Method not allowed'}, 405);
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const publishableKey =
    Deno.env.get('SUPABASE_ANON_KEY') ?? Deno.env.get('SB_PUBLISHABLE_KEY');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const authorization = request.headers.get('Authorization');
  if (!supabaseUrl || !publishableKey || !serviceRoleKey) {
    return json({error: 'Server authentication is not configured'}, 500);
  }
  if (!authorization) {
    return json({error: 'Authentication required'}, 401);
  }

  const callerClient = createClient(supabaseUrl, publishableKey, {
    global: {headers: {Authorization: authorization}},
    auth: {persistSession: false},
  });
  const {data: userData, error: userError} =
    await callerClient.auth.getUser();
  if (userError || !userData.user) {
    return json({error: 'Authentication required'}, 401);
  }

  const {data: caller, error: callerError} = await callerClient
    .from('profiles')
    .select('role,is_active')
    .eq('id', userData.user.id)
    .single();
  if (
    callerError ||
    !caller?.is_active ||
    !['admin', 'manager'].includes(caller.role)
  ) {
    return json({error: 'Admin or manager access is required'}, 403);
  }

  let input: Record<string, unknown>;
  try {
    input = await request.json();
  } catch (_) {
    return json({error: 'A JSON request body is required'}, 400);
  }

  const email = String(input.email ?? '').trim().toLowerCase();
  const password = String(input.password ?? '');
  const username = String(input.username ?? email.split('@')[0] ?? '').trim();
  const name = String(input.name ?? '').trim();
  const staffTitle = String(input.role ?? 'Barber').trim();
  const existingUserId = input.user_id ? String(input.user_id).trim() : null;

  if (existingUserId) {
    if (!name) {
      return json({error: 'Staff name is required'}, 400);
    }
    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: {persistSession: false, autoRefreshToken: false},
    });

    try {
      // If password provided, update user auth password
      if (password) {
        if (password.length < 8) {
          return json({error: 'Password must be at least 8 characters long'}, 400);
        }
        const authUpdate: Record<string, unknown> = {password};
        if (email.includes('@')) {
          authUpdate.email = email;
        }
        const {error: updateAuthError} = await admin.auth.admin.updateUserById(
          existingUserId,
          authUpdate,
        );
        if (updateAuthError) {
          return json({error: updateAuthError.message}, 400);
        }
      }

      // Update profiles role and username
      await admin
        .from('profiles')
        .update({
          username: username || undefined,
          role: 'barber',
          is_active: input.is_active !== false,
        })
        .eq('id', existingUserId);

      // Update staff record
      const staffUpdateFields: Record<string, unknown> = {
        name,
        phone: input.phone || null,
        role: staffTitle,
        skills: input.skills || null,
        pay_rate: input.pay_rate ?? null,
        commission_rate: input.commission_rate ?? 0,
        is_active: input.is_active !== false,
      };
      if (email.includes('@')) {
        staffUpdateFields.email = email;
      }

      const {data: staff, error: staffError} = await admin
        .from('staff')
        .update(staffUpdateFields)
        .eq('user_id', existingUserId)
        .select()
        .single();

      if (staffError) throw staffError;

      return json({
        data: {
          ...staff,
          staff_id: staff.id,
          username,
        },
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      return json({error: message}, 400);
    }
  }

  if (!email.includes('@') || password.length < 8 || !username || !name) {
    return json(
      {error: 'Valid email, username, name, and an 8-character password are required'},
      400,
    );
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: {persistSession: false, autoRefreshToken: false},
  });
  const {data: created, error: createError} =
    await admin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: {username},
    });
  if (createError || !created.user) {
    return json({error: createError?.message ?? 'Unable to create user'}, 400);
  }

  const userId = created.user.id;
  try {
    const {error: profileError} = await admin
      .from('profiles')
      .update({username, role: 'barber', is_active: input.is_active !== false})
      .eq('id', userId);
    if (profileError) throw profileError;

    const {data: staff, error: staffError} = await admin
      .from('staff')
      .insert({
        user_id: userId,
        name,
        phone: input.phone || null,
        email,
        role: staffTitle,
        skills: input.skills || null,
        pay_rate: input.pay_rate ?? null,
        commission_rate: input.commission_rate ?? 0,
        is_active: input.is_active !== false,
      })
      .select()
      .single();
    if (staffError) throw staffError;

    return json({
      data: {
        ...staff,
        staff_id: staff.id,
        username,
      },
    });
  } catch (error) {
    await admin.auth.admin.deleteUser(userId);
    const message = error instanceof Error ? error.message : String(error);
    return json({error: message}, 400);
  }
});
