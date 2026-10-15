# apps/web — the app

A SaaS application from Vercel's
[Next.js SaaS Starter](https://github.com/nextjs/saas-starter) (MIT, see
`LICENSE`), running on Cloudflare Workers + Static Assets:

- Marketing landing page (`/`) with an animated terminal
- Pricing page (`/pricing`) connected to Stripe Checkout — or, until Stripe is
  connected, the template's plans and a notice saying so
- Dashboard pages with CRUD on users and teams, owner and member roles
- Subscription management with the Stripe Customer Portal
- Email/password authentication with a JWT in a cookie, a proxy that guards
  `/dashboard` and refreshes the session, validated server actions
- An activity log of every user event
- `/api/health`, which answers 200 only when the database is reachable through
  Hyperdrive and migrated

The product's name is `lib/site.ts`. The database client is built per request
over the `HYPERDRIVE` binding (`lib/db/drizzle.ts`); the session key is
`AUTH_SECRET` or the one the database generated (`lib/auth/secret.ts`); the
Stripe client exists only once `STRIPE_SECRET_KEY` does
(`lib/payments/stripe.ts`).

```bash
pnpm dev          # next dev on http://localhost:3000
pnpm build        # next build + opennextjs-cloudflare build → .open-next/
pnpm preview      # wrangler dev over the built Worker
pnpm db:migrate   # drizzle-kit, against POSTGRES_URL
pnpm db:seed      # the test user (test@test.com / admin123) and, with a key, the Stripe products
```

How it runs locally, how it deploys — per environment, after the Supabase
project, the Hyperdrive config and the migrations, on merge to `main` — and
how to connect Stripe are the repository's README and `component.yaml`
beside this file.
