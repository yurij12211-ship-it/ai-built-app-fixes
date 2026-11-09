# Launch-readiness checklist for AI-built apps

32 checks, grouped so you can do them in an afternoon. Each line says how to check it, not just what. Tick everything in sections 1–4 before real users; sections 5–7 before real money or real marketing.

Legend: **[auto]** has a script in this repo · **[2 users]** needs two test accounts · **[prod]** test on the published URL, not the preview.

## 1. Data and security

- [ ] **Every table the browser touches has RLS on** — run [`scripts/rls_audit.sql`](../scripts/rls_audit.sql); result set 1 empty. [auto]
- [ ] **Every RLS-on table has policies, or is deliberately server-only** — result set 2 empty or documented. [auto]
- [ ] **No `USING (true)` policies on private data** — result set 3 empty or documented (public catalogs only). [auto]
- [ ] **Two users cannot see each other's data via the API** — curl the REST endpoint with user B's token; expect `[]`. [2 users]
- [ ] **Anonymous requests get nothing private** — same curl without `Authorization`. [prod]
- [ ] **No server secrets in the front-end build** — `bash scripts/check-bundle-secrets.sh dist` is clean. [auto]
- [ ] **Service-role key appears only in edge-function secrets** — search the repo: `grep -rn "service_role" src/` returns nothing.
- [ ] **Storage buckets that hold user files are private with owner policies** — try to open another user's file URL while logged in as B. [2 users]
- [ ] **Edge functions the browser calls keep `verify_jwt = true`; only webhooks disable it** — review `supabase/config.toml`.
- [ ] **The builder's security scan is green** (Lovable "Security review", Bolt/Supabase advisors) — rerun after every schema change.

## 2. Auth

- [ ] **Site URL is the production domain** — Supabase → Authentication → URL Configuration.
- [ ] **Redirect allow list contains production, `www`, preview and localhost** — same panel.
- [ ] **Sign-up confirmation email lands on the production domain** — sign up with a fresh address. [prod]
- [ ] **Password reset works end to end** — request, click, set, log in with the new password. [prod]
- [ ] **OAuth providers return to the right origin from production, preview and localhost** — three logins. [prod]
- [ ] **Protected routes redirect once, no loop; refresh keeps you logged in** — open a deep link in a private window, then log in and refresh. [prod]
- [ ] **Email confirmation is ON in production** — Authentication → Providers → Email.

## 3. Reliability

- [ ] **No console errors on any main page** — open each route with F12 open. [prod]
- [ ] **No render loops or repeated requests** — Network tab stays quiet after a page settles ([Fix 3](../fixes/03-react-render-loops.md)).
- [ ] **Empty states and error states exist** — new account with zero data shows a sensible screen, not a blank one or a crash.
- [ ] **Forms validate and show errors** — submit empty, submit wrong email, submit twice quickly.
- [ ] **Mobile layout works** — open on a phone or at 375 px width; nothing overflows, buttons are tappable.
- [ ] **Backups** — Supabase Pro has daily backups (PITR as an add-on); on the free plan schedule your own `pg_dump` or at least export critical tables weekly.

## 4. Deploy and domain

- [ ] **Published version is the current version** — the published site shows your latest change after Publish → Update. [prod]
- [ ] **Custom domain resolves on apex and `www`, HTTPS lock on both** — [Fix 5](../fixes/05-publish-and-deploy.md). [prod]
- [ ] **Deep-link refresh does not 404** — refresh on `/dashboard/anything`. [prod]
- [ ] **Env vars are set on the host for Production and Preview** — and the build was redeployed after setting them.
- [ ] **No hardcoded `localhost` / preview URLs** — `grep -rn "localhost\|lovable.app" src/`.

## 5. Payments (if you charge money)

- [ ] **Live key with live price IDs, test key with test price IDs** — never mixed ([Fix 4](../fixes/04-stripe-edge-functions.md)).
- [ ] **Webhook verifies signatures and returns 200 in the Stripe dashboard** — send a test event; change the secret and confirm a 400.
- [ ] **Paid status comes only from Stripe (webhook or server-side check), never from the client** — read the checkout and subscription code.
- [ ] **One real live purchase done and refunded; customer portal opens** — smallest price, then refund. [prod]

## 6. Legal and trust (before marketing)

- [ ] Privacy policy and terms pages exist and are linked in the footer; the privacy policy names Supabase and Stripe as processors.
- [ ] Cookie/consent notice if you use analytics or ads pixels and have EU/UK visitors.
- [ ] A support email that a human reads, shown in the app and in Stripe receipts (Stripe → Settings → Public details).
- [ ] Account deletion path: a button, or at least a documented email request, that actually deletes `auth.users` and cascades.

## 7. Operations

- [ ] Error monitoring (Sentry free tier or the host's logs) so you learn about crashes before users email you.
- [ ] Supabase usage alerts: watch egress and database size on the free/Pro plan; a render loop can exhaust them in a day.
- [ ] You can export your code and database (GitHub connected; `pg_dump` tested once) so you are not locked into the builder.
- [ ] A short runbook: where the secrets live, how to rotate the Stripe key, how to roll back a deployment.

---

Done with all of it? You are ahead of most AI-built apps that go live. If any line in sections 1, 2 or 5 is not ticked and you are not sure how to fix it, that is exactly what the free 24-hour diagnosis is for (see the [README](../README.md)).
