# ASKODOX — external configuration the owner must enable

The code for these features is in the repo. It only **works** once the
settings below exist. Nothing here is faked: until a setting exists, the
feature reports itself as not configured (Admin → Integrations).

To see what is live now, use **Admin Web → Integrations → Google Maps →
Check**. It calls each Google API with the key already stored in Railway
and shows `OK` or Google's own error per API. The key is never shown.

---

## 1. Google Maps Platform (key already in Railway: `GOOGLE_MAPS_API_KEY`)

Each API is switched on separately in the Google Cloud project that owns
the key. Do this in **Google Cloud Console → APIs & Services → Library**
(same project as the key):

| API to enable | Used for | Without it |
|---|---|---|
| **Places API (New)** | Nearby shops/providers; place search on the Location screen; naming the town when Geocoding is off | No nearby results; place search empty |
| **Geocoding API** | Naming the current place ("Vuyyuru, Andhra Pradesh") from the backend | The app still names it on the phone (Android Geocoder), then falls back to the Places locality |
| **Routes API** | Pickup → drop distance/time for parcel/ride quotes | Route quote shows no distance |

Then, in **APIs & Services → Credentials → the key**:
- **API restrictions:** allow at least Places API (New), Geocoding API and
  Routes API. A key restricted to only some APIs gets `REQUEST_DENIED` /
  HTTP 403 from the rest.
- **Application restrictions:** the key is used by the **backend server**
  (Railway), not by the app. So use "None" or IP restrictions.
  **Do not** use "Android apps" (server calls would be refused).
- **Billing** must be enabled on the project. The Maps APIs refuse calls
  without it.

You do **not** need to create or replace the key. Enabling these APIs on
its project is enough.

## 2. Background push notifications (Firebase Cloud Messaging)

Today, silent notifications appear only while ASKODOX is open or brought
back. Background delivery needs Firebase:

1. **Firebase console → Add project** (or reuse one). Add an **Android
   app** with package name **`com.askodox.askodox`**.
2. Download **`google-services.json`** for that app. Add it to the build
   in one of two ways:
   - as `android/app/google-services.json`, or
   - as the GitHub Actions secret `GOOGLE_SERVICES_JSON_B64` (base64 of
     the file) for CI builds.

   The Android client (plugin `firebase_messaging` + Gradle
   `com.google.gms.google-services`) is added in the PR that follows once
   this file exists, because the Android build cannot compile the Firebase
   plugin without it.
3. **Project settings → Service accounts → Generate new private key**.
   Put the whole JSON into Railway as the variable
   **`FIREBASE_SERVICE_ACCOUNT_JSON`** (service `podx-ai-connect`).
4. In Google Cloud for that Firebase project, make sure **Firebase Cloud
   Messaging API (V1)** is enabled. The legacy API is not used.

What already works on the server (`backend/app/services/push_service.py`):
- device token registry: `POST/DELETE /api/me/push-token`
- FCM HTTP v1 sender: signed service-account token, **silent**
  `askodox_updates` channel, deep-link `route`, at most once per event,
  dead tokens removed
- hooks: a new request goes to the seller; accept, decline and completed
  go to the buyer
- account deletion removes the user's device tokens

## 3. Affiliate / partner programs (Command Center -> Partner Hub)

Nothing to set in Railway except, optionally, `ASKODOX_PUBLIC_BASE_URL`
(the backend's public https address, e.g. the Railway domain). It is used
for tracked links (`/go/<click id>`) and the postback URL shown to you;
without it the address is taken from the incoming request.

For each partner (any company, any category):
1. Apply on the partner's affiliate / partner program page (store it as
   "Affiliate program signup URL"; notes under "How / where to apply").
2. After approval, copy your tracking / tag ID and build a deep-link template
   in the partner's link tool; paste both. Set the partner's sub-ID parameter
   so ASKODOX's click id comes back in their reports.
3. Level 2 (optional): if the partner gives a product API / feed, fill "Product
   feed/API" and paste the key with "Set key" (stored on the server only).
4. Level 3 (optional): "Postback URL" generates a token and the URL to paste
   into the partner's conversion / postback settings (shown once).
5. Level 4 (always): "Import report" takes the partner's conversion CSV.
6. Press "Test", then "Enable".

An affiliate link alone never gives ASKODOX the partner's product database,
orders or customer care -- only what the partner actually provides.

## 4. Already configured (no action)

`BRAVE_SEARCH_API_KEY`, `SARVAM_API_KEY`, `GEMINI_API_KEY`,
`OPENAI_API_KEY` and the WhatsApp variables exist in Railway. Do not
create or replace them.
