# Integration readiness (backend + Command Center)

Branch `claude/friendly-ramanujan-538sbj`, deployed only to the **staging** Railway environment
(`https://podx-ai-connect-staging.up.railway.app`). Production and `main` are unchanged.

Live view: Command Center → **System → Integration readiness** (`GET /admin/cc/platform/readiness`). It is computed
from live state — the integration registry, the delivery outbox, sandbox payments and Partner Hub — never from a
hand-set flag. An integration is **LIVE** only with real credentials, mode `live` and a passed live check.

## How every integration behaves

| State | Meaning |
|---|---|
| NEEDS_CONFIGURATION | Credentials missing. Never contacted. Messages are recorded as `SKIPPED_NEEDS_CONFIGURATION`. |
| DISABLED | Credentials present (Command Center or Railway variable) but switched off. Never contacted. |
| MOCK | Enabled in mock mode: works end to end inside ASKODOX, needs no credentials, **never contacts the provider**. Messages are `MOCK_DELIVERED`. |
| TEST | Real credentials, enabled, not yet verified live. Real API calls. |
| LIVE | Real credentials + mode `live` + a passed **Check** (read-only live probe). |
| ERROR | The last live check failed (reason shown). |

* Secrets are encrypted with `ASKODOX_SECRETS_KEY` and write-only (never returned, never logged, only names in the
  audit log). Existing Railway variables are reused as-is and shown only as "set via deployment variable".
* Every outbound message goes through one path (`app/services/comms.py`) and lands in the delivery outbox
  (Command Center → **System → Message deliveries**) with the recipient masked and the provider's error when it fails.
* **Test send** (Integrations → provider → Test send) sends one message to an address you type — in mock mode it
  never leaves ASKODOX.

## Production hardening (built without credentials, tested with recorded API shapes)

* **Validation on save.** Each credential is format-checked when it is saved: Razorpay `rzp_test_/rzp_live_` key id,
  YouTube `AIza…` key, Twilio `AC…` SID, numeric WhatsApp phone-number id, DLT sender id, SMTP host/port/from
  address, and a real Firebase service-account JSON. Errors name the field, never the value. A deployment variable
  that looks wrong shows as a warning.
* **Razorpay adapter** (Razorpay's documented Orders, Standard Checkout and Webhooks APIs):
  * Starting an online payment creates a Razorpay order (amount in paise, receipt = ASKODOX payment id,
    idempotent).
  * The checkout success callback is verified with `HMAC(key_secret, order_id|payment_id)`.
  * Razorpay's own webhooks (`X-Razorpay-Signature`, `X-Razorpay-Event-Id` replay protection) map
    `payment.captured` / `order.paid` to PAID, `payment.failed` to FAILED and `refund.processed` to (partially)
    REFUNDED.
  * A customer order paid this way becomes payment VERIFIED "by gateway".
  * Customer actions: `POST /api/orders/{id}/payment` `start_online` / `verify_online`. These are refused when no
    gateway is configured or the `payments.online` switch is off.
  * The **app screen for Razorpay Checkout is not built yet** (it needs the Razorpay SDK in the APK).
* **WhatsApp inbound security.** Once `app_secret` is set, every webhook must carry a valid Meta
  `X-Hub-Signature-256`, otherwise 401. Without it the endpoint behaves exactly as before, and the Command Center shows
  a warning. Delivery receipts (sent / delivered / read / failed) are written onto the message in the delivery log.
* **Customer opt-out.** `GET/PUT /api/me/notification-channels`: a customer can switch off WhatsApp, SMS, e-mail or
  push. This always wins over admin notification rules (`SKIPPED_OPTED_OUT`), and opt-out counts appear in Message
  deliveries.
* **Contacts are found from the real user id server-side.** The delivery log keeps only the opaque reference. This
  fixes a bug where real SMS/WhatsApp/push would never have found the customer.
* **One automatic retry** on transient provider errors (5xx, 429, network). Permanent errors fail at once with the
  provider's message.
* **YouTube quota guard.** A daily unit budget (`ASKODOX_YOUTUBE_DAILY_UNITS`, default 9,000 of the standard 10,000;
  101 units per uncached search) counted per Pacific-time day. When it is used up, search falls back to web videos,
  and usage is shown on the integration card.
* **Staging check.** The public `/readiness` endpoint lists each integration's status word (never values or field
  names). The staging smoke test fails if anything is LIVE on staging or if staging's WhatsApp is on.

## Where each credential goes

Command Center → Integrations → *provider* → **Configure** (encrypted, write-only), or the Railway variable on the
environment that should use it (staging first). A value saved in the Command Center takes precedence.

| Integration | Provider(s) | Required | Optional | Railway variables (reused if present) |
|---|---|---|---|---|
| Payment gateway | Razorpay (also Cashfree, PhonePe, Paytm, Stripe) | `key_id`, `key_secret`, `webhook_secret` | — | `RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET`, `RAZORPAY_WEBHOOK_SECRET` |
| WhatsApp | WhatsApp Cloud API | `access_token`, `phone_number_id` | `app_secret`, `api_version`, `template_name`, `template_language` | `WHATSAPP_ACCESS_TOKEN`, `WHATSAPP_PHONE_NUMBER_ID`, `WHATSAPP_APP_SECRET`, `WHATSAPP_API_VERSION` |
| SMS | MSG91 (default) or Twilio | `api_key`, `sender_id` (+ `dlt_template_id` for MSG91, `account_sid` for Twilio) | `vendor` | `SMS_API_KEY`, `SMS_SENDER_ID`, `SMS_VENDOR`, `SMS_DLT_TEMPLATE_ID`, `SMS_ACCOUNT_SID` |
| Email | Any SMTP (Gmail app password, Brevo, SES SMTP, …) | `host`, `from_address`, `password` | `port` (587 / 465), `username` | `SMTP_HOST`, `EMAIL_FROM`, `SMTP_PASSWORD`, `SMTP_PORT`, `SMTP_USERNAME` |
| Firebase push | FCM HTTP v1 | `service_account_json` | `project_id` | `FIREBASE_SERVICE_ACCOUNT_JSON` (+ the app's `google-services.json`, see `docs/EXTERNAL_SETUP.md`) |
| YouTube Data API | YouTube Data API v3 | `api_key` | — | `YOUTUBE_API_KEY` |
| Affiliate partners | Partner Hub partners, affiliate programs / links, networks (Amazon Associates, Flipkart, Cuelinks, Admitad) | per network / partner | — | Command Center only (Partner Hub secrets are encrypted) |

Production today has WhatsApp variables set; production is on `main` and not affected by this branch. Staging has
its WhatsApp variables deliberately blank so it can never message real users.

## Working without any external account

* **Payments:** COD, cash on pickup, direct merchant (offline) and **direct UPI**. A seller adds their own UPI ID in
  their profile (validated). The customer's order then shows a standard `upi://pay` link to that seller (NPCI deep
  link — any UPI app). The customer submits the UTR and the seller confirms receipt. No gateway, no fee, and no
  placeholder or demo UPI ID anywhere: the unreachable demo QR screen was removed.
* **Online-payment flow test:** the **Sandbox gateway** (Integrations → Payments) creates a payment and plays the
  gateway's part (Payments → payment → *Sandbox: simulate paid / failed*), then refund / settle through the same
  state machine a real webhook uses. It is disabled and refused whenever `RAILWAY_ENVIRONMENT_NAME` is `production`.
* **Offers, coupons, rewards:** unchanged engines (`benefits_engine.py`, `offers_engine.py`, rewards ledger). They
  record discount and redemption events and credit rewards only on confirmed completion.
* **Videos:** real videos come from the already-configured Brave search with YouTube oEmbed checks. **Content →
  Discovered videos** lists them; *Send to review* copies one into Videos as **Pending Review**. There it can be
  linked to products and services, a seller, a service provider or a creator/influencer, and given a relationship
  (organic / creator / merchant / affiliate / sponsored, always disclosed) and an affiliate link. It shows to
  customers only after **Approve → Active**. An affiliate video's "shop" button opens its link through the tracked
  `/go/af/…` redirect (impression → click → conversion by postback). Seller and provider references never leave the server.

## Before production (for every integration)

1. Add the real credential on **staging** first. Run **Check** and one **Test send** / sandbox payment to your own
   number or address.
2. Switch the mode to `live`, then run **Check** again. The status becomes LIVE only if the check passes.
3. Repeat on production after the branch is merged and deployed — with your approval, never automatically.
