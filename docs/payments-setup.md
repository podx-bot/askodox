# Payments: gateway setup, TEST mode and Live approval

Status (2026-10-15): **Razorpay TEST keys are set as Railway variables** (`RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET`).
Razorpay runs in TEST mode for billing testers only. Nothing charges real money, and Live mode is locked.
The public `/health/integrations` "Razorpay" row shows the state without any key: `TEST_MODE_READY` after
Razorpay accepted the keys in a read-only check.

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

## Razorpay TEST mode flow (2026-10-15)
- **Keys from Railway only:** `RAZORPAY_KEY_ID` (`rzp_test_...`) + `RAZORPAY_KEY_SECRET` switch Razorpay on in
  TEST mode until staff change it in the Command Center (staff settings win). `RAZORPAY_WEBHOOK_SECRET` is
  optional. Without it, payments are confirmed by the checkout signature or by reading the order back from Razorpay.
- **Who can pay:** `GET /api/billing/options` says, per plan, whether this user may pay now. In TEST mode that
  means staff-chosen billing testers only.
- **Radio stays off:** Travel Radio passes also need flag `billing.radio_checkout`, which is OFF.
- **Checkout:**
  - The app sends only the plan code to `POST /api/billing/checkout`. The server sets the price and creates the
    Razorpay order (amount in paise).
  - The server returns `pay_url`: `/billing/pay/{purchase}?t=...`, a 30-minute link bound to that one purchase,
    redacted in access logs.
  - The app opens the link in the browser. The page loads Razorpay Standard Checkout with the server's key,
    order and amount.
- **Success:** the checkout returns a signature. The server checks `HMAC_SHA256(key_secret, order_id|payment_id)`
  AND that the order belongs to this purchase, then activates the plan once.
- **Cancel:** closing the checkout marks the purchase `CANCELLED`. If Razorpay later reports a capture, the plan
  still activates, because the money was taken.
- **Failed attempt:** stays `PENDING`, because Razorpay allows a retry on the same order. The attempt is logged.
- **Pending:**
  - `GET /api/billing/purchases/{id}` (the app's "Check status") reads the order's payments back from Razorpay.
    This is a GET only.
  - A captured payment with the right amount becomes `ACTIVE`.
  - A purchase with no capture after 24 h becomes `EXPIRED`.
- **Webhooks** (when the secret is set): signature, event-id replay protection and amount / currency checks.
  A wrong amount never pays.
- **Refunds:**
  - Only staff can refund, with confirmation (Command Center -> Billing -> Refund).
  - "Check with gateway" reads refund status back. It never creates a refund or a capture.
- **Audit:**
  - `billing_events` records each step: who, what and when, never card / UPI data.
  - Payment state history is in `pf_state_history`. Staff see both under "Check with gateway".

## TEST money never creates a real entitlement (2026-10-15)
A gateway-confirmed TEST payment becomes `TEST_PAID`. It proves the flow: order, checkout, signature or webhook,
idempotency and refund. No plan, subscription or Radio pass is activated. Only a LIVE purchase activates a plan
(`ACTIVE`), and that is possible only after every Owner approval.

## One gateway state everywhere
`payment_gateway_health.check` answers for every screen: the public `/health/integrations`, Integration readiness
(`TEST_MODE_VERIFIED`), API Health & Billing (Razorpay row) and Billing.
- **Key check:** Razorpay's own answer to an authenticated read-only call (`GET /v1/payments?count=1`), cached for
  15 minutes.
- **Check with gateway:** under API Health & Billing -> Razorpay, `POST /admin/cc/api-billing/razorpay/check`
  forces a fresh check at most once a minute. It is audited and never creates, captures or refunds anything.
- **Webhook evidence:** counts signature-verified events stored in `pf_payment_events`, and rejected signatures
  since the last deploy.
- **Failed checks:** only a Razorpay 401 marks the keys as failed, which turns checkout off. A network blip changes
  nothing.

## Phone test (TEST mode, no real money)
1. Command Center -> Billing, gateways & push: Razorpay shows `TEST`, key `test`, enabled by `environment`.
2. Add yourself as a billing tester: your phone number (`98XXXXXXXX`) or app user id. The number matches by its
   last 10 digits however you typed it at app sign-in, with or without +91. Removing it revokes every spelling. Without this, the app shows
   "Payments are in TEST mode: only billing testers chosen by staff can pay" and no Pay button.
3. App -> header menu -> "Plans & subscription": Plus shows **Pay (test)**. Tap it. The Razorpay page opens with "TEST MODE".
4. Pay with a Razorpay test card or test UPI from Razorpay's test-payment docs, never a real card. Then go back
   to the app and tap **Check status**. Expected: `ACTIVE`.
5. Repeat and close the checkout: `CANCELLED`. Repeat and use a failing test card: stays `PENDING`, then retry.
6. Refund (staff) -> **Check with gateway** -> `REFUNDED`.
