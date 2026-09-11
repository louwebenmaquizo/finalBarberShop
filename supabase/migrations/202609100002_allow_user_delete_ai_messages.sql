-- Allow authenticated users to delete their own chat messages,
-- and allow management to delete any chat message.
begin;

drop policy if exists ai_messages_delete_management on public.ai_messages;
drop policy if exists ai_messages_delete_own on public.ai_messages;

create policy ai_messages_delete_own
on public.ai_messages for delete to authenticated
using (user_id = auth.uid() or private.is_management());

commit;
