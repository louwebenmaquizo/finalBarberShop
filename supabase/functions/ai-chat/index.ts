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
    headers: { ...cors, 'Content-Type': 'application/json' },
  });

interface ChatMessage {
  role: 'user' | 'assistant';
  content: string;
}

Deno.serve(async (request) => {
  const corsHeaders = getCorsHeaders(request);
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (request.method !== 'POST') return json({ error: 'Method not allowed' }, 405, corsHeaders);

  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const publishableKey =
    Deno.env.get('SUPABASE_ANON_KEY') ?? Deno.env.get('SB_PUBLISHABLE_KEY')!;
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const geminiApiKey = Deno.env.get('GEMINI_API_KEY');

  if (!geminiApiKey) return json({ error: 'AI is not configured on the server.' }, 500);

  const authorization = request.headers.get('Authorization');
  if (!authorization) return json({ error: 'Authentication required' }, 401);

  // Verify caller using their own token (respects RLS)
  const callerClient = createClient(supabaseUrl, publishableKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false },
  });
  const { data: userData, error: userError } = await callerClient.auth.getUser();
  if (userError || !userData.user) return json({ error: 'Authentication required' }, 401);

  const { data: profile } = await callerClient
    .from('profiles')
    .select('role, is_active')
    .eq('id', userData.user.id)
    .single();

  if (!profile?.is_active) return json({ error: 'Your account is inactive.' }, 403);

  const role = profile.role as string;

  // Block barbers — AI assistant is for admins and customers only
  if (role === 'barber' || role === 'staff') {
    return json({ error: 'The AI assistant is not available for barbers.' }, 403);
  }
  if (!['admin', 'manager', 'cashier', 'customer'].includes(role)) {
    return json({ error: 'Access denied.' }, 403);
  }

  // Service-role client for all privileged DB operations
  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  let input: { messages: ChatMessage[]; session_id: string };
  try {
    input = await request.json();
  } catch {
    return json({ error: 'Invalid JSON request body.' }, 400);
  }

  const messages: ChatMessage[] = input.messages ?? [];
  const sessionId: string = input.session_id ?? crypto.randomUUID();
  if (!messages.length) return json({ error: 'No messages provided.' }, 400);

  const lastUserMessage = messages[messages.length - 1];
  if (lastUserMessage.role !== 'user')
    return json({ error: 'Last message must be from user.' }, 400);

  let reply: string;
  try {
    if (role === 'customer') {
      reply = await handleCustomer(admin, geminiApiKey, messages, userData.user.id);
    } else {
      reply = await handleAdmin(admin, geminiApiKey, messages, role);
    }
  } catch (err) {
    return json({ error: err instanceof Error ? err.message : 'AI error.' }, 500);
  }

  // Save user message + AI reply to database
  await admin.from('ai_messages').insert([
    { user_id: userData.user.id, session_id: sessionId, role: 'user', content: lastUserMessage.content },
    { user_id: userData.user.id, session_id: sessionId, role: 'assistant', content: reply },
  ]);

  return json({ reply, session_id: sessionId });
});

// ---------------------------------------------------------------------------
// CUSTOMER HANDLER — context-based RAG, no function calling
// ---------------------------------------------------------------------------
async function handleCustomer(
  admin: ReturnType<typeof createClient>,
  apiKey: string,
  messages: ChatMessage[],
  userId: string,
): Promise<string> {
  const [{ data: services }, { data: staff }] = await Promise.all([
    admin
      .from('services')
      .select('name, price, duration_minutes, description')
      .eq('is_active', true)
      .order('name'),
    admin
      .from('staff')
      .select('name, role, skills')
      .eq('is_active', true)
      .order('name'),
  ]);

  // Personalisation: load recent booking history
  const { data: customer } = await admin
    .from('customers')
    .select('id, full_name')
    .eq('user_id', userId)
    .maybeSingle();

  let historyContext = '';
  if (customer?.id) {
    const { data: recentBookings } = await admin
      .from('appointment_details')
      .select('service_name, status')
      .eq('customer_id', customer.id)
      .order('start_time', { ascending: false })
      .limit(5);
    if (recentBookings?.length) {
      historyContext =
        '\n\nThis customer\'s recent bookings:\n' +
        recentBookings.map((b: Record<string, string>) => `- ${b.service_name} (${b.status})`).join('\n');
    }
  }

  const serviceList =
    (services ?? [])
      .map((s: Record<string, unknown>) =>
        `- ${s.name}: ₱${Number(s.price).toFixed(2)}, ${s.duration_minutes} min${
          s.description ? `, "${s.description}"` : ''
        }`
      )
      .join('\n') || 'No services currently listed.';

  const staffList =
    (staff ?? [])
      .map((s: Record<string, unknown>) =>
        `- ${s.name} (${s.role})${
          s.skills ? `: specializes in ${s.skills}` : ''
        }`
      )
      .join('\n') || 'No barbers currently listed.';

  const systemPrompt = `You are a friendly and knowledgeable AI assistant for Liem Barber Shop.
Your job is to help customers choose the right haircut, learn about services, and find the right barber.

AVAILABLE SERVICES:
${serviceList}

AVAILABLE BARBERS:
${staffList}
${historyContext}

RULES:
- Only discuss haircuts, grooming, services, barbers, and appointment-related topics.
- Always show exact prices and durations from the list above. Never invent services or prices.
- When recommending haircuts, be specific and match the customer's described style or preference.
- If asked to book, say: "Great choice! Please use the Booking section in the app to schedule your appointment."
- Keep responses concise, warm, and helpful. Use emojis sparingly.
- Use \u20b1 (Philippine Peso) for all prices.
- If the question is unrelated to the barbershop, politely redirect.`;

  const geminiContents = messages.map((m) => ({
    role: m.role === 'assistant' ? 'model' : 'user',
    parts: [{ text: m.content }],
  }));

  const res = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/gemini-3.6-flash:generateContent?key=${apiKey}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        system_instruction: { parts: [{ text: systemPrompt }] },
        contents: geminiContents,
        generationConfig: { maxOutputTokens: 512, temperature: 0.7 },
      }),
    },
  );

  const data = await res.json();
  const text = data?.candidates?.[0]?.content?.parts?.[0]?.text;
  if (!text) throw new Error('No response from AI. Please try again.');
  return text;
}

// ---------------------------------------------------------------------------
// ADMIN HANDLER — Gemini function calling with real DB tools
// ---------------------------------------------------------------------------
async function handleAdmin(
  admin: ReturnType<typeof createClient>,
  apiKey: string,
  messages: ChatMessage[],
  callerRole: string,
): Promise<string> {
  const isReadOnly = callerRole === 'cashier';

  const systemPrompt = `You are an intelligent management assistant for Liem Barber Shop.
You have access to tools that read and manage the shop's real data.

IMPORTANT RULES:
- Always use the tools to get REAL data. Never guess or invent numbers.
- When creating a barber you MUST collect: name, email, phone, password (min 8 chars), skills.
  If any field is missing, ask the admin for it before calling create_barber.
- Always confirm destructive actions (deactivate) before executing.
- Format currency as \u20b1X,XXX.XX.
- Be concise and professional.
- Current caller role: ${callerRole}${
    isReadOnly ? ' \u2014 READ-ONLY. You cannot create or modify data.' : ''
  }`;

  const functionDeclarations = [
    {
      name: 'get_staff_list',
      description: 'Get all staff/barber records from the database.',
      parameters: {
        type: 'object',
        properties: {
          active_only: {
            type: 'boolean',
            description: 'If true (default), return only active staff.',
          },
        },
      },
    },
    {
      name: 'get_appointment_stats',
      description: 'Get appointment counts and list for a time period.',
      parameters: {
        type: 'object',
        properties: {
          period: {
            type: 'string',
            enum: ['today', 'this_week', 'this_month'],
          },
        },
        required: ['period'],
      },
    },
    {
      name: 'get_revenue_stats',
      description: 'Get completed transaction totals for a time period.',
      parameters: {
        type: 'object',
        properties: {
          period: {
            type: 'string',
            enum: ['today', 'this_week', 'this_month'],
          },
        },
        required: ['period'],
      },
    },
    {
      name: 'get_services_list',
      description: 'Get all services and their details.',
      parameters: { type: 'object', properties: {} },
    },
    {
      name: 'get_customer_count',
      description: 'Get total number of registered customers.',
      parameters: { type: 'object', properties: {} },
    },
    ...(!isReadOnly
      ? [
          {
            name: 'create_barber',
            description:
              'Create a new barber account. Requires: name, email, phone, password (≥8 chars), skills.',
            parameters: {
              type: 'object',
              properties: {
                name: { type: 'string' },
                email: { type: 'string' },
                phone: { type: 'string' },
                password: { type: 'string' },
                skills: { type: 'string' },
                role: {
                  type: 'string',
                  description: 'Staff title, e.g. Barber, Senior Barber',
                },
              },
              required: ['name', 'email', 'phone', 'password', 'skills'],
            },
          },
          {
            name: 'update_staff_status',
            description: 'Activate or deactivate a staff member by name.',
            parameters: {
              type: 'object',
              properties: {
                staff_name: { type: 'string' },
                is_active: { type: 'boolean' },
              },
              required: ['staff_name', 'is_active'],
            },
          },
        ]
      : []),
  ];

  // Build Gemini message history
  let geminiContents: Record<string, unknown>[] = messages.map((m) => ({
    role: m.role === 'assistant' ? 'model' : 'user',
    parts: [{ text: m.content }],
  }));

  // Agentic loop: keep calling Gemini until we get a text response
  for (let turn = 0; turn < 6; turn++) {
    const res = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/gemini-3.6-flash:generateContent?key=${apiKey}`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          system_instruction: { parts: [{ text: systemPrompt }] },
          contents: geminiContents,
          tools: [{ function_declarations: functionDeclarations }],
          generationConfig: { maxOutputTokens: 1024, temperature: 0.2 },
        }),
      },
    );

    const data = await res.json();
    const candidate = data?.candidates?.[0];
    const parts: Record<string, unknown>[] = candidate?.content?.parts ?? [];

    const functionCallParts = parts.filter((p) => p.functionCall);

    if (functionCallParts.length === 0) {
      // Gemini produced a final text answer
      const text = parts.find((p) => p.text)?.text as string | undefined;
      if (!text) throw new Error('No response from AI. Please try again.');
      return text;
    }

    // Add Gemini's function-call turn to history
    geminiContents.push({ role: 'model', parts });

    // Execute each requested tool and collect results
    const toolResponseParts: Record<string, unknown>[] = [];
    for (const part of functionCallParts) {
      const fc = part.functionCall as { name: string; args: Record<string, unknown> };
      const result = await executeTool(admin, fc.name, fc.args, callerRole);
      toolResponseParts.push({
        functionResponse: {
          name: fc.name,
          response: { content: result },
        },
      });
    }

    // Add tool responses back to history
    geminiContents.push({ role: 'user', parts: toolResponseParts });
  }

  throw new Error('The AI could not complete the request. Please rephrase and try again.');
}

// ---------------------------------------------------------------------------
// TOOL EXECUTOR — called by the admin agentic loop
// ---------------------------------------------------------------------------
async function executeTool(
  admin: ReturnType<typeof createClient>,
  name: string,
  args: Record<string, unknown>,
  callerRole: string,
): Promise<string> {
  try {
    switch (name) {
      case 'get_staff_list': {
        let query = admin
          .from('staff')
          .select('name, role, skills, email, phone, is_active, created_at')
          .order('name');
        if (args.active_only !== false) query = query.eq('is_active', true);
        const { data, error } = await query;
        if (error) return `Error: ${error.message}`;
        return JSON.stringify(data ?? []);
      }

      case 'get_appointment_stats': {
        const { start, end } = periodRange(args.period as string);
        const { data, error } = await admin
          .from('appointment_details')
          .select('appointment_id, status, customer_name, staff_name, service_name, start_time')
          .gte('start_time', start)
          .lt('start_time', end)
          .order('start_time');
        if (error) return `Error: ${error.message}`;
        const byStatus: Record<string, number> = {};
        for (const a of data ?? []) {
          byStatus[(a as Record<string, string>).status] =
            (byStatus[(a as Record<string, string>).status] ?? 0) + 1;
        }
        return JSON.stringify({ total: data?.length ?? 0, by_status: byStatus, appointments: data ?? [] });
      }

      case 'get_revenue_stats': {
        const { start, end } = periodRange(args.period as string);
        const { data, error } = await admin
          .from('transactions')
          .select('amount, tip_amount, payment_method, status')
          .gte('created_at', start)
          .lt('created_at', end)
          .eq('status', 'completed');
        if (error) return `Error: ${error.message}`;
        const totalRevenue = (data ?? []).reduce(
          (s, t) => s + Number((t as Record<string, unknown>).amount),
          0,
        );
        const totalTips = (data ?? []).reduce(
          (s, t) => s + Number((t as Record<string, unknown>).tip_amount ?? 0),
          0,
        );
        return JSON.stringify({
          total_revenue: totalRevenue,
          total_tips: totalTips,
          transaction_count: data?.length ?? 0,
        });
      }

      case 'get_services_list': {
        const { data, error } = await admin
          .from('service_catalog')
          .select('name, price, duration_minutes, description, category_name, is_active')
          .order('name');
        if (error) return `Error: ${error.message}`;
        return JSON.stringify(data ?? []);
      }

      case 'get_customer_count': {
        const { count, error } = await admin
          .from('customers')
          .select('*', { count: 'exact', head: true });
        if (error) return `Error: ${error.message}`;
        return JSON.stringify({ total_customers: count ?? 0 });
      }

      case 'create_barber': {
        if (!['admin', 'manager'].includes(callerRole)) {
          return 'Error: Only admins and managers can create barber accounts.';
        }
        const { name, email, phone, password, skills } = args;
        if (!name || !email || !phone || !password || !skills) {
          return 'Error: All fields (name, email, phone, password, skills) are required.';
        }
        if ((password as string).length < 8) {
          return 'Error: Password must be at least 8 characters.';
        }
        const username = (email as string)
          .split('@')[0]
          .toLowerCase()
          .replace(/[^a-z0-9_]/g, '_');

        const { data: created, error: createError } =
          await admin.auth.admin.createUser({
            email: email as string,
            password: password as string,
            email_confirm: true,
            user_metadata: { username, full_name: name },
          });
        if (createError || !created.user) {
          return `Error: ${createError?.message ?? 'Could not create user account.'}`;
        }

        const userId = created.user.id;
        try {
          await admin
            .from('profiles')
            .update({ username, role: 'barber', is_active: true })
            .eq('id', userId);

          const { data: staffRow, error: staffError } = await admin
            .from('staff')
            .insert({
              user_id: userId,
              name,
              phone,
              email,
              role: (args.role as string) ?? 'Barber',
              skills,
              is_active: true,
            })
            .select()
            .single();
          if (staffError) throw staffError;

          return JSON.stringify({
            success: true,
            message: `Barber "${name}" created successfully.`,
            staff_id: (staffRow as Record<string, unknown>).id,
          });
        } catch (err) {
          await admin.auth.admin.deleteUser(userId);
          return `Error: ${err instanceof Error ? err.message : String(err)}`;
        }
      }

      case 'update_staff_status': {
        if (!['admin', 'manager'].includes(callerRole)) {
          return 'Error: Only admins and managers can change staff status.';
        }
        const { staff_name, is_active } = args;
        const { data: found, error: findErr } = await admin
          .from('staff')
          .select('id, name, user_id')
          .ilike('name', `%${staff_name}%`)
          .limit(1)
          .maybeSingle();
        if (findErr || !found) {
          return `Error: Could not find a staff member matching "${staff_name}".`;
        }
        const sf = found as Record<string, unknown>;
        await admin.from('staff').update({ is_active }).eq('id', sf.id);
        if (sf.user_id) {
          await admin.from('profiles').update({ is_active }).eq('id', sf.user_id);
        }
        return JSON.stringify({
          success: true,
          message: `${sf.name} has been ${is_active ? 'activated' : 'deactivated'}.`,
        });
      }

      default:
        return `Error: Unknown tool "${name}".`;
    }
  } catch (err) {
    return `Error: ${err instanceof Error ? err.message : String(err)}`;
  }
}

// ---------------------------------------------------------------------------
// HELPERS
// ---------------------------------------------------------------------------
function periodRange(period: string): { start: string; end: string } {
  const now = new Date();
  let start: Date;
  let end: Date;
  if (period === 'today') {
    start = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    end = new Date(start.getTime() + 86_400_000);
  } else if (period === 'this_week') {
    const day = now.getDay();
    start = new Date(now.getFullYear(), now.getMonth(), now.getDate() - day);
    end = new Date(start.getTime() + 7 * 86_400_000);
  } else {
    // this_month
    start = new Date(now.getFullYear(), now.getMonth(), 1);
    end = new Date(now.getFullYear(), now.getMonth() + 1, 1);
  }
  return { start: start.toISOString(), end: end.toISOString() };
}
