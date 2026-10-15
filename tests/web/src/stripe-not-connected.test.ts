import { beforeEach, describe, expect, it, vi } from 'vitest';
import { NextRequest } from 'next/server';

// A deployment starts with no STRIPE_SECRET_KEY: Stripe is a third party no
// platform brokers, and its owner adds the key (README, "Connect Stripe").
// Until then nothing may fail on it — lib/payments/stripe.ts never builds the
// client, checkout and the portal send the visitor to the pricing page (which
// says Stripe is not connected), and the checkout callback does the same.
// No network: with no key, nothing reaches Stripe.

function redirectTarget(error: unknown): string | undefined {
  // next/navigation's redirect() throws; its digest carries the location.
  const digest = (error as { digest?: string })?.digest ?? '';
  return digest.startsWith('NEXT_REDIRECT') ? digest.split(';')[2] : undefined;
}

describe('Stripe, not connected (lib/payments/stripe.ts)', () => {
  beforeEach(() => {
    vi.resetModules();
    delete process.env.STRIPE_SECRET_KEY;
    delete process.env.STRIPE_WEBHOOK_SECRET;
  });

  it('reports itself unconfigured and refuses to build a client', async () => {
    const { getStripe, stripeConfigured } = await import('@/lib/payments/stripe');
    expect(stripeConfigured()).toBe(false);
    expect(() => getStripe()).toThrow(/Stripe is not connected/);
  });

  it('sends checkout to the pricing page instead of calling Stripe', async () => {
    const { createCheckoutSession } = await import('@/lib/payments/stripe');
    const error = await createCheckoutSession({ team: null, priceId: 'price_1' }).catch((e) => e);
    expect(redirectTarget(error)).toBe('/pricing');
  });

  it('sends the customer portal to the pricing page too', async () => {
    const { createCustomerPortalSession } = await import('@/lib/payments/stripe');
    const team = { stripeCustomerId: 'cus_1', stripeProductId: 'prod_1' };
    const error = await createCustomerPortalSession(team as never).catch((e) => e);
    expect(redirectTarget(error)).toBe('/pricing');
  });

  it('redirects the checkout callback to the pricing page', async () => {
    const { GET } = await import('@/app/api/stripe/checkout/route');
    const res = await GET(
      new NextRequest('https://app.example.com/api/stripe/checkout?session_id=cs_test_1')
    );
    expect(res.status).toBe(307);
    expect(new URL(res.headers.get('location')!).pathname).toBe('/pricing');
  });

  it('builds one client once a key is set', async () => {
    process.env.STRIPE_SECRET_KEY = 'sk_test_not_a_real_key';
    const { getStripe, stripeConfigured } = await import('@/lib/payments/stripe');
    expect(stripeConfigured()).toBe(true);
    expect(getStripe()).toBe(getStripe());
  });
});
