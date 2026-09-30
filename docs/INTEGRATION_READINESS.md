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
