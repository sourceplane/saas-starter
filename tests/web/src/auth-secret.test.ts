import { beforeEach, describe, expect, it, vi } from 'vitest';

// lib/auth/secret.ts: the session-signing key is AUTH_SECRET when one is set,
// and otherwise the key the environment's database generated for itself
// (migration 020_app_secrets) — read once per isolate. The database client is
// mocked: what is tested is which key wins and when the database is asked.
const execute = vi.fn();
const getDb = vi.fn(async () => ({ execute }));

vi.mock('@/lib/db/drizzle', () => ({ getDb: () => getDb() }));

const STORED = 'a'.repeat(64);

describe('the session key (lib/auth/secret.ts)', () => {
  beforeEach(() => {
    vi.resetModules();
    execute.mockReset();
    getDb.mockClear();
    delete process.env.AUTH_SECRET;
  });

  it('is AUTH_SECRET when one is set, without asking the database', async () => {
    process.env.AUTH_SECRET = 'an-owner-set-secret-of-enough-length';
    const { authSecret } = await import('@/lib/auth/secret');
    expect(await authSecret()).toBe('an-owner-set-secret-of-enough-length');
    expect(getDb).not.toHaveBeenCalled();
  });

  it('is the stored key otherwise, read once per isolate', async () => {
    execute.mockResolvedValue([{ value: STORED }]);
    const { authSecret } = await import('@/lib/auth/secret');
    expect(await authSecret()).toBe(STORED);
    expect(await authSecret()).toBe(STORED);
    expect(execute).toHaveBeenCalledTimes(1);
  });

  it('names the missing migration when there is neither', async () => {
    execute.mockResolvedValue([]);
    const { authSecret } = await import('@/lib/auth/secret');
    await expect(authSecret()).rejects.toThrow(/020_app_secrets/);
  });

  it('signs and verifies a session with the stored key', async () => {
    execute.mockResolvedValue([{ value: STORED }]);
    const { signToken, verifyToken } = await import('@/lib/auth/session');
    const expires = new Date(Date.now() + 60_000).toISOString();
    const token = await signToken({ user: { id: 3 }, expires });
    expect((await verifyToken(token)).user).toEqual({ id: 3 });
  });

  it('refuses a session signed under AUTH_SECRET once the stored key is in use', async () => {
    process.env.AUTH_SECRET = 'an-owner-set-secret-of-enough-length';
    const { signToken } = await import('@/lib/auth/session');
    const token = await signToken({
      user: { id: 3 },
      expires: new Date(Date.now() + 60_000).toISOString()
    });
    vi.resetModules();
    delete process.env.AUTH_SECRET;
    execute.mockResolvedValue([{ value: STORED }]);
    const { verifyToken } = await import('@/lib/auth/session');
    await expect(verifyToken(token)).rejects.toThrow();
  });
});
