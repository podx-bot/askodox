# PODX monetization integration guide

## Current architecture

Sprint 9 is entirely local and demonstrative. Domain models describe plans, limits, subscriptions, trials, attempts, promotions, invoices, GST placeholders, refunds, and revenue metrics. Riverpod exposes provider-neutral repository boundaries and a state controller. Mock repositories are the only implementations. Buyers remain free and seller onboarding is never paywalled.

Widgets ask `EntitlementService` about capabilities rather than comparing plan names. Limits are configuration on `SellerPlan`; `checkLimit` returns the usage and maximum so the UI can explain a refusal and offer an upgrade. Paid lead access never includes buyer identity or phone data.

## Adding a gateway later

Implement `PaymentGateway` in an infrastructure package for Razorpay or Cashfree (or Stripe, Play Billing, or Apple IAP). Keep SDK objects inside the adapter. The app should request an order from the PODX backend, open the provider UI, then submit the provider reference to the backend. Never activate locally from the provider callback. No production key belongs in Flutter; publishable identifiers should come from environment configuration and secrets stay server-side.

## Webhooks and server authority

The backend must verify webhook signatures using the raw payload, reject replayed event IDs, persist events idempotently, fetch/verify the provider payment when appropriate, and atomically update payment and subscription records. Flutter should refresh the authoritative subscription afterward. The demo confirmation reference is deliberately labelled unverified. The same server authority must validate subscription status, entitlements, promo usage, invoice generation, refunds, and webhook signatures.

## GST and invoices

The model reserves legal name, GSTIN, billing address, state, place of supply, taxable value, CGST, SGST, and IGST. Current numbers and invoice downloads are placeholders and make no tax-compliance claim. Before launch, obtain professional tax advice, calculate tax server-side, use immutable invoice numbering, preserve tax snapshots, and generate signed documents from backend records.

## Refunds

A production refund begins as an authenticated admin request with a mandatory reason. The backend checks policy and captured value, calls the selected provider, and advances the state only from verified provider responses/webhooks. Audit every transition and never infer a refund from client success.

## Replacing mocks

Implement each domain interface with API-backed repositories, replace its Riverpod provider override at the composition root, and retain controller/widget contracts. Add mapping, retry/idempotency, authenticated seller scoping, admin authorization, server time, pagination, and explicit offline/error states. Contract-test adapters before enabling a gateway.
