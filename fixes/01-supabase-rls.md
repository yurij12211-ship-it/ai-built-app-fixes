# Fix 1: Supabase Row Level Security (RLS)

Builder: Lovable, Bolt, Replit, Base44, v0 or any app that talks to Supabase from the browser.

## Symptoms

| What you see | What it usually means |
|---|---|
| `permission denied for table <name>` | RLS is on and there is no policy that lets this role read the table, or the table grant for `anon`/`authenticated` was removed |
| `new row violates row-level security policy for table <name>` | RLS is on; there is no INSERT policy, or the `WITH CHECK` condition fails (most often `user_id` is not set on the inserted row) |
| The list is empty, but the rows exist in the Table Editor | RLS is on with a SELECT policy whose condition never matches (wrong column, `auth.uid()` compared to the wrong id) |
| Every user sees every other user's records | RLS is off, or a policy uses `USING (true)` for everyone |
| Lovable / Bolt security scan: "RLS disabled", "policy allows public access", "publicly readable table" | Same as above; the scanners look for exactly these two states |
| `infinite recursion detected in policy for relation <name>` | A policy on table A queries table A (directly or through another table whose policy comes back to A) |
| Works in the builder preview, fails after publish | The preview was often tested while logged in as the project owner, or with RLS off; production users hit the real policies |

## Why it happens

The browser uses the **anon key**. That key is public by design: anyone who opens your site can copy it from the network tab and call your database directly. Row Level Security is the only thing standing between that key and your data. AI builders generate the tables and the UI first and frequently leave RLS for later, or write a permissive policy to "make it work" and never tighten it.

So there are only three healthy states for a table that the browser touches:

1. RLS **on**, with policies that check `auth.uid()` (owner-based or membership-based).
2. RLS **on**, with a deliberate public-read policy for genuinely public data (a blog, a catalog), and owner-only writes.
3. The table is **never** touched from the browser; only an edge function with the service-role key reads it. Then grants to `anon`/`authenticated` can be revoked entirely.

Everything else is either broken (errors, empty lists) or a data leak.

## Diagnose (5 minutes)

Open **Supabase → SQL Editor** and run [`scripts/rls_audit.sql`](../scripts/rls_audit.sql). It returns three result sets:

1. Tables in `public` with RLS **off**.
2. Tables with RLS **on** but **zero policies** (these produce the `permission denied` / empty list symptoms).
3. Policies whose condition is literally `true` (these produce the "everyone sees everything" symptom).

Then reproduce as a real user. The SQL editor runs as `postgres`, which **bypasses RLS**, so a query that works there proves nothing. Simulate the browser instead:

```sql
-- run inside one transaction so the role change does not stick
begin;
select set_config('request.jwt.claims',
  '{"sub":"<a real user uuid from auth.users>","role":"authenticated"}', true);
set local role authenticated;

select count(*) from public.projects;   -- what this user can actually see

rollback;
```

If the count is `0` while the Table Editor shows rows for that user, the SELECT policy is wrong. If you get `permission denied`, there is no policy (or no grant) for `authenticated`.

## Fix

### Pattern A: owner-based table (the default for user data)

Use this for anything that belongs to one user: projects, notes, orders, settings.

```sql
-- 1. every row must know its owner
alter table public.projects
  add column if not exists user_id uuid not null default auth.uid()
  references auth.users (id) on delete cascade;

create index if not exists projects_user_id_idx on public.projects (user_id);

-- 2. turn RLS on
alter table public.projects enable row level security;
-- optional: make the table owner obey policies too (service role still bypasses them)
-- alter table public.projects force row level security;

-- 3. drop whatever permissive policies the builder left behind
drop policy if exists "Enable read access for all users" on public.projects;
drop policy if exists "Allow all" on public.projects;

-- 4. one policy per operation, all scoped to the owner
create policy "projects: owner can select"
  on public.projects for select to authenticated
  using (user_id = (select auth.uid()));

create policy "projects: owner can insert"
  on public.projects for insert to authenticated
  with check (user_id = (select auth.uid()));

create policy "projects: owner can update"
  on public.projects for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy "projects: owner can delete"
  on public.projects for delete to authenticated
  using (user_id = (select auth.uid()));
```

Notes:

- `default auth.uid()` means the front-end does not have to send `user_id` at all. That removes the most common cause of `new row violates row-level security policy`: the builder inserts a row without `user_id`, so `WITH CHECK` fails.
- `(select auth.uid())` instead of bare `auth.uid()` lets Postgres evaluate the function once per query instead of once per row. On large tables this is the difference between 50 ms and 5 s.
- `to authenticated` means anonymous visitors get nothing. If your app has no public pages reading this table, that is what you want.

### Pattern B: public read, owner write

For catalogs, blog posts, public profiles.

```sql
alter table public.posts enable row level security;

create policy "posts: anyone can read published"
  on public.posts for select to anon, authenticated
  using (published = true);

create policy "posts: author can do everything"
  on public.posts for all to authenticated
  using (author_id = (select auth.uid()))
  with check (author_id = (select auth.uid()));
```

The `published = true` filter matters: without it, drafts are public too.

### Pattern C: teams / multi-tenant (and the recursion error)

When access depends on membership (workspace members can see workspace documents), the naive policy queries the membership table, whose own policy queries the membership table again, and Postgres reports `infinite recursion detected in policy`. The fix is a `security definer` function that reads memberships without going through RLS:

```sql
create or replace function public.is_workspace_member(ws uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from public.workspace_members m
    where m.workspace_id = ws
      and m.user_id = auth.uid()
  );
$$;

revoke all on function public.is_workspace_member(uuid) from public;
grant execute on function public.is_workspace_member(uuid) to authenticated;

alter table public.documents enable row level security;

create policy "documents: members can read"
  on public.documents for select to authenticated
  using (public.is_workspace_member(workspace_id));

create policy "documents: members can write"
  on public.documents for insert to authenticated
  with check (public.is_workspace_member(workspace_id));
```

The membership table itself gets a simple owner policy (`user_id = auth.uid()`), which does not recurse.

### Pattern D: tables the browser should never touch

Webhook logs, Stripe event tables, admin audit tables.

```sql
alter table public.stripe_events enable row level security;
-- no policies at all: with RLS on and zero policies, anon/authenticated get nothing.
-- edge functions use the service-role key, which bypasses RLS.
revoke all on table public.stripe_events from anon, authenticated;
```

### Storage buckets

Storage has its own policies on `storage.objects`. A private bucket with no policies gives `new row violates row-level security policy` on upload. Owner-scoped upload and read:

```sql
create policy "avatars: users upload to their own folder"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy "avatars: users read their own folder"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );
```

This expects uploads at `avatars/<user-uuid>/<file>`.

## Mistakes to avoid

- **Fixing the error by disabling RLS.** The error goes away and your whole table becomes public. Scanners will flag it, and so will your first security-aware customer.
- **Using the service-role key in the browser** ("it fixed the permission error"). The service-role key bypasses every policy; shipping it in the front-end bundle hands your entire database to anyone who views source. Run [`scripts/check-bundle-secrets.sh`](../scripts/check-bundle-secrets.sh) after every build.
- **A SELECT policy without an INSERT policy** (or vice versa). Policies are per operation. "Reading works, saving fails" is almost always a missing INSERT/UPDATE policy or a missing `WITH CHECK`.
- **Testing in the SQL editor as `postgres`.** It bypasses RLS. Use the transaction trick in *Diagnose*, or test from the actual app as a second, non-admin user.
- **Changing the schema outside the builder without telling it.** If you run SQL directly in Supabase, tell Lovable/Bolt what you changed (or paste the SQL into the chat as "this migration was applied") so the generated types and later prompts stay in sync.

## Verify

1. Re-run `scripts/rls_audit.sql`: all three result sets should be empty, except for tables you deliberately made public (pattern B) or deliberately left policy-less (pattern D).
2. Log in as **two different test users** in two browsers. Create a record as user A. User B must not see it in the UI **and** must not get it from the API:

   ```bash
   curl "https://<project>.supabase.co/rest/v1/projects?select=*" \
     -H "apikey: <anon key>" \
     -H "Authorization: Bearer <user B access token>"
   ```

   Expected: `[]` (or only B's rows).
3. Call the same endpoint with **no** `Authorization` header (anonymous). Expected: `[]` or a `401`/`permission denied`, never user data.
4. Run the builder's own security scan again; the RLS findings should be gone.

## When to ask for help

Policies that depend on roles stored in a `profiles` table, hierarchical permissions (admin → manager → member), or data shared between two tenants are where hand-written policies most often leak. If `rls_audit.sql` is clean but the two-user test still fails, that is a logic problem, not a settings problem, and worth a second pair of eyes.
