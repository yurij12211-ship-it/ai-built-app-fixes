# Diagnosis report (free 24-hour diagnosis)

This is the one-page format every diagnosis comes back in. It exists so you can compare quotes, hand it to another developer, or fix the small items yourself.

---

**Project:** `<name>` · **Builder:** Lovable / Bolt / Replit / Base44 / v0 · **Backend:** Supabase (own project / Lovable Cloud) · **Payments:** Stripe yes/no
**Reported symptom:** "<in the client's words>"
**Access used:** GitHub read-only invite · project share link · screenshots only
**Date:** YYYY-MM-DD

## 1. Root cause (plain English)

One paragraph. What is actually broken, where, and why the builder keeps reintroducing it.

## 2. Evidence

- Exact error text and where it appears (console / network / function log / Stripe log).
- Query or command that reproduces it, e.g. the `rls_audit.sql` rows, the failing request from the Network tab, the webhook delivery with its status code.
- Screenshot references if any.

## 3. Findings

| # | Finding | Severity | Where | Fix ref |
|---|---------|----------|-------|---------|
| 1 | e.g. `projects` table has RLS off; all rows readable with the anon key | **Critical** (data exposure) | Supabase → public.projects | [Fix 1](../fixes/01-supabase-rls.md), pattern A |
| 2 | e.g. Site URL still `localhost:3000`; confirmation emails unusable in production | High (blocks sign-up) | Supabase → Auth → URL config | [Fix 2](../fixes/02-auth-redirects.md), step A |
| 3 | e.g. `useEffect` in `Dashboard.tsx` refetches on every render | Medium (cost, slowness) | src/pages/Dashboard.tsx:41 | [Fix 3](../fixes/03-react-render-loops.md), case 2 |
| 4 | … | Low | … | … |

Severity scale: **Critical** = data exposure or money at risk · **High** = users cannot complete a core flow · **Medium** = works but costs money/credits or will break at scale · **Low** = polish.

## 4. Recommended scope and quote

- **Must fix before launch:** findings #1, #2 — fixed price **$___**, delivery **24–48 h** from go-ahead.
- **Should fix soon:** finding #3 — **$___** or included if done together.
- **Optional:** finding #4 — you can do this yourself with the linked fix; no charge.

What is included: the fix in a separate branch (or applied in your builder with the exact prompts/SQL documented), a written explanation of each change, verification per the Verify sections, and 7 days of follow-up for the same issues.

What is not included: new features, redesigns, anything not listed above (quoted separately if you want it).

## 5. What you can do yourself right now (no charge)

Two or three concrete items from the findings that are safe and quick, with the link to the exact section.

## 6. Access and safety notes

- No passwords were requested or used. Access was via `<GitHub invite / share link>`; you can revoke it at `<where>`.
- All secrets stay in your Supabase and Stripe dashboards. If any secret was found in the front-end bundle, **rotate it now** (listed in Findings) regardless of who fixes the rest.
- Any SQL I propose is included verbatim so you can review it or run it yourself.

---

*Prepared by Yurij V. · [Upwork](https://www.upwork.com/freelancers/~011846815b093cf1d1) · [Fiverr](https://www.fiverr.com/yurij1221) · Repo of fixes: https://github.com/yurij12211-ship-it/ai-built-app-fixes*
