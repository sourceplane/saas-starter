import Stripe from 'stripe';
import {
  getStripe,
  handleSubscriptionChange,
  stripeConfigured
} from '@/lib/payments/stripe';
import { NextRequest, NextResponse } from 'next/server';

export async function POST(request: NextRequest) {
  // Until the owner connects Stripe (both keys, README "Connect Stripe") there
  // is nothing to verify a delivery against: say so with a 503, which Stripe
  // retries, rather than a 500 or a 400 that reads as a forged event.
  const webhookSecret = process.env.STRIPE_WEBHOOK_SECRET;
  if (!stripeConfigured() || !webhookSecret) {
    return NextResponse.json(
      { error: 'Stripe is not connected.' },
      { status: 503 }
    );
  }

  const payload = await request.text();
  const signature = request.headers.get('stripe-signature') as string;

  let event: Stripe.Event;

  try {
    // Workers: verify the signature over SubtleCrypto (async), not Node's crypto.
    event = await getStripe().webhooks.constructEventAsync(
      payload,
      signature,
      webhookSecret,
      undefined,
      Stripe.createSubtleCryptoProvider()
    );
  } catch (err) {
    console.error('Webhook signature verification failed.', err);
    return NextResponse.json(
      { error: 'Webhook signature verification failed.' },
      { status: 400 }
    );
  }

  switch (event.type) {
    case 'customer.subscription.updated':
    case 'customer.subscription.deleted':
      const subscription = event.data.object as Stripe.Subscription;
      await handleSubscriptionChange(subscription);
      break;
    default:
      console.log(`Unhandled event type ${event.type}`);
  }

  return NextResponse.json({ received: true });
}
