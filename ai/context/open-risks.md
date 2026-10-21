# saas-starter — open risks

What is not yet proven or not yet decided. The full write-up of every risk,
including the accepted and resolved ones, is
`specs/epics/saas-starter/risks-and-open-questions.md`; this page lists only
what is still live, so it should be short.

| ID | Risk | State | What closes it |
|---|---|---|---|
| SA-M | No bootstrap has been timed (the card's twenty minutes is summed from estimates); neither Terraform root has been applied from this repository and db-migrate has not run against a real project — so whether `postgres` owns the tables there, which migration `030`'s guard checks before it enables RLS (SA-L), is also unobserved | OPEN | One bootstrap from a tag against a workspace with Cloudflare and Supabase connected |

Accepted, and worth knowing before you change them: SA-A (a `postgres`
client per request), SA-D (the deploy sets no Worker secret; Stripe's keys
are the owner's), SA-E (migrations through the Management API, autocommit),
SA-F (Stripe products come from the seed, test mode), SA-G (local
development needs a Postgres on 54322), SA-N (the bootstrap floor plans
`modeRules` as enforced).
