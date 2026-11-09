-- rls_audit.sql
-- Paste into Supabase -> SQL Editor and run. Three result sets:
--   1) tables in `public` with RLS OFF                  -> data is public to anyone with the anon key
--   2) tables with RLS ON but ZERO policies            -> every browser query fails or returns nothing
--   3) policies whose condition is literally TRUE      -> everyone can do that operation on every row
-- Expected on a healthy project: all three empty, except tables you deliberately made public
-- (with a documented reason) or deliberately left policy-less for server-only access.

-- 1) RLS off
select
  n.nspname  as schema,
  c.relname  as table_name,
  'RLS OFF'  as finding
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relkind in ('r', 'p')          -- ordinary and partitioned tables
  and c.relrowsecurity = false
order by c.relname;

-- 2) RLS on, no policies
select
  n.nspname  as schema,
  c.relname  as table_name,
  'RLS ON, NO POLICIES' as finding
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relkind in ('r', 'p')
  and c.relrowsecurity = true
  and not exists (
    select 1 from pg_policy p where p.polrelid = c.oid
  )
order by c.relname;

-- 3) permissive "true" policies (USING true or WITH CHECK true)
select
  schemaname          as schema,
  tablename           as table_name,
  policyname          as policy,
  cmd                 as operation,
  roles,
  qual                as using_expression,
  with_check          as with_check_expression,
  'ALLOWS EVERYONE'   as finding
from pg_policies
where schemaname = 'public'
  and (
    coalesce(qual, '')       in ('true', '(true)')
    or coalesce(with_check, '') in ('true', '(true)')
  )
order by tablename, policyname;

-- Bonus: full policy inventory, useful for the diagnosis report
-- select schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
-- from pg_policies where schemaname = 'public' order by tablename, cmd, policyname;

-- Bonus: which roles can touch each table at all (grants), independent of RLS
-- select table_name, grantee, string_agg(privilege_type, ', ' order by privilege_type) as privileges
-- from information_schema.role_table_grants
-- where table_schema = 'public' and grantee in ('anon', 'authenticated')
-- group by table_name, grantee order by table_name, grantee;
