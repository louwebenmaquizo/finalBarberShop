-- AI chat message history for the Liem Barber Shop assistant.
-- One row per message (user or assistant) grouped by session_id.
-- Clients and Edge Functions can insert and query their own messages.

begin;

create table if not exists public.ai_messages (
  id           uuid        primary key default gen_random_uuid(),
  user_id      uuid        not null references public.profiles (id) on delete cascade,
  session_id   text        not null,
  role         text        not null check (role in ('user', 'assistant')),
  content      text        not null,
  created_at   timestamptz not null default now()
);

-- In case session_id was created as uuid in an earlier run, alter to text
do $$
begin
  alter table public.ai_messages alter column session_id type text using session_id::text;
exception when others then null;
end $$;

create index if not exists ai_messages_user_session_idx
  on public.ai_messages (user_id, session_id, created_at);

alter table public.ai_messages enable row level security;

-- Customers and admins can read their own messages.
drop policy if exists ai_messages_select_own_or_management on public.ai_messages;
create policy ai_messages_select_own_or_management
on public.ai_messages for select to authenticated
using (user_id = auth.uid() or private.is_management());

-- Authenticated users can insert their own messages into chat history.
drop policy if exists ai_messages_insert_own on public.ai_messages;
create policy ai_messages_insert_own
on public.ai_messages for insert to authenticated
with check (user_id = auth.uid() or private.is_management());

-- Users can delete their own messages, and management can delete any messages (moderation).
drop policy if exists ai_messages_delete_management on public.ai_messages;
drop policy if exists ai_messages_delete_own on public.ai_messages;
create policy ai_messages_delete_own
on public.ai_messages for delete to authenticated
using (user_id = auth.uid() or private.is_management());

commit;
