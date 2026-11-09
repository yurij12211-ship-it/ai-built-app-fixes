# Fix 2: Auth and redirect URLs (Supabase Auth)

Builder: Lovable, Bolt, Replit, Base44, v0 or any app using Supabase Auth (email + password, magic links, Google/GitHub OAuth).

## Symptoms

| What you see | What it usually means |
|---|---|
| The confirmation / magic-link email opens `http://localhost:3000` | **Site URL** in Supabase is still the default `http://localhost:3000` |
| Confirmation opens the preview URL instead of your custom domain | Site URL points to the builder preview; the custom domain is not in **Redirect URLs** |
| `Email link is invalid or has expired` the first time you click it | The link was already consumed, usually by an email scanner (Outlook Safe Links, corporate gateways) that pre-fetches links, or the user clicked twice |
| `redirect_uri_mismatch` from Google | The Google OAuth client does not list `https://<project-ref>.supabase.co/auth/v1/callback` as an authorized redirect URI |
| Google / GitHub login works in preview, fails on the published site | Your production origin is not in the Supabase **Redirect URLs** allow list, so Supabase falls back to Site URL |
| Redirect loop after login (`/login` → `/dashboard` → `/login` …) | The protected-route guard checks `session` before the auth client finished loading it (`loading` state missing), or two components both navigate on auth change |
| Logged in, refresh the page, logged out | Session persistence disabled, or the app reads the user once on mount and never subscribes to `onAuthStateChange` |
| Password reset link lands on the home page, not the "set new password" form | `redirectTo` on `resetPasswordForEmail` is missing or not in the allow list |

## Why it happens

Supabase Auth only redirects to URLs it has been told about. Two settings in **Supabase → Authentication → URL Configuration** control everything:

- **Site URL**: the default destination. Also used as the fallback whenever a requested `redirectTo` is not allowed.
- **Redirect URLs**: an allow list. Any `emailRedirectTo` / `redirectTo` your code passes must match an entry here (wildcards allowed), otherwise it is silently replaced by Site URL.

AI builders set none of this. They leave Site URL at `localhost:3000` and pass whatever `window.location.origin` is at the time, which in the builder's preview is the preview domain. The moment you publish on a real domain, every email points to the wrong place.

OAuth adds a second layer: the **provider** (Google, GitHub) has its own allow list, and it must contain Supabase's callback URL, not your site's URL.

## Diagnose (5 minutes)

1. **Supabase → Authentication → URL Configuration.** Write down the Site URL and every Redirect URL. If Site URL is `localhost`, you have found problem #1.
2. **Open the confirmation email** (or its source) and look at the link. The `redirect_to=` parameter shows where Supabase will send the user after verification. If it is not your production URL, the allow list rejected your `redirectTo`.
3. **Browser dev tools → Network** while logging in with Google. The request to `/auth/v1/authorize?...&redirect_to=...` shows what the app asked for.
4. **For the redirect loop**: add `console.log(event, session)` inside `onAuthStateChange`. If you see `INITIAL_SESSION` with `null` followed by `SIGNED_IN`, your guard is redirecting on the first event before the session loads.

## Fix

### A. Set the URL configuration correctly

In **Supabase → Authentication → URL Configuration**:

- **Site URL**: your production URL, e.g. `https://app.example.com`
- **Redirect URLs** (one per line):

  ```
  https://app.example.com/**
  https://www.example.com/**
  https://<your-project>.lovable.app/**
  https://*.lovable.app/**
  http://localhost:3000/**
  http://localhost:5173/**
  ```

Adjust the preview domain to your builder (`*.bolt.host`, `*.replit.app`, `*.vercel.app` for Vercel previews). `**` matches any path; `*` matches one segment of a hostname.

Lovable's built-in backend ("Lovable Cloud") exposes the same settings under its Cloud → Authentication panel; if you cannot find them, ask the builder: *"Set the auth Site URL to https://app.example.com and add https://app.example.com/** to the redirect allow list."*

### B. Pass an explicit redirect from code

Do not rely on the default. Every auth call that sends an email or starts OAuth should say where to come back:

```ts
// sign-up with email confirmation
await supabase.auth.signUp({
  email,
  password,
  options: { emailRedirectTo: `${window.location.origin}/auth/callback` },
});

// magic link
await supabase.auth.signInWithOtp({
  email,
  options: { emailRedirectTo: `${window.location.origin}/auth/callback` },
});

// password reset
await supabase.auth.resetPasswordForEmail(email, {
  redirectTo: `${window.location.origin}/auth/reset-password`,
});

// OAuth
await supabase.auth.signInWithOAuth({
  provider: "google",
  options: { redirectTo: `${window.location.origin}/auth/callback` },
});
```

`window.location.origin` is correct **only if** every origin you deploy to is in the allow list (step A). That is why both steps are needed.

### C. Add a callback route

Create `/auth/callback` that waits for the session and then navigates:

```tsx
// src/pages/AuthCallback.tsx
import { useEffect } from "react";
import { useNavigate } from "react-router-dom";
import { supabase } from "@/integrations/supabase/client";

export default function AuthCallback() {
  const navigate = useNavigate();

  useEffect(() => {
    const { data: { subscription } } = supabase.auth.onAuthStateChange((event, session) => {
      if (session) navigate("/dashboard", { replace: true });
      if (event === "SIGNED_OUT") navigate("/login", { replace: true });
    });
    // handle the case where the session is already there
    supabase.auth.getSession().then(({ data }) => {
      if (data.session) navigate("/dashboard", { replace: true });
    });
    return () => subscription.unsubscribe();
  }, [navigate]);

  return <p>Signing you in…</p>;
}
```

### D. Fix the redirect loop with a loading state

```tsx
// src/hooks/useAuth.tsx
import { createContext, useContext, useEffect, useState } from "react";
import type { Session } from "@supabase/supabase-js";
import { supabase } from "@/integrations/supabase/client";

const AuthContext = createContext<{ session: Session | null; loading: boolean }>({
  session: null,
  loading: true,
});

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [session, setSession] = useState<Session | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    // 1. subscribe first so no event is missed
    const { data: { subscription } } = supabase.auth.onAuthStateChange((_event, s) => {
      setSession(s);
      setLoading(false);
    });
    // 2. then read the current session
    supabase.auth.getSession().then(({ data }) => {
      setSession(data.session);
      setLoading(false);
    });
    return () => subscription.unsubscribe();
  }, []);

  return <AuthContext.Provider value={{ session, loading }}>{children}</AuthContext.Provider>;
}

export const useAuth = () => useContext(AuthContext);
```

```tsx
// src/components/ProtectedRoute.tsx
import { Navigate } from "react-router-dom";
import { useAuth } from "@/hooks/useAuth";

export function ProtectedRoute({ children }: { children: React.ReactNode }) {
  const { session, loading } = useAuth();
  if (loading) return null;                    // do NOT redirect while loading
  if (!session) return <Navigate to="/login" replace />;
  return <>{children}</>;
}
```

The loop comes from redirecting during `loading`. One guard component, one place that navigates.

### E. Links "expire" on first click (email scanners)

Corporate mail filters open links before the user does, which consumes one-time tokens. Two robust options:

1. **Use a confirmation page with a button.** Point `emailRedirectTo` to `/auth/confirm`, which shows "Click to continue" and only then calls `supabase.auth.verifyOtp({ token_hash, type })` with the values from the URL. Scanners load the page but do not click. This requires changing the email template to use `{{ .TokenHash }}` instead of `{{ .ConfirmationURL }}` (Supabase → Authentication → Email Templates).
2. **Use a 6-digit OTP code** instead of a link (`signInWithOtp` + `verifyOtp` with `type: "email"`). Nothing to pre-fetch.

### F. OAuth provider settings

In **Google Cloud Console → Credentials → your OAuth client → Authorized redirect URIs** add exactly:

```
https://<project-ref>.supabase.co/auth/v1/callback
```

Your own domain goes in **Authorized JavaScript origins**, not in redirect URIs. For GitHub OAuth apps the "Authorization callback URL" is the same Supabase URL. For Lovable Cloud projects the callback host is the one shown in the Cloud → Authentication → Providers panel; copy it from there rather than guessing.

## Verify

1. Sign up with a brand-new email on the **published** site. The confirmation link must open your production domain and land on `/auth/callback`, then the dashboard.
2. Do the same from a private window (no existing session).
3. Request a password reset; the link must open the reset form, and the new password must work.
4. Google login from the published site, from the preview, and from localhost: all three must return to the origin they started from.
5. Refresh the dashboard: you stay logged in. Open the dashboard URL in a private window: you are sent to `/login` **once**, with no loop.

## Mistakes to avoid

- Turning off "Confirm email" in production to make sign-up "work". Fine for a demo; in production it lets anyone register with someone else's address.
- Putting your site URL into Google's redirect URIs. Google must redirect to Supabase, and Supabase redirects to you.
- Forgetting the `www` variant or the preview domain in the allow list, then wondering why only some users have the problem.
