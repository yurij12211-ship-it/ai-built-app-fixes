# Fix 4: Stripe payments and Supabase edge functions

Builder: Lovable (Stripe connector or hand-prompted integration), Bolt, Replit, v0 projects using Supabase Edge Functions (Deno) to talk to Stripe.

## Symptoms

| What you see | What it usually means |
|---|---|
| Checkout works in the preview, fails on the live site with `No such price: 'price_…'` | Live **secret key** with **test-mode price IDs** (or the reverse). Price IDs are different objects in test and live mode |
| `Invalid API Key provided` / the builder keeps asking you to "update the Stripe key" | Key revoked, rotated, restricted without the needed permissions, or a **publishable** key (`pk_…`) was stored where a secret key belongs |
| Payment succeeded in Stripe, but the app still shows the free plan | The subscription check matches the Stripe customer by **email**, and the sign-in email differs from the Stripe email; or the check only runs at sign-in and the user has not re-logged; or the webhook that should update the database is failing |
| `Webhook signature verification failed` (`No signatures found matching the expected signature`) | Wrong signing secret (`whsec_…` from a different endpoint or from the CLI), or the function parsed the body as JSON before verifying; verification needs the **raw** body |
| `SubtleCryptoProvider cannot be used in a synchronous context` | The function calls `constructEvent` (sync). In Deno you must use `constructEventAsync` with a SubtleCrypto provider |
| Stripe dashboard shows the webhook returning **401** | The edge function has JWT verification on. Stripe does not send a Supabase JWT, so the gateway rejects it before your code runs |
| `No configuration provided and your test mode default configuration has not been created` | The Stripe **Customer Portal** has not been activated in the Stripe dashboard |
| Browser console: `blocked by CORS policy` when calling the function | The function does not answer the `OPTIONS` preflight or does not return `Access-Control-Allow-Origin` headers |
| Checkout button does nothing | Popup blocked (checkout opens in a new tab), or the function returned an error the UI swallowed; check the function logs |
| Real cards charged while "testing" | A live key is stored. The builder preview has no separate test environment: live key means live money, everywhere |

## How the pieces fit

In a typical Lovable/Bolt setup there are three or four edge functions:

- a **checkout** function that creates a Stripe Checkout Session and returns its URL;
- a **subscription check** function that asks Stripe whether the signed-in user has an active subscription (Lovable's connector matches by email and runs it at sign-in);
- optionally a **webhook** function that Stripe calls when something happens (`checkout.session.completed`, `invoice.paid`, `customer.subscription.deleted`) so your database stays in sync without polling;
- a **customer portal** function that returns a Stripe billing-portal URL.

The Stripe secret key lives in the backend secrets (`STRIPE_SECRET_KEY`), never in the front-end. With Lovable's built-in backend it is under **Settings → Secrets**; with your own Supabase it is **Edge Functions → Secrets** (or `supabase secrets set`). The browser only ever sees the publishable key, and only if you use Stripe.js directly.

## Diagnose (5 minutes)

1. **Stripe → Developers → Logs.** Every failed API call from your functions is here with the exact error. `No such price` and `Invalid API Key` show up immediately.
2. **Stripe → Developers → Webhooks → your endpoint → Events.** Shows each delivery and the HTTP status your function returned. `401` = JWT verification; `400` with signature text = wrong secret or body handling; `500` = your code.
3. **Supabase → Edge Functions → function → Logs** (or Lovable's function logs). Add `console.log` liberally; logs appear here within seconds.
4. **Check the mode of each piece.** Key prefix `sk_test_`/`rk_test_` = test; `sk_live_`/`rk_live_` = live. In Stripe, toggle "Test mode" in the dashboard and look at whether your product/prices exist in **both** modes. They must be created separately in each.
5. **Compare emails.** The email in Supabase `auth.users` for the user vs. the email on the Stripe Customer. If they differ, the email-based check will never find the subscription.

## Fix

### A. Test and live are separate worlds

Keep two sets of values and switch them together:

| | Test | Live |
|---|---|---|
| Secret key | `sk_test_…` / `rk_test_…` | `sk_live_…` / `rk_live_…` |
| Price IDs | `price_…` created in test mode | `price_…` created in live mode |
| Webhook endpoint + signing secret | endpoint created in test mode, its own `whsec_…` | endpoint created in live mode, its own `whsec_…` |
| Customer portal configuration | activated in test mode | activated in live mode |

Store price IDs as secrets or in a config table, not hardcoded in the UI, so switching modes is one change. Verify a live purchase with a real card for the smallest amount and refund it.

### B. Webhook function that actually verifies

`supabase/functions/stripe-webhook/index.ts`:

```ts
import Stripe from "https://esm.sh/stripe@17?target=denonext";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY")!, {
  apiVersion: "2024-06-20",
  httpClient: Stripe.createFetchHttpClient(),
});
const cryptoProvider = Stripe.createSubtleCryptoProvider();

const supabaseAdmin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,   // server-side only, never in the browser
);

Deno.serve(async (req) => {
  const signature = req.headers.get("stripe-signature");
  if (!signature) return new Response("Missing signature", { status: 400 });

  // 1. read the RAW body as text; do not call req.json() before verifying
  const body = await req.text();

  let event: Stripe.Event;
  try {
    // 2. async verification is required in Deno
    event = await stripe.webhooks.constructEventAsync(
      body,
      signature,
      Deno.env.get("STRIPE_WEBHOOK_SECRET")!,
      undefined,
      cryptoProvider,
    );
  } catch (err) {
    console.error("Signature verification failed:", err.message);
    return new Response(`Webhook Error: ${err.message}`, { status: 400 });
  }

  // 3. idempotency: Stripe retries, so never process the same event twice
  const { error: dupErr } = await supabaseAdmin
    .from("stripe_events")
    .insert({ id: event.id, type: event.type });
  if (dupErr?.code === "23505") return new Response("Already processed", { status: 200 });

  // 4. handle what you need, acknowledge everything else
  switch (event.type) {
    case "checkout.session.completed": {
      const session = event.data.object as Stripe.Checkout.Session;
      await supabaseAdmin.from("subscriptions").upsert({
        user_id: session.client_reference_id,      // set this when creating the session
        stripe_customer_id: session.customer as string,
        stripe_subscription_id: session.subscription as string,
        status: "active",
      }, { onConflict: "user_id" });
      break;
    }
    case "customer.subscription.updated":
    case "customer.subscription.deleted": {
      const sub = event.data.object as Stripe.Subscription;
      await supabaseAdmin.from("subscriptions")
        .update({ status: sub.status })
        .eq("stripe_subscription_id", sub.id);
      break;
    }
  }

  return new Response(JSON.stringify({ received: true }), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
});
```

Supporting table (RLS on, no policies: only the service role touches it, see [Fix 1, pattern D](01-supabase-rls.md)):

```sql
create table if not exists public.stripe_events (
  id text primary key,
  type text not null,
  received_at timestamptz not null default now()
);
alter table public.stripe_events enable row level security;
```

### C. Let Stripe call the function without a JWT

`supabase/config.toml`:

```toml
[functions.stripe-webhook]
verify_jwt = false
```

Deploy again after changing this. Keep `verify_jwt = true` (the default) for the functions your **browser** calls (checkout, portal, subscription check) so only signed-in users can invoke them. If the dashboard offers a per-function "Verify JWT" toggle, it does the same thing.

Register the endpoint in **Stripe → Developers → Webhooks → Add endpoint** with the URL

```
https://<project-ref>.supabase.co/functions/v1/stripe-webhook
```

select the events you handle, then copy the endpoint's signing secret into the `STRIPE_WEBHOOK_SECRET` backend secret. The CLI's `stripe listen` prints a **different** secret that only works for local forwarding.

### D. CORS for functions called from the browser

```ts
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",   // or your exact domain
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    // ... your logic ...
    return new Response(JSON.stringify({ url }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: err.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
```

Every response, including errors, must carry the CORS headers, or the browser reports a CORS error instead of your real error message.

### E. Checkout session that your webhook can match to a user

```ts
const session = await stripe.checkout.sessions.create({
  mode: "subscription",
  line_items: [{ price: Deno.env.get("STRIPE_PRICE_PRO")!, quantity: 1 }],
  customer_email: user.email,          // or `customer` if you already created one
  client_reference_id: user.id,        // lets the webhook link the payment to the Supabase user
  success_url: `${origin}/billing/success?session_id={CHECKOUT_SESSION_ID}`,
  cancel_url: `${origin}/billing`,
  allow_promotion_codes: true,
});
```

Matching by `client_reference_id` (the Supabase user id) is more reliable than matching by email.

### F. Customer portal

Activate it once per mode: **Stripe → Settings → Billing → Customer portal → Activate** (choose what customers may do: cancel, switch plan, update card). Then the function:

```ts
const portal = await stripe.billingPortal.sessions.create({
  customer: stripeCustomerId,
  return_url: `${origin}/billing`,
});
return new Response(JSON.stringify({ url: portal.url }), { headers: corsHeaders });
```

The portal does not open inside the builder's preview iframe; test it on the published site or in a standalone tab.

## Verify

1. **Test mode, end to end**: buy with card `4242 4242 4242 4242`; the webhook endpoint shows `200`; the `subscriptions` row appears; the UI unlocks without re-login (or after a refresh if the UI reads the table on load).
2. **Signature check**: send a test event from the Stripe dashboard ("Send test webhook"); it returns `200`. Change one character of `STRIPE_WEBHOOK_SECRET` and resend: it must return `400`. Restore the secret.
3. **Idempotency**: resend the same event from the dashboard; the second delivery returns `200` and creates no duplicate rows.
4. **Live mode**: smallest real purchase, then refund from the dashboard; `subscriptions` row updates; portal opens.
5. `scripts/check-bundle-secrets.sh dist` finds no `sk_`, `rk_`, `whsec_` or service-role strings in the built front-end.

## Mistakes to avoid

- Shipping the Stripe secret or the Supabase service-role key to the browser "because the function call failed". Fix the function instead.
- Skipping signature verification "temporarily". An unverified webhook endpoint lets anyone mark themselves as paid with one `curl`.
- Trusting the client: never let the front-end tell the backend "the user paid". The backend learns it from Stripe (webhook or direct API check) only.
- Using the same `whsec_` for test and live, or copying it from `stripe listen`.
