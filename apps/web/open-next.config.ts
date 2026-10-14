// OpenNext Cloudflare adapter config.
//
// Every route of this template renders per request — the root layout reads
// the session cookie, the pricing page reads Stripe — so the build
// pre-renders nothing and no incremental cache is exercised. The read-only
// static-assets cache is kept as the default that costs nothing to
// provision: a page that becomes static later is served from it, and a page
// that revalidates for real (ISR, `revalidateTag`) is the signal to swap in
// the R2 incremental cache plus a tag cache.
import { defineCloudflareConfig } from '@opennextjs/cloudflare/config';
import staticAssetsIncrementalCache from '@opennextjs/cloudflare/overrides/incremental-cache/static-assets-incremental-cache';

export default defineCloudflareConfig({
  incrementalCache: staticAssetsIncrementalCache
});
