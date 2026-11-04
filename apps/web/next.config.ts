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
  outputFileTracingRoot: path.join(__dirname, '../..'),
  // Dev server only (`next build` ignores it): orun.work's live Preview tab
  // loads `next dev` from the preview's own host, and Next.js refuses the
  // hot reload and other /_next/* dev requests from an origin it is not told
  // about. These are the preview's hosts, prod's and stage's.
  allowedDevOrigins: ['*.orun-preview.app', 'preview-gateway-stage.oruncloud.workers.dev'],
  experimental: {
    // Dev server only: behind orun.work's live Preview the browser's Origin
    // is the preview's host while `next dev` sees a local Host, and Next.js
    // refuses a Server Action from an origin it is not told about. `next
    // build` runs with NODE_ENV=production, so production keeps its
    // same-origin check.
    ...(process.env.NODE_ENV === 'development'
      ? { serverActions: { allowedOrigins: ['*.orun-preview.app', 'preview-gateway-stage.oruncloud.workers.dev'] } }
      : {})
  }
};

// `next dev` gets the Worker's bindings (the HYPERDRIVE binding, pointed at
// the local Postgres by wrangler.jsonc's localConnectionString) through
// getCloudflareContext(); a no-op at build time.
initOpenNextCloudflareForDev();

export default nextConfig;
