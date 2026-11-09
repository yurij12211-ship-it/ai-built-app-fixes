# ai-built-app-fixes

Tested fixes and a launch checklist for apps built with **Lovable, Bolt, Replit, Base44, v0** and similar AI builders on top of **Supabase**.

The builder got you to "almost works". This repo covers the last 10%: the five problems that stop AI-built apps from going live, how to diagnose each one in minutes, and the exact fix.

| # | Fix | Typical symptom |
|---|-----|-----------------|
| 1 | [Supabase Row Level Security](fixes/01-supabase-rls.md) | `permission denied`, `new row violates row-level security policy`, empty lists after login, users seeing each other's data, security-scan warnings |
| 2 | [Auth and redirect URLs](fixes/02-auth-redirects.md) | confirmation email opens `localhost:3000`, `Email link is invalid or has expired`, redirect loop after login, Google login works in preview but not on the custom domain |
| 3 | [React render loops](fixes/03-react-render-loops.md) | `Maximum update depth exceeded`, `Too many re-renders`, endless spinner, the same request firing hundreds of times |
| 4 | [Stripe and edge functions](fixes/04-stripe-edge-functions.md) | checkout works in test mode but not live, `No such price`, subscription never unlocks, `Webhook signature verification failed`, customer portal error, CORS errors |
| 5 | [Publish and deploy](fixes/05-publish-and-deploy.md) | blank page after publish, 404 on refresh, custom domain not connecting, build fails on Vercel/Netlify after GitHub export, env vars undefined |

Also in this repo:

- [`checklist/launch-readiness.md`](checklist/launch-readiness.md): 32 checks to run before you put real users and real money into an AI-built app.
- [`scripts/rls_audit.sql`](scripts/rls_audit.sql): one query that lists every table with RLS off, RLS on but no policies, or a policy that lets everyone in.
- [`scripts/check-bundle-secrets.sh`](scripts/check-bundle-secrets.sh): greps your production build for keys that must never ship to the browser.
- [`templates/diagnosis-report.md`](templates/diagnosis-report.md): the one-page report format used for the free 24-hour diagnosis.

## How to use this repo

1. Find your symptom in the table above and open the fix.
2. Run the **Diagnose** section first. Every fix starts with a way to confirm the cause in under five minutes, so you don't apply the wrong fix.
3. Apply the **Fix** section. Where a change touches the database, it is plain SQL you can paste into the Supabase SQL editor (or ask your builder to apply as a migration).
4. Run the **Verify** section. A fix that is not verified is a guess.

Everything here is written for people who built their app with prompts and do not want to become full-time developers. Each fix explains *why* the problem happens, so your next prompt to the builder does not reintroduce it.

## Why these five

Independent scans of AI-built apps keep finding the same things. Symbiotic Security's June 2026 scan of 1,072 Supabase-backed vibe-coded apps found at least one finding in 98% of them and a critical flaw in 16%. The RLS gap behind CVE-2025-48757 affected roughly 170 of 1,645 scanned Lovable apps. Agencies that audit these apps report the same handful of bug classes in most audits (Fora Soft, October 2026). The five fixes here are those classes.

## Need it done for you?

I fix and finish AI-built apps for a fixed price, usually within 24–48 hours, after a **free 24-hour diagnosis** (you get a written report and a quote before paying anything).

- Upwork: https://www.upwork.com/freelancers/~011846815b093cf1d1
- Fiverr: https://www.fiverr.com/yurij1221

Access is always by GitHub invitation or project share link. I never ask for passwords, and all secrets stay in your own Supabase and Stripe dashboards.

## Contributing

Found a failure mode that is not covered, or a fix that no longer matches the current Lovable/Supabase behaviour? Open an issue with the exact error text and the builder you used. Fixes are kept current as the platforms change.

## License

MIT. Use the SQL, scripts and checklists freely in your own projects.
