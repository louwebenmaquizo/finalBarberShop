-- Enforce strict AI chat privacy:
-- Every user (including admin and management) can ONLY see and delete their OWN AI chat messages.
-- No user can see any other user's conversations with AI.
begin;

-- 1. Drop existing select policies
drop policy if exists ai_messages_select_own_or_management on public.ai_messages;
drop policy if exists ai_messages_select_own on public.ai_messages;

-- 2. Create strict select policy: only the message owner can view their messages
create policy ai_messages_select_own
on public.ai_messages for select to authenticated
using (user_id = auth.uid());

-- 3. Drop existing delete policies
drop policy if exists ai_messages_delete_management on public.ai_messages;
drop policy if exists ai_messages_delete_own on public.ai_messages;

-- 4. Create strict delete policy: only the message owner can delete their messages
create policy ai_messages_delete_own
on public.ai_messages for delete to authenticated
using (user_id = auth.uid());

commit;
