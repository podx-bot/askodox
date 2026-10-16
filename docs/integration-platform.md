# Universal Integration Platform

Status: phase 1 merged (catalog, statuses, Setup Wizard, Owner checklist, OTP fallback, no demo bypass in
production). The phase plan is at the end of this file.

## Pieces that already exist (reused, not duplicated)
- `commerce_finance.IntegrationRegistry`:
  - one row per provider: encrypted secrets, test / live / mock mode, checks;
  - credentials come from the Command Center or the Railway variables (`ENV_SOURCES`);
  - Live payments are locked by `ASKODOX_PAYMENTS_LIVE_APPROVED`.
- Senders: `comms.py` (WhatsApp Cloud, SMS MSG91 / Twilio, e-mail SMTP, push) and the delivery outbox.
- Payments: `razorpay_gateway.py` and `cashfree_gateway.py` through `PaymentService`, plus `billing.py`.
- Gateway state: `payment_gateway_health`.
- Affiliate / partners:
  - Partner Hub: postbacks, conversions, revenue;
  - Affiliate Product Hub and the item store (`affiliate_products`);
  - Smart Links;
  - benefits / offers;
  - sponsored campaigns;
  - `marketplace_api` (Amazon PA-API / Flipkart).
- Real-call provider health: `provider_health`, `api_billing` (API Health & Billing).
- Testers: `tester_identity`. One rule for billing and Radio testers; the demo account is never a tester.

## Integration Catalog (`app/services/integration_catalog.py`)
- One entry per integration, in 10 areas: auth, kyc, communication, commerce, app_monetization, bfsi,
  payments, maps, ai, video.
- Each entry records:
  - what the integration does;
  - whether an account, provider approval or money is needed;
  - the signup and docs URLs (the provider's own site);
  - the auth method;
  - credential NAMES (never values);
  - setup steps and how to test;
  - the honest code state: `built`, `manual_workflow` (staff link / postback workflow) or `not_built`.

Status is computed from live state, never set by hand:

| Status | Meaning |
|---|---|
| CODE READY | adapter built; credentials present, no real call has proven it yet |
| CONFIGURATION REQUIRED / ACCOUNT REQUIRED / PROVIDER APPROVAL REQUIRED | adapter built, setup missing |
| SANDBOX TESTED | a real call passed in TEST / sandbox |
| LIVE VERIFIED | a real call passed in live mode |
| DISABLED | switched off by staff |
| ERROR | the last real call / check failed |
| NOT BUILT | no adapter yet (development work, never shown as an Owner task) |

A mock-mode provider, or a test with recorded responses, never becomes SANDBOX TESTED or LIVE VERIFIED.

Command Center -> System -> **Integration Setup Wizard**:
- every integration with its status, reason, links, credential names, steps and test;
- the Owner Action Checklist;
- the list of NOT BUILT items.

APIs: `GET /admin/cc/integrations/catalog` and `GET /admin/cc/integrations/owner-checklist`
(`integrations:view`).

### Adding a provider
1. Add one catalog entry with its area, links, credentials and steps.
2. If the provider stores credentials, add it to `commerce_finance.PROVIDERS` (+ `ENV_SOURCES`). The registry
   then gives it encrypted storage, enable / disable, test / live / mock and Check automatically.
3. If the provider needs unique logic (its own API calls, webhook format), write one adapter module and a probe
   in `comms.default_probes`. This is the only part that is genuinely provider-specific.
4. Tests: recorded request / response shapes. A status only becomes SANDBOX TESTED / LIVE VERIFIED from a real
   check.

## Sign-in OTP (`app/services/otp_delivery.py`)
- The code goes out through the first channel that can send, in the order of `ASKODOX_OTP_CHANNELS`
  (default `whatsapp_template,whatsapp,sms`):
  - `whatsapp_template`: WhatsApp Cloud API with an approved authentication template. This is the only
    WhatsApp form that reaches someone who has not messaged the business in 24 h.
  - `whatsapp`: the legacy free-text WhatsApp sender.
  - `sms`: MSG91 with a DLT template, or Twilio.
- An unconfigured channel is skipped. A failing one falls through to the next.
- The code is never logged or returned; logs carry only the channel and the last 4 digits.
- The public `/health/integrations` row "Sign-in OTP" shows which channels are configured, and whether the demo
  login is on.
- **Demo login:** the shared demo number (fixed code) works only outside production. In production it works
  only when the Owner sets `ASKODOX_DEMO_LOGIN=yes` for a test session; the same applies to
  `ASKODOX_TEST_OTP_MOBILES`. It can never be a billing or Radio tester (`DEMO_ACCOUNT_NOT_ALLOWED`).

## Phase plan (status)
1. **Phase 1, done in code:** catalog + statuses + wizard + Owner checklist; OTP fallback; no demo bypass in
   production.
2. **Phase 2, KYC engine:**
   - verification levels L1–L5;
   - consent records;
   - document AI extraction marked as "extracted, not verified";
   - review queue;
   - expiry;
   - provider adapters once a provider is chosen.
3. **Phase 3, commission engine:**
   - commission rule types (CPS / CPI / CPA / CPL / CPC / recurring / revenue share);
   - attribution windows;
   - reversals;
   - settlement reconciliation;
   - fraud signals.

   This extends Partner Hub, it does not replace it.
4. **Phase 4, campaign types:**
   - app install / referral / BFSI campaign types in the item store, with transparent "Sponsored" cards on the
     Result Board;
   - partner metadata (registration URL, docs, tracking method, commission model) in Partner Hub.
5. **Phase 5, identity:**
   - one Master Profile per phone (normalise 10-digit vs 91-prefixed sign-ins, with a data migration);
   - roles on one account;
   - account recovery.
