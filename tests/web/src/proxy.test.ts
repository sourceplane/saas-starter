import { beforeEach, describe, expect, it, vi } from 'vitest';
import { NextRequest } from 'next/server';

// proxy.ts (upstream's middleware.ts under Next 16's name) is the one piece of
// request logic that decides something: /dashboard* needs a session cookie,
// a valid cookie is re-signed for another day on GET, an invalid one is
// dropped.
const SECRET = 'test-auth-secret-at-least-32-bytes-long-for-hs256';

function request(pathname: string, session?: string) {
  return new NextRequest(new URL(pathname, 'https://app.example.com'), {
    headers: session ? { cookie: `session=${session}` } : undefined
  });
}

describe('proxy (proxy.ts)', () => {
  beforeEach(() => {
    vi.resetModules();
    process.env.AUTH_SECRET = SECRET;
    vi.spyOn(console, 'error').mockImplementation(() => {});
  });

  it('sends a signed-out visitor of /dashboard to /sign-in', async () => {
    const { proxy } = await import('@/proxy');
    for (const p of ['/dashboard', '/dashboard/activity', '/dashboard/security']) {
      const res = await proxy(request(p));
      expect(res.status, p).toBe(307);
      expect(new URL(res.headers.get('location')!).pathname, p).toBe('/sign-in');
    }
  });

  it('lets a signed-out visitor see the public pages', async () => {
    const { proxy } = await import('@/proxy');
    for (const p of ['/', '/pricing', '/sign-in', '/sign-up']) {
      const res = await proxy(request(p));
      expect(res.status, p).toBe(200);
      expect(res.headers.get('location'), p).toBeNull();
    }
  });

  it('lets a signed-in user into /dashboard and refreshes the cookie on GET', async () => {
    const { signToken, verifyToken } = await import('@/lib/auth/session');
    const { proxy } = await import('@/proxy');
    const token = await signToken({
      user: { id: 7 },
      expires: new Date(Date.now() + 60_000).toISOString()
    });
    const res = await proxy(request('/dashboard', token));
    expect(res.status).toBe(200);
    const refreshed = res.cookies.get('session');
    expect(refreshed?.value).toBeTruthy();
    expect(refreshed?.httpOnly).toBe(true);
    const payload = await verifyToken(refreshed!.value);
    expect(payload.user).toEqual({ id: 7 });
    expect(new Date(payload.expires).getTime()).toBeGreaterThan(Date.now() + 23 * 60 * 60 * 1000);
  });

  it('drops an invalid cookie and redirects a protected request', async () => {
    const { proxy } = await import('@/proxy');
    const res = await proxy(request('/dashboard', 'not-a-jwt'));
    expect(res.status).toBe(307);
    expect(new URL(res.headers.get('location')!).pathname).toBe('/sign-in');
  });
});
