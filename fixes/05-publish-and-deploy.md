# Fix 5: Publish, custom domains and deploying the exported code

Builder: Lovable (Publish + Domains), Bolt (Netlify), Replit (Deployments), or any exported React/Vite + Supabase project deployed to Vercel or Netlify.

## Symptoms

| What you see | What it usually means |
|---|---|
| Works in the editor preview, published site is a **blank white page** | A runtime error on load (open the console): usually an env variable that is `undefined` in production, or a hardcoded preview/localhost URL |
| Published site still shows the old version | You edited but did not re-publish. Builders keep "preview" and "published" separate; the changes go live only after **Publish → Update** |
| Direct link to `/dashboard` or a page **refresh gives 404**, but navigating from the home page works | SPA routing: the host looks for a file called `dashboard` instead of serving `index.html`. Needs a rewrite rule |
| Custom domain "pending" for hours, or shows the host's parking page | DNS records not added, added at the wrong host (apex vs `www`), or still cached; SSL is issued only after DNS resolves |
| `This site can't provide a secure connection` on the custom domain | Certificate not issued yet (wait for DNS), or you pointed DNS before adding the domain in the builder |
| Login works on `*.lovable.app` but not on the custom domain | Supabase redirect allow list and Site URL still point at the preview domain; see [Fix 2](02-auth-redirects.md) |
| Build fails on Vercel/Netlify after GitHub export (`tsc` errors, `Cannot find module`, `ERR_PNPM_OUTDATED_LOCKFILE`, Node version) | The builder's environment was more forgiving than CI: TypeScript errors that were warnings now fail the build, the lockfile does not match `package.json`, or Node is too old |
| `import.meta.env.VITE_SUPABASE_URL is undefined` | Env vars on the host are missing or lack the `VITE_` prefix (Vite only exposes variables that start with `VITE_`) |
| Mixed-content warnings, images not loading on HTTPS | Assets or API URLs hardcoded as `http://` |
| Publishing is blocked or flagged by the builder's security review | Unresolved findings, almost always RLS or exposed secrets; see [Fix 1](01-supabase-rls.md) and [`scripts/check-bundle-secrets.sh`](../scripts/check-bundle-secrets.sh) |

## Diagnose (5 minutes)

1. Open the **published** URL in a private window with the console open (F12). The first red line tells you whether it is an env problem (`undefined`), a routing problem (404 in Network tab) or a runtime loop ([Fix 3](03-react-render-loops.md)).
2. Run `dig +short yourdomain.com` and `dig +short www.yourdomain.com` (or use a DNS lookup site). Compare with the records the builder's **Domains** panel asks for. Wrong or missing values explain "pending".
3. For a host build failure, read the **first** error in the build log, not the last. Everything after the first error is noise.
4. Run the production build locally: `npm ci && npm run build && npx vite preview`. If it fails locally, it will fail on the host; if it works locally and fails on the host, the difference is env vars, Node version or lockfile.

## Fix

### A. Publishing in the builder

- **Lovable**: top-right **Publish → Update**. Confirm the published URL updates (hard refresh with `Ctrl+Shift+R`). Preview URLs (`id-preview--…lovable.app`) are not the published site.
- **Bolt**: deploys to Netlify from the editor; the deployment you see in the panel is the live one. Re-deploy after every change you want live.
- **Replit**: use **Deployments** (Autoscale or Static), not the dev URL, which sleeps and is not meant for users.

### B. Custom domain

1. Add the domain **in the builder first** (Lovable: Project → Settings → Domains; Vercel: Project → Settings → Domains; Netlify: Domain management). It will show the exact DNS records to create.
2. Create those records at your DNS provider (where you bought the domain, or Cloudflare if you moved DNS there). Typically an `A` record for the apex (`@`) and a `CNAME` for `www`, sometimes a `TXT` for verification. Copy the values from the panel; do not reuse values from a blog post, they change.
3. If you use Cloudflare, set the records to **DNS only** (grey cloud) until the certificate is issued; proxied records often break verification.
4. Wait. DNS propagation is minutes to a few hours; the certificate is issued automatically once the panel shows the domain as verified.
5. Pick one canonical host (`www` or apex) and let the other redirect; most hosts do this for you once both records exist.
6. Update **Supabase Auth → Site URL and Redirect URLs** to the new domain ([Fix 2](02-auth-redirects.md)), and any OAuth provider's authorized origins.

### C. SPA routing on Vercel / Netlify (404 on refresh)

Vercel: add `vercel.json` to the project root:

```json
{
  "rewrites": [{ "source": "/(.*)", "destination": "/index.html" }]
}
```

Netlify: add `public/_redirects` (copied into `dist` by Vite):

```
/*    /index.html   200
```

Lovable's own hosting handles this already; the problem appears only after exporting to another host.

### D. Environment variables

- Vite exposes only variables prefixed with `VITE_`. `SUPABASE_URL` is invisible to the browser bundle; `VITE_SUPABASE_URL` is not.
- Set them in the host's dashboard (Vercel: Settings → Environment Variables, for Production **and** Preview; Netlify: Site configuration → Environment variables), then **redeploy**; env changes do not apply to an existing build.
- The anon key and project URL are fine in the browser. The service-role key, Stripe secret key and webhook secret are **not**; they live in edge-function secrets only.
- Lovable projects usually read Supabase credentials from `src/integrations/supabase/client.ts`, generated by the builder. After export, either keep that file or move the values to `VITE_` env vars; do not do both.

### E. Build failures after export

Common causes and the one-line fix for each:

| Error | Fix |
|---|---|
| TypeScript errors fail the build (`tsc -b && vite build`) but the preview worked | Fix the types, or change `"build": "vite build"` in `package.json` while you work through them (Vite does not type-check during build) |
| `ERR_PNPM_OUTDATED_LOCKFILE` / `npm ci` lockfile mismatch | Delete the lockfile that does not match the package manager you use, run `npm install` (or `bun install`) locally, commit the new lockfile |
| Both `bun.lockb` and `package-lock.json` present | Keep one. Lovable uses bun; Vercel and Netlify use whichever lockfile they detect first |
| `Error: Node.js version 18 … is required` or syntax errors from the host's Node | Set Node 20+ in the host (Vercel: Settings → General → Node.js Version; Netlify: `NODE_VERSION` env var or `.nvmrc`) |
| `Cannot find module '@/components/…'` | Path alias: make sure `vite.config.ts` has `resolve.alias['@'] = path.resolve(__dirname, './src')` and `tsconfig.json` has the matching `paths` |
| Case-sensitive import errors (`Button.tsx` vs `button.tsx`) | Linux hosts are case-sensitive; Windows and macOS preview were not. Rename the import to match the file exactly |
| Build runs out of memory | `NODE_OPTIONS=--max-old-space-size=4096` as an env var |

### F. Hardcoded URLs

Search the code for `localhost`, `127.0.0.1`, `lovable.app`, `http://`:

```bash
grep -rn "localhost\|127.0.0.1\|lovable.app\|http://" src/ --include=*.ts --include=*.tsx | grep -v "https://"
```

Replace with `window.location.origin` (for redirects back to your app) or an env variable (for API endpoints).

## Verify

1. Published URL and custom domain both load in a private window with **zero console errors**.
2. Refresh on a deep link (`/dashboard/settings`) loads the page, no 404.
3. `https://` lock icon on both apex and `www`; `http://` redirects to `https://`.
4. Sign-up, login and password reset all return to the custom domain ([Fix 2](02-auth-redirects.md) verify list).
5. `npm run build` passes locally and on the host; the host shows the commit you expect as the production deployment.
6. `scripts/check-bundle-secrets.sh dist` is clean.

## Mistakes to avoid

- Pointing DNS before adding the domain in the builder/host: verification then fails and you wait on nothing.
- Fixing a TypeScript build failure with `// @ts-ignore` everywhere. Changing the build script to skip type-checking is an honest temporary measure; blanket ignores hide real bugs.
- Leaving the preview domain in production emails and OAuth settings. Users will click confirmation links that land on the builder preview.
