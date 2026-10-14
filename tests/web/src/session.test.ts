import { beforeEach, describe, expect, it, vi } from 'vitest';

// lib/auth/session.ts is the template's auth: a bcrypt password hash and an
// HS256 JWT (jose) in the `session` cookie. It derives the signing key from
// AUTH_SECRET when the module loads, so every suite imports it fresh.
const SECRET = 'test-auth-secret-at-least-32-bytes-long-for-hs256';

describe('session tokens (lib/auth/session.ts)', () => {
  beforeEach(() => {
    vi.resetModules();
    process.env.AUTH_SECRET = SECRET;
  });

  it('signs a session that verifies back to the same payload', async () => {
    const { signToken, verifyToken } = await import('@/lib/auth/session');
    const expires = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString();
    const token = await signToken({ user: { id: 42 }, expires });
    expect(token.split('.')).toHaveLength(3);
    const payload = await verifyToken(token);
    expect(payload.user).toEqual({ id: 42 });
    expect(payload.expires).toBe(expires);
  });

  it('rejects a token signed under another secret', async () => {
    const { signToken } = await import('@/lib/auth/session');
    const token = await signToken({
      user: { id: 1 },
      expires: new Date(Date.now() + 60_000).toISOString()
    });
    vi.resetModules();
    process.env.AUTH_SECRET = 'a-different-secret-that-is-also-long-enough';
    const { verifyToken } = await import('@/lib/auth/session');
    await expect(verifyToken(token)).rejects.toThrow();
  });

  it('rejects a tampered token', async () => {
    const { signToken, verifyToken } = await import('@/lib/auth/session');
    const token = await signToken({
      user: { id: 1 },
      expires: new Date(Date.now() + 60_000).toISOString()
    });
    const [header, , signature] = token.split('.');
    const forged = `${header}.${Buffer.from('{"user":{"id":2}}').toString('base64url')}.${signature}`;
    await expect(verifyToken(forged)).rejects.toThrow();
  });
});

describe('passwords (lib/auth/session.ts)', () => {
  beforeEach(() => {
    vi.resetModules();
    process.env.AUTH_SECRET = SECRET;
  });

  it('hashes a password with bcrypt and compares it', async () => {
    const { hashPassword, comparePasswords } = await import('@/lib/auth/session');
    const hash = await hashPassword('admin123');
    expect(hash).not.toBe('admin123');
    expect(hash.startsWith('$2')).toBe(true);
    expect(await comparePasswords('admin123', hash)).toBe(true);
    expect(await comparePasswords('admin124', hash)).toBe(false);
  });
});
