# Payments: gateway setup, TEST mode and Live approval

Status (2026-10-14): **code ready, no gateway configured**. Nothing charges real money. Live mode is locked.

## What is built (one payment layer)
- `commerce_finance.PaymentService`: one payment record per purchase, with an idempotency key and a strict state
  machine (CREATED -> PENDING -> PAID -> REFUNDED / PARTIALLY_REFUNDED / SETTLED).
- Gateway adapters, from each gateway's official API:
  - Razorpay (`razorpay_gateway.py`): Orders API; Standard Checkout; checkout signature
    `HMAC_SHA256(key_secret, order_id|payment_id)`; webhooks signed with the webhook secret, header
    `X-Razorpay-Signature`, replay id `X-Razorpay-Event-Id`; Refunds API.
  - Cashfree (`cashfree_gateway.py`, API version 2023-08-01): Create Order -> `payment_session_id` for the
    Cashfree checkout SDK; webhooks `x-webhook-signature = base64(HMAC_SHA256(client_secret, timestamp + body))`;
    stale (> 15 min) or replayed events are refused; Refunds API. TEST mode uses `sandbox.cashfree.com`.
- Billing (`billing.py`, `/api/billing/*`):
  - base plans (Free / Plus / Pro) and the separate Travel Radio add-on (1 day Rs 29, 7 days Rs 149,
    30 days Rs 399 -- all inactive);
  - a plan or pass activates only on a gateway-confirmed PAID;
  - a refund ends it only after the gateway confirms;
  - expiry by period (`ends_at`).
- ASKODOX never sees or stores card numbers, CVV, UPI PINs or bank logins: the gateway's checkout collects them.

## Safety locks
1. **TEST mode** (sandbox keys, no real money): only staff-chosen billing testers can pay (Command Center ->
   Billing, gateways & push -> Billing testers).
2. **Live mode is locked in code.** Switching a gateway to Live, or saving live keys (`rzp_live_...`, a
   non-TEST Cashfree client id), is refused unless the Owner sets the Railway variable
   `ASKODOX_PAYMENTS_LIVE_APPROVED=yes`. A live key that arrives some other way shows `LIVE_MODE_LOCKED` (ERROR)
   and takes no payment.
3. Even with Live unlocked, a plan is sold only when flag `billing.live_pricing` is ON and the plan is set "on
   sale" (Plans & pricing).

## Individual / sole-proprietor merchant account (company registration pending)
Whether the gateway accepts the account is the gateway's decision (KYC). Nothing here bypasses it. From the
gateways' own pages (checked 2026-10-14; requirements change, confirm with the gateway):
- **Razorpay**: freelancers and individual / unregistered businesses can sign up. KYC uses the personal PAN
  (CKYC, or Video KYC with the original PAN card). GST and a current account are not mandatory: a savings account
  works. Sole proprietorships need 2 business documents from Razorpay's list from 2026-01-01.
  - <https://razorpay.com/docs/payments/faqs/>
  - <https://razorpay.com/docs/payments/business-types-kyc-documents/>
- **Cashfree**: supports "eligible" unregistered businesses. It typically asks for PAN, Aadhaar / ID, address
  proof, a bank account and business details. It does not state individual / sole-proprietor eligibility, so
  confirm with Cashfree.
  - <https://www.cashfree.com/blog/payment-gateway-for-unregistered-businesses/>
  - <https://docs.cashfree.com/docs/cashfree-payments-account-checklist>

ASKODOX works with either. If both are ready, `ASKODOX_PAYMENT_PROVIDER=razorpay|cashfree` picks one.

## Owner steps (no credentials are invented)
1. Create the merchant account with your own PAN and bank account. While KYC is pending, the TEST / sandbox keys
   are usually available.
2. Command Center -> Integrations -> Razorpay (or Cashfree), mode **test**:
   - Razorpay: `key_id` (`rzp_test_...`), `key_secret`, `webhook_secret`.
   - Cashfree: `client_id` (TEST...), `client_secret`.
   - Secrets are encrypted and never shown again.
   - Or use Railway variables `RAZORPAY_KEY_ID / RAZORPAY_KEY_SECRET / RAZORPAY_WEBHOOK_SECRET` or
     `CASHFREE_CLIENT_ID / CASHFREE_CLIENT_SECRET`.
3. Webhook URL in the gateway dashboard:
   - `https://podx-ai-connect-production-3279.up.railway.app/api/payments/webhook/razorpay`
     (events `payment.captured`, `payment.failed`, `order.paid`, `refund.processed`)
   - `.../api/payments/webhook/cashfree` (payment success / failed / user dropped, refund)
4. Add yourself as a billing tester and buy a plan with the gateway's test card / test UPI. Expected: purchase
   PENDING -> ACTIVE after the webhook; Refund -> REFUNDED after the refund webhook; the pass / plan ends.
5. Live (only after the gateway approved the account):
   - Railway `ASKODOX_PAYMENTS_LIVE_APPROVED=yes`
   - live keys and mode live
   - `billing.live_pricing` ON
   - plans on sale

## App
The app needs the gateway's checkout SDK (Razorpay Checkout / Cashfree SDK) added once a gateway is chosen.
The server returns the checkout parameters (`/api/billing/checkout`), and Razorpay success is verified at
`/api/billing/razorpay/verify`. Until a gateway exists, the Plans screen says payments are not available.
