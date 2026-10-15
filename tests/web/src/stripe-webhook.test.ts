import { beforeEach, describe, expect, it, vi } from 'vitest';
import { NextRequest } from 'next/server';

// app/api/stripe/webhook/route.ts: until Stripe is connected it answers 503;
// then the signature is checked first (on Workers through constructEventAsync
// over SubtleCrypto), a bad one is a 400 before anything touches the database;
// subscription events reach handleSubscriptionChange. The Stripe client is
// mocked — no network.
const constructEventAsync = vi.fn();
const handleSubscriptionChange = vi.fn();
const stripeConfigured = vi.fn();

vi.mock('@/lib/payments/stripe', () => ({
  getStripe: () => ({ webhooks: { constructEventAsync } }),
  stripeConfigured: () => stripeConfigured(),
  handleSubscriptionChange
}));

function post(body: string, signature?: string) {
  return new NextRequest('https://app.example.com/api/stripe/webhook', {
    method: 'POST',
    body,
    headers: signature ? { 'stripe-signature': signature } : undefined
  });
}

describe('POST /api/stripe/webhook', () => {
  beforeEach(() => {
    vi.resetModules();
    constructEventAsync.mockReset();
    handleSubscriptionChange.mockReset();
    stripeConfigured.mockReset().mockReturnValue(true);
    process.env.STRIPE_WEBHOOK_SECRET = 'whsec_test';
    vi.spyOn(console, 'error').mockImplementation(() => {});
    vi.spyOn(console, 'log').mockImplementation(() => {});
  });

  it('answers 503, verifying nothing, while Stripe is not connected', async () => {
    stripeConfigured.mockReturnValue(false);
    const { POST } = await import('@/app/api/stripe/webhook/route');
    const res = await POST(post('{"id":"evt_0"}', 't=1,v1=ok'));
    expect(res.status).toBe(503);
    expect(await res.json()).toEqual({ error: 'Stripe is not connected.' });
    expect(constructEventAsync).not.toHaveBeenCalled();
    expect(handleSubscriptionChange).not.toHaveBeenCalled();
  });

  it('answers 503 when the key is set and the webhook secret is not', async () => {
    delete process.env.STRIPE_WEBHOOK_SECRET;
    const { POST } = await import('@/app/api/stripe/webhook/route');
    const res = await POST(post('{"id":"evt_0"}', 't=1,v1=ok'));
    expect(res.status).toBe(503);
    expect(constructEventAsync).not.toHaveBeenCalled();
  });

  it('answers 400 when the signature does not verify', async () => {
    constructEventAsync.mockRejectedValue(
      new Error('No signatures found matching the expected signature for payload')
    );
    const { POST } = await import('@/app/api/stripe/webhook/route');
    const res = await POST(post('{"id":"evt_1"}', 't=1,v1=bad'));
    expect(res.status).toBe(400);
    expect(await res.json()).toEqual({ error: 'Webhook signature verification failed.' });
    expect(handleSubscriptionChange).not.toHaveBeenCalled();
  });

  it('verifies against the configured secret and hands a subscription change on', async () => {
    const subscription = { id: 'sub_1', customer: 'cus_1', status: 'active' };
    constructEventAsync.mockResolvedValue({
      type: 'customer.subscription.updated',
      data: { object: subscription }
    });
    const { POST } = await import('@/app/api/stripe/webhook/route');
    const res = await POST(post('{"id":"evt_2"}', 't=1,v1=ok'));
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ received: true });
    expect(handleSubscriptionChange).toHaveBeenCalledWith(subscription);
    const [payload, signature, secret] = constructEventAsync.mock.calls[0]!;
    expect(payload).toBe('{"id":"evt_2"}');
    expect(signature).toBe('t=1,v1=ok');
    expect(secret).toBe('whsec_test');
  });

  it('acknowledges events it does not handle without touching the team', async () => {
    constructEventAsync.mockResolvedValue({ type: 'invoice.paid', data: { object: {} } });
    const { POST } = await import('@/app/api/stripe/webhook/route');
    const res = await POST(post('{}', 't=1,v1=ok'));
    expect(res.status).toBe(200);
    expect(handleSubscriptionChange).not.toHaveBeenCalled();
  });
});
