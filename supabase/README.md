# Supabase backend

This directory replaces the legacy PHP/MySQL backend.

## Remote project

- Project reference: `qpdfscwlrmpuoqrtemwv`
- Region: Singapore
- Flutter uses only `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY`.
- Never add a Supabase secret/service-role key to Flutter or Git.

## Apply database changes

```powershell
supabase link --project-ref qpdfscwlrmpuoqrtemwv
supabase db push
supabase functions deploy create-staff
```

The initial migration creates Auth-linked profiles, customers, staff,
catalog, appointments, transactions, feedback, compatibility views, secure
RPCs, RLS policies, and Storage buckets. The second migration adds a starter
catalog without passwords or customer data.

## Run Flutter

Copy `supabase.example.json` to `supabase.local.json`, then place the project
URL and publishable key in the local file. Never place a secret/service-role
key there.

```powershell
flutter pub get
flutter run --dart-define-from-file=supabase.local.json
```

For web password-recovery links during development, use the allowed port:

```powershell
flutter run -d chrome --web-port 3000 --dart-define-from-file=supabase.local.json
```

The checked-in VS Code configuration is intentionally omitted; a local
`.vscode/launch.json` can pass the same `--dart-define-from-file` argument.

## Bootstrap the first administrator

Register normally in the app. Then, once only, promote that verified account
in the Supabase SQL Editor using its exact email:

```sql
update public.profiles
set role = 'admin'
where id = (
  select id from auth.users where lower(email) = lower('YOUR_EMAIL')
);

delete from public.customers
where user_id = (
  select id from auth.users where lower(email) = lower('YOUR_EMAIL')
);
```

After promotion, sign out and back in. Admin/manager users can create staff
login accounts through the deployed `create-staff` Edge Function.

## Password migration

Legacy MySQL passwords were plaintext and must not be imported. Existing users
must register again or receive a Supabase invitation/password-reset email.
