import type { NextConfig } from 'next';
import path from 'node:path';
import { initOpenNextCloudflareForDev } from '@opennextjs/cloudflare';

// Upstream (Next 15 canary) enabled `experimental.ppr` and
// `experimental.clientSegmentCache`. Next 16 rejects the first ("merged into
// cacheComponents", which would mean restructuring the pricing page's
// `revalidate` and the root layout's cookie read) and no longer knows the
// second; both are dropped. Every route is dynamic either way: the root
// layout reads the session cookie.
const nextConfig: NextConfig = {
  // Required by @opennextjs/cloudflare, which bundles `.next/standalone/**`
  // into the Worker. Trace from the monorepo root so workspace dependencies
  // resolve from the root node_modules.
  output: 'standalone',
  outputFileTracingRoot: path.join(__dirname, '../..')
};

// `next dev` gets the Worker's bindings (the HYPERDRIVE binding, pointed at
// the local Postgres by wrangler.jsonc's localConnectionString) through
// getCloudflareContext(); a no-op at build time.
initOpenNextCloudflareForDev();

export default nextConfig;
