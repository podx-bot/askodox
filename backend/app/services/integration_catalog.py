"""Universal Integration Catalog + Setup Wizard (zero-credential readiness).

ONE list of every external integration ASKODOX has or plans, across the
categories auth / kyc / communication / commerce / app_monetization / bfsi /
payments / maps / ai / video. Each entry says, in the Owner's terms, what it
does, whether an account / approval / money is needed, where to sign up, which
secure field or deployment variable to fill, how to test, and -- honestly --
whether ASKODOX already has the adapter code ("built"), the engine + adapter
interface but no vendor adapter yet ("interface_ready", e.g. KYC providers), only
a staff manual link / report workflow ("manual_workflow"), or nothing yet
("not_built").

Status is COMPUTED from live state (integration registry, the same real-call
provider health the API Health page uses, the payment gateway check), never
hand-set:

  CODE READY                  adapter built; credentials present, not yet proven by a real call
  CONFIGURATION REQUIRED      adapter built; credentials / settings missing
  ACCOUNT REQUIRED            adapter built; needs an account with the provider first
  PROVIDER APPROVAL REQUIRED  adapter built; the provider must approve ASKODOX first
  SANDBOX TESTED              a real call passed in TEST / sandbox mode
  LIVE VERIFIED               a real call passed in live mode
  DISABLED                    switched off by staff
  ERROR                       the provider refused / failed the last real call
  NOT BUILT                   no adapter yet (named honestly; never shown as ready)

A mock / recorded-response test never produces SANDBOX TESTED or LIVE VERIFIED.
Nothing here returns a secret value; links point to the providers' own sites.
Adding a provider = one catalog entry (+ an adapter when the provider needs
unique logic), see docs/integration-platform.md.
"""
from __future__ import annotations

import os
from typing import Any, Callable, Dict, List, Optional

CODE_READY = "CODE READY"
CONFIG_REQUIRED = "CONFIGURATION REQUIRED"
ACCOUNT_REQUIRED = "ACCOUNT REQUIRED"
APPROVAL_REQUIRED = "PROVIDER APPROVAL REQUIRED"
SANDBOX_TESTED = "SANDBOX TESTED"
LIVE_VERIFIED = "LIVE VERIFIED"
DISABLED = "DISABLED"
ERROR = "ERROR"
NOT_BUILT = "NOT BUILT"
STATUSES = (CODE_READY, CONFIG_REQUIRED, ACCOUNT_REQUIRED, APPROVAL_REQUIRED, SANDBOX_TESTED, LIVE_VERIFIED,
            DISABLED, ERROR, NOT_BUILT)
DONE_STATUSES = (SANDBOX_TESTED, LIVE_VERIFIED)

CATEGORIES = {
    "auth": "Authentication", "kyc": "Identity verification (KYC)", "communication": "Communication",
    "commerce": "Commerce & affiliate", "app_monetization": "App install & referral campaigns",
    "bfsi": "Financial services partners", "payments": "Payments", "maps": "Maps & location", "ai": "AI",
    "video": "Video & content",
}

# Source of state for built adapters:
#   ("registry", provider)   -> commerce_finance.IntegrationRegistry row
#   ("api_health", name)     -> api_billing provider state (real calls observed)
#   ("gateway", "razorpay")  -> payment_gateway_health.check
#   ("otp", None)            -> otp_delivery channels
#   ("env", (VARS...))       -> deployment variables present (no real check exists)
#   ("partner_hub", None)    -> Partner Hub rows (manual / postback workflow)


def _e(key: str, name: str, category: str, adapter: str, does: str, *, source: Any = None,
       account: bool = True, approval: bool = False, costs: str = "", signup: str = "", docs: str = "",
       auth: str = "", credentials: Optional[List[str]] = None, steps: Optional[List[str]] = None,
       test: str = "", notes: str = "") -> Dict[str, Any]:
    return {"key": key, "name": name, "category": category, "adapter": adapter, "does": does, "source": source,
            "account_required": account, "approval_required": approval, "costs": costs, "signup_url": signup,
            "docs_url": docs, "auth_method": auth, "credentials": credentials or [], "steps": steps or [],
            "how_to_test": test, "notes": notes}


# The ASKODOX release signing certificate (public fingerprints; Firebase needs them).
RELEASE_CERT_SHA1 = "63:37:E1:1A:34:E7:55:31:20:77:EF:7D:52:B2:69:AA:A1:7B:19:0A"
RELEASE_CERT_SHA256 = ("72:7B:4A:66:22:F0:F9:DF:A3:36:36:DA:4F:26:61:62:E9:CA:B7:50:FB:DF:24:00:04:E9:B2:1F:"
                       "56:C9:57:CF")

CC = "Command Center -> Integrations -> {name} -> Configure (encrypted, write-only)"

CATALOG: List[Dict[str, Any]] = [
    # ------------------------------------------------------------- auth --
    _e("otp_whatsapp_template", "WhatsApp OTP (approved template)", "auth", "built",
       "Sends the sign-in code on WhatsApp to anyone, using an approved authentication template.",
       source=("otp", "whatsapp_template"), approval=True, costs="Meta charges per authentication conversation.",
       signup="https://business.facebook.com/", docs="https://developers.facebook.com/docs/whatsapp/cloud-api",
       auth="Bearer access token (System User)",
       credentials=["access_token (WHATSAPP_ACCESS_TOKEN)", "phone_number_id (WHATSAPP_PHONE_NUMBER_ID)",
                    "template_name (approved authentication template)"],
       steps=["Create / verify a Meta Business account and add a WhatsApp Business number.",
              "Create an AUTHENTICATION message template with one code parameter; wait for Meta approval.",
              CC.format(name="WhatsApp Business (Cloud API)") + ": access_token, phone_number_id, template_name.",
              "Command Center -> Integrations -> WhatsApp -> Check."],
       test="Sign in from the app with your own number: the code must arrive on WhatsApp.",
       notes="Without a template, WhatsApp delivers free text only to people who messaged in the last 24 hours."),
    _e("otp_whatsapp_text", "WhatsApp OTP (free text, legacy)", "auth", "built",
       "Current sign-in path: free-text WhatsApp message.", source=("otp", "whatsapp"),
       signup="https://business.facebook.com/", docs="https://developers.facebook.com/docs/whatsapp/cloud-api",
       auth="Bearer access token", credentials=["WHATSAPP_ACCESS_TOKEN", "WHATSAPP_PHONE_NUMBER_ID"],
       steps=["Railway -> production -> podx-ai-connect -> Variables: WHATSAPP_ACCESS_TOKEN, WHATSAPP_PHONE_NUMBER_ID."],
       test="Message the business number first, then request a code (24-hour window rule)."),
    _e("otp_sms", "SMS OTP", "auth", "built", "Sends the sign-in code by SMS when WhatsApp cannot.",
       source=("otp", "sms"), approval=True,
       costs="Per-SMS charge; India needs DLT registration (entity, header, template).",
       signup="https://msg91.com/", docs="https://docs.msg91.com/",
       auth="API key (authkey)", credentials=["api_key", "sender_id", "vendor (msg91 / twilio)",
                                              "dlt_template_id (MSG91)"],
       steps=["Register on the DLT portal of your telecom operator (entity, header, OTP template).",
              "Create the SMS account (MSG91 or Twilio) and an OTP flow with the approved DLT template.",
              CC.format(name="SMS gateway") + ".", "Order of channels: Railway variable ASKODOX_OTP_CHANNELS."],
       test="Request a code with WhatsApp unavailable: the SMS must arrive."),
    _e("firebase_phone_auth", "Firebase phone sign-in", "auth", "built",
       "Google sends the sign-in SMS and the app proves the number; the server verifies the Firebase ID token.",
       source=("env", ("FIREBASE_PROJECT_ID", "ASKODOX_FIREBASE_PHONE_AUTH")), approval=False,
       costs="Firebase Blaze plan; Google bills phone sign-in SMS beyond the free tier.",
       signup="https://console.firebase.google.com/", docs="https://firebase.google.com/docs/auth/flutter/phone-auth",
       auth="Firebase ID token (RS256, verified on the server against Google's public keys)",
       credentials=["FIREBASE_PROJECT_ID (Railway + GitHub variable)", "ASKODOX_FIREBASE_PHONE_AUTH=yes (Railway)",
                    "FIREBASE_API_KEY / APP_ID / SENDER_ID (GitHub variables, Android app)"],
       steps=["Firebase Console -> create / open the project -> Add app -> Android, package com.askodox.askodox.",
              "Project settings -> Your apps -> Add fingerprint: SHA-1 " + RELEASE_CERT_SHA1 + " and SHA-256 "
              + RELEASE_CERT_SHA256 + " (the ASKODOX release key).",
              "Build -> Authentication -> Sign-in method -> Phone -> Enable (upgrade to the Blaze plan when asked).",
              "Optional for tests: Authentication -> Phone -> 'Phone numbers for testing' (your own test number only).",
              "GitHub -> repository Settings -> Variables -> FIREBASE_API_KEY, FIREBASE_APP_ID, FIREBASE_SENDER_ID, "
              "FIREBASE_PROJECT_ID (values from the Android app config), then a new APK build.",
              "Railway -> production -> podx-ai-connect -> Variables: FIREBASE_PROJECT_ID and "
              "ASKODOX_FIREBASE_PHONE_AUTH=yes."],
       test="Sign out, then sign in with your own number: the SMS comes from Google and the app signs you in.",
       notes="Off until the Owner sets ASKODOX_FIREBASE_PHONE_AUTH (SMS cost); the server OTP stays the fallback."),
    _e("otp_email", "E-mail OTP", "auth", "not_built", "Sign-in code by e-mail.", account=False,
       notes="The e-mail sender exists (Integrations -> Email); an e-mail sign-in flow is not built yet."),
    _e("google_sign_in", "Google Sign-In", "auth", "not_built", "Sign in with a Google account.",
       signup="https://console.cloud.google.com/", docs="https://developers.google.com/identity",
       notes="Needs an OAuth client for the Android app and a server-side token check; not built yet."),
    _e("apple_sign_in", "Apple Sign-In", "auth", "not_built", "Sign in with Apple (iOS).",
       docs="https://developer.apple.com/sign-in-with-apple/", costs="Apple Developer Program membership.",
       notes="Only relevant once an iOS app exists."),
    _e("passkeys", "Passkeys", "auth", "not_built", "Password-less sign-in with the phone's screen lock.",
       account=False, docs="https://developer.android.com/identity/sign-in/credential-manager"),
    _e("voice_otp", "Voice-call OTP", "auth", "not_built", "Reads the code out in a phone call.",
       notes="Needs a voice provider; not chosen."),
    # -------------------------------------------------------------- kyc --
    _e("kyc_pan", "PAN verification", "kyc", "interface_ready", "Checks a PAN against the authoritative source.",
       approval=True, costs="Per-check fee charged by the verification provider.",
       source=("kyc_provider", "pan"),
       notes="KYC engine + adapter interface built; a licensed provider must be chosen (vendor adapter needed). "
             "AI-read PAN details are never 'verified'."),
    _e("kyc_digilocker", "DigiLocker", "kyc", "interface_ready", "User-consented documents from DigiLocker.",
       approval=True, signup="https://www.digilocker.gov.in/",
       source=("kyc_provider", "digilocker"),
       notes="KYC engine built; DigiLocker requester registration + its adapter still needed."),
    _e("kyc_aadhaar", "Aadhaar-based verification (permitted modes)", "kyc", "not_built",
       "Only legally permitted modes (e.g. offline XML / DigiLocker) through an authorised provider.",
       approval=True, notes="Aadhaar numbers must never be stored or logged; not built yet."),
    _e("kyc_gst", "GST verification", "kyc", "interface_ready", "Checks a GSTIN and the business name.",
       approval=True, source=("kyc_provider", "gst"),
       notes="KYC engine reads GSTINs (check digit, PAN cross-check); a GST verification provider is needed."),
    _e("kyc_bank", "Bank account ownership", "kyc", "interface_ready",
       "Penny-drop / name match to prove an account belongs to the person.", approval=True,
       source=("kyc_provider", "bank_account"),
       notes="KYC engine reads IFSC / account (masked); penny-drop needs a provider (often the payment gateway)."),
    _e("kyc_documents_review", "Business & professional documents (staff review)", "kyc", "built",
       "Users upload business registration / professional licences; AI extracts fields; staff verify.",
       account=False, steps=["Command Center -> KYC review queue."],
       test="Upload a business document from the app, approve it in the KYC review queue: level 3."),
    _e("kyc_face", "Face match & liveness", "kyc", "not_built", "Selfie matches the ID photo; a live person.",
       approval=True, notes="Needs a provider with consent + data-retention terms; not built yet."),
    _e("kyc_video", "Approved video KYC", "kyc", "not_built", "Regulated video KYC by an authorised partner.",
       approval=True, notes="Only through regulated partners for regulated products."),
    # ---------------------------------------------------- communication --
    _e("whatsapp_cloud", "WhatsApp Business (Cloud API)", "communication", "built",
       "Order / request updates and support messages on WhatsApp.", source=("registry", "whatsapp_cloud"),
       approval=True, costs="Meta per-conversation pricing.", signup="https://business.facebook.com/",
       docs="https://developers.facebook.com/docs/whatsapp/cloud-api", auth="Bearer access token",
       credentials=["access_token", "phone_number_id", "template_name (for business-initiated messages)"],
       steps=[CC.format(name="WhatsApp Business (Cloud API)") + ".", "Integrations -> WhatsApp -> Check."],
       test="Integrations -> Message deliveries: a real message shows SENT."),
    _e("sms", "SMS gateway", "communication", "built", "Transactional SMS.", source=("registry", "sms"),
       approval=True, costs="Per SMS; DLT registration in India.", signup="https://msg91.com/",
       docs="https://docs.msg91.com/", auth="API key",
       credentials=["api_key", "sender_id", "vendor", "dlt_template_id"],
       steps=[CC.format(name="SMS gateway") + "."], test="Message deliveries: SENT for a real SMS."),
    _e("email", "E-mail (SMTP)", "communication", "built", "Transactional e-mail.", source=("registry", "email"),
       costs="Depends on the mail provider.", auth="SMTP username + password",
       credentials=["host", "from_address", "password", "port", "username"],
       steps=[CC.format(name="Email (SMTP / API)") + "."], test="Integrations -> Email -> Check."),
    _e("fcm_push", "Push notifications (Firebase)", "communication", "built",
       "Background notifications on Android phones.", source=("env", ("FIREBASE_SERVICE_ACCOUNT_JSON",)),
       costs="Free tier.", signup="https://console.firebase.google.com/",
       docs="https://firebase.google.com/docs/cloud-messaging",
       auth="Service account (server); app values (Android build)",
       credentials=["FIREBASE_SERVICE_ACCOUNT_JSON (Railway)",
                    "FIREBASE_API_KEY / APP_ID / SENDER_ID / PROJECT_ID (GitHub repository variables)"],
       steps=["See docs/push-test-procedure.md (Firebase project, Android app com.askodox.askodox, variables)."],
       test="Command Center -> push readiness -> Test send to your own user."),
    _e("firebase_in_app_messaging", "Firebase In-App Messaging", "communication", "built",
       "Targeted banners / cards inside the app, designed in the Firebase Console (text + image only).",
       source=("env", ("FIREBASE_PROJECT_ID",)), costs="Free.", signup="https://console.firebase.google.com/",
       docs="https://firebase.google.com/docs/in-app-messaging",
       credentials=["Same Firebase Android app values as push (GitHub variables)"],
       steps=["Firebase Console -> Engage -> In-App Messaging -> New campaign; target ONE test device first "
              "(Test on device, using the Installation ID from Developer Diagnostics)."],
       test="Test on device -> open ASKODOX: the message shows once; switching off promotions hides it.",
       notes="Shown only to people who allowed promotions (Profile -> Notifications). Video ads stay in the ASKODOX "
             "native content system -- In-App Messaging is not a video ad platform."),
    # --------------------------------------------------------- commerce --
    _e("amazon_associates", "Amazon Associates (India)", "commerce", "built",
       "Product links + product data (PA-API) with your associate tag.", source=("registry", "amazon_associates"),
       approval=True, costs="Free to join; commission per qualifying sale.",
       signup="https://affiliate-program.amazon.in/", docs="https://webservices.amazon.in/paapi5/documentation/",
       auth="PA-API access key + secret key", credentials=["access_key", "partner_tag", "secret_key"],
       steps=["Join Amazon Associates and get approved (PA-API needs qualifying sales).",
              CC.format(name="Amazon Associates") + "."],
       test="Affiliate products -> Refresh from marketplace API on one product."),
    _e("flipkart_affiliate", "Flipkart Affiliate", "commerce", "built", "Flipkart product links and feed.",
       source=("registry", "flipkart_affiliate"), approval=True, signup="https://affiliate.flipkart.com/",
       credentials=["affiliate id", "token"], steps=[CC.format(name="Flipkart Affiliate") + "."],
       test="Affiliate products -> Refresh from marketplace API."),
    _e("cuelinks", "Cuelinks (affiliate network)", "commerce", "built", "Many Indian stores through one network.",
       source=("registry", "cuelinks"), approval=True, signup="https://www.cuelinks.com/",
       steps=[CC.format(name="Cuelinks") + "."]),
    _e("admitad", "Admitad (affiliate network)", "commerce", "built", "Affiliate network with postbacks.",
       source=("registry", "admitad"), approval=True, signup="https://www.admitad.com/",
       steps=[CC.format(name="Admitad") + "."]),
    _e("meesho", "Meesho", "commerce", "manual_workflow",
       "Staff paste approved Meesho links / feeds in the item store; no public product API.",
       source=("partner_hub", None), approval=True,
       steps=["Command Center -> Affiliate Product Hub -> paste the approved link."],
       notes="No product API: manual links / feed only."),
    _e("manual_links", "Manual approved links", "commerce", "built",
       "Any approved product / service / app / referral link pasted by staff (Affiliate Product Hub + Smart Links).",
       source=("partner_hub", None), account=False,
       steps=["Command Center -> Affiliate Product Hub -> paste link -> review -> LIVE."],
       test="Search for the item in the app: the card shows the link and its 'Sponsored' / partner label."),
    # ------------------------------------------------- app monetization --
    _e("app_install_networks", "App install / CPI-CPA-CPL networks", "app_monetization", "manual_workflow",
       "Campaign links + server-to-server postbacks into Partner Hub (conversions only from signed postbacks).",
       source=("partner_hub", None), approval=True,
       steps=["Join the network, get approved for the campaign.",
              "Command Center -> Partners -> add the partner, its postback secret and campaign link."],
       test="Partner Hub -> send the network's test postback: a conversion appears as PENDING."),
    _e("mmp_attribution", "Mobile measurement partner (attribution)", "app_monetization", "not_built",
       "Install attribution SDK / API (e.g. for CPI campaigns run BY ASKODOX).",
       notes="Needs an MMP account and an SDK in the app; not built yet."),
    # ------------------------------------------------------------- bfsi --
    _e("bfsi_partners", "Insurance / trading / credit card / loan partners", "bfsi", "manual_workflow",
       "Referral links + partner-confirmed conversions; the partner runs its own regulated KYC.",
       source=("partner_hub", None), approval=True,
       steps=["Sign an agreement with an authorised partner.", "Add it in Command Center -> Partners."],
       notes="ASKODOX never collects regulated KYC for these products itself."),
    # --------------------------------------------------------- payments --
    _e("razorpay", "Razorpay", "payments", "built", "Online payments, refunds, webhooks (TEST until approved).",
       source=("gateway", "razorpay"), approval=True, costs="Per-transaction fee after live activation.",
       signup="https://dashboard.razorpay.com/signup", docs="https://razorpay.com/docs/",
       auth="Key id + key secret; webhook secret",
       credentials=["RAZORPAY_KEY_ID", "RAZORPAY_KEY_SECRET", "RAZORPAY_WEBHOOK_SECRET"],
       steps=["See docs/payments-setup.md."], test="API Health & Billing -> Razorpay -> Check with gateway."),
    _e("cashfree", "Cashfree", "payments", "built", "Online payments, refunds, webhooks (sandbox first).",
       source=("registry", "cashfree"), approval=True, costs="Per-transaction fee after live activation.",
       signup="https://merchant.cashfree.com/merchants/signup", docs="https://www.cashfree.com/docs/",
       auth="Client id + client secret", credentials=["CASHFREE_CLIENT_ID", "CASHFREE_CLIENT_SECRET"],
       steps=["See docs/payments-setup.md."], test="Billing -> sandbox purchase as a billing tester."),
    _e("phonepe", "PhonePe PG", "payments", "not_built", "Payment gateway (registry entry only).",
       approval=True, notes="Credentials can be stored, but no checkout adapter exists yet."),
    _e("paytm", "Paytm PG", "payments", "not_built", "Payment gateway (registry entry only).", approval=True,
       notes="Credentials can be stored, but no checkout adapter exists yet."),
    # ------------------------------------------------------------- maps --
    _e("google_maps", "Google Maps Platform", "maps", "built", "Geocoding, Places, Routes, nearby search.",
       source=("api_health", "google_maps"), costs="Pay per call above Google's monthly credit.",
       signup="https://console.cloud.google.com/google/maps-apis", docs="https://developers.google.com/maps",
       auth="API key", credentials=["GOOGLE_MAPS_API_KEY"], test="/health/maps (all APIs OK)."),
    # --------------------------------------------------------------- ai --
    _e("gemini", "Google Gemini", "ai", "built", "Conversation brain, image / document understanding.",
       source=("api_health", "gemini"), costs="Pay per token above the free tier.",
       signup="https://aistudio.google.com/", docs="https://ai.google.dev/", auth="API key",
       credentials=["GEMINI_API_KEY"]),
    _e("openai", "OpenAI", "ai", "built", "Fallback brain.", source=("api_health", "openai"),
       costs="Pay per token.", signup="https://platform.openai.com/", docs="https://platform.openai.com/docs",
       auth="API key", credentials=["OPENAI_API_KEY"]),
    _e("sarvam", "Sarvam (speech)", "ai", "built", "Telugu / Hindi / English speech-to-text and voice replies.",
       source=("api_health", "sarvam"), costs="Prepaid credits.", signup="https://dashboard.sarvam.ai/",
       docs="https://docs.sarvam.ai/", auth="API subscription key", credentials=["SARVAM_API_KEY"]),
    _e("brave", "Brave Search API", "ai", "built", "Whole-web search results.", source=("api_health", "brave"),
       costs="Paid plan by request volume.", signup="https://api-dashboard.search.brave.com/",
       docs="https://api-dashboard.search.brave.com/app/documentation", auth="API key",
       credentials=["BRAVE_SEARCH_API_KEY"]),
    # ------------------------------------------------------------ video --
    _e("youtube_data", "YouTube Data API", "video", "built", "Video search and details.",
       source=("registry", "youtube_data"), costs="Free daily quota.",
       signup="https://console.cloud.google.com/apis/library/youtube.googleapis.com",
       docs="https://developers.google.com/youtube/v3", auth="API key", credentials=["api_key (YOUTUBE_API_KEY)"]),
    _e("meta_messaging", "Facebook / Instagram messaging", "video", "built",
       "Business auto-DM on Facebook / Instagram.", source=("registry", "meta_messaging"), approval=True,
       signup="https://developers.facebook.com/", docs="https://developers.facebook.com/docs/messenger-platform",
       credentials=["app_id", "app_secret", "verify_token"], notes="Needs Meta App Review."),
]

_API_KEY_SETTING = {"gemini": "gemini_api_key", "openai": "openai_api_key", "sarvam": "sarvam_api_key",
                    "brave": "brave_search_api_key", "google_maps": "google_maps_api_key"}

_LABEL = {"LIVE": LIVE_VERIFIED, "CONFIGURED_NOT_VERIFIED": CODE_READY, "UNVERIFIED": CODE_READY,
          "NEEDS_CONFIGURATION": CONFIG_REQUIRED, "DISABLED": DISABLED, "QUOTA_EXHAUSTED": ERROR,
          "CREDENTIAL_ERROR": ERROR, "RATE_LIMITED": ERROR, "DOWN": ERROR, "ERROR": ERROR,
          "TEST_MODE_VERIFIED": SANDBOX_TESTED, "CHECK_FAILED": ERROR, "LIVE_MODE_LOCKED": ERROR}


def _missing(entry: Dict[str, Any]) -> str:
    if entry["approval_required"]:
        return APPROVAL_REQUIRED
    return ACCOUNT_REQUIRED if entry["account_required"] else CONFIG_REQUIRED


def evaluate(entry: Dict[str, Any], probe: Callable[[Any], Dict[str, Any]]) -> Dict[str, Any]:
    """Status + reason for one entry; `probe(source)` returns the live facts."""
    if entry["adapter"] == "not_built":
        return {"status": NOT_BUILT, "reason": entry["notes"] or "No adapter in ASKODOX yet."}
    if entry["adapter"] == "interface_ready":
        facts = probe(entry["source"]) or {}
        if facts.get("ready"):
            return {"status": CODE_READY, "reason": "provider adapter configured; verify with a real document"}
        return {"status": _missing(entry), "reason": entry["notes"]}
    try:
        facts = probe(entry["source"]) or {}
    except Exception as error:
        return {"status": ERROR, "reason": f"state unavailable ({type(error).__name__})"}
    kind = facts.get("kind")
    if kind == "missing":
        return {"status": _missing(entry), "reason": facts.get("reason") or "credentials not set"}
    if kind == "label":
        state = facts.get("state")
        status = _LABEL.get(state, ERROR)
        if status == CONFIG_REQUIRED:
            status = _missing(entry)
        return {"status": status, "reason": facts.get("reason") or str(state)}
    if kind == "registry":
        st = facts["status"]
        if st.get("missing") and st.get("status") != "MOCK":
            return {"status": _missing(entry), "reason": "missing: " + ", ".join(st["missing"])}
        if st.get("status") == "DISABLED":
            return {"status": DISABLED, "reason": "switched off in the Command Center"}
        if st.get("status") == "ERROR" or st.get("last_check_ok") == 0:
            return {"status": ERROR, "reason": str(st.get("last_check_detail") or "the last real check failed")}
        if st.get("status") == "MOCK":
            return {"status": CODE_READY, "reason": "mock mode: wiring only, never a real provider test"}
        if st.get("last_check_ok") == 1:
            return {"status": LIVE_VERIFIED if st.get("mode") == "live" else SANDBOX_TESTED,
                    "reason": str(st.get("last_check_detail") or "a real check passed")}
        return {"status": CODE_READY, "reason": "credentials present; run Check to verify"}
    if kind == "ready":
        return {"status": CODE_READY if facts.get("ready") else _missing(entry),
                "reason": facts.get("reason") or ""}
    return {"status": ERROR, "reason": "unknown state"}


def _prober(container: Any) -> Callable[[Any], Dict[str, Any]]:
    cache: Dict[str, Any] = {}

    def probe(source: Any) -> Dict[str, Any]:
        if not source:
            return {"kind": "ready", "ready": True}
        kind, ref = source
        if kind == "registry":
            from app.api.routes.platform import platform

            return {"kind": "registry", "status": platform(container).registry.status(ref)}
        if kind == "gateway":
            from app.services import payment_gateway_health

            g = payment_gateway_health.check(container)
            if g["state"] == "NEEDS_CONFIGURATION":
                return {"kind": "missing", "reason": g["reason"]}
            return {"kind": "label", "state": g["state"], "reason": g["reason"]}
        if kind == "api_health":
            from app.services import api_billing

            setting = _API_KEY_SETTING.get(ref)
            if setting and not str(getattr(getattr(container, "settings", None), setting, "") or "").strip():
                return {"kind": "missing", "reason": "API key not set"}
            st = api_billing._state(ref, container)
            return {"kind": "label", "state": st.get("state"), "reason": st.get("note") or ""}
        if kind == "otp":
            from app.services import otp_delivery

            if "otp" not in cache:
                cache["otp"] = {c["channel"]: c for c in otp_delivery.channels(container)}
            row = cache["otp"].get(ref) or {"ready": False, "needs": "channel not in ASKODOX_OTP_CHANNELS"}
            return {"kind": "ready", "ready": row["ready"],
                    "reason": "configured; send a real code to verify" if row["ready"] else row["needs"]}
        if kind == "env":
            have = [v for v in ref if str(os.environ.get(v, "")).strip()]
            if len(have) < len(ref):
                return {"kind": "missing", "reason": "not set: " + ", ".join(v for v in ref if v not in have)}
            return {"kind": "ready", "ready": True, "reason": "set; verify with a real test"}
        if kind == "kyc_provider":
            return {"kind": "ready", "ready": ref in dict(getattr(container, "kyc_providers", None) or {})}
        if kind == "partner_hub":
            return {"kind": "ready", "ready": True, "reason": "staff workflow in the Command Center"}
        return {"kind": "unknown"}

    return probe


def catalog(container: Any) -> List[Dict[str, Any]]:
    probe = _prober(container)
    out = []
    for entry in CATALOG:
        row = {k: v for k, v in entry.items() if k != "source"}
        row.update(evaluate(entry, probe))
        row["category_label"] = CATEGORIES[entry["category"]]
        out.append(row)
    return out


def _default_steps(r: Dict[str, Any]) -> List[str]:
    steps = []
    if r["signup_url"]:
        steps.append(f"Create the account: {r['signup_url']}")
    if r["credentials"]:
        steps.append("Railway -> production -> podx-ai-connect -> Variables: " + ", ".join(r["credentials"]))
    if r["how_to_test"]:
        steps.append("Test: " + r["how_to_test"])
    return steps or ["Open the integration in the Command Center and run Check."]


def owner_checklist(rows: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """What only the Owner can do next: built adapters waiting for an account,
    approval or credentials first; then errors; NOT BUILT items are listed
    separately as development work, never as Owner tasks."""
    rank = {ERROR: 0, APPROVAL_REQUIRED: 1, ACCOUNT_REQUIRED: 2, CONFIG_REQUIRED: 3, CODE_READY: 4}
    todo = [r for r in rows if r["status"] in rank]
    todo.sort(key=lambda r: (rank[r["status"]], r["category"], r["name"]))
    return [{"key": r["key"], "name": r["name"], "category": r["category_label"], "status": r["status"],
             "why": r["reason"], "signup_url": r["signup_url"], "costs": r["costs"],
             "steps": r["steps"] or _default_steps(r),
             "how_to_test": r["how_to_test"]} for r in todo]
