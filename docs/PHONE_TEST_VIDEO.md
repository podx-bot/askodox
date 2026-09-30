# Phone test — video journey (phone-test build 1271, staging backend)

Build **1271** from branch `claude/friendly-ramanujan-538sbj`, talking to the **staging** backend
`https://podx-ai-connect-staging.up.railway.app` (Railway environment `staging`, this branch, its own database).
Production and `main` are untouched.

Before you start:
* Install over the current build (same package, same signing key; versionCode 1271 > 1270). No uninstall, no data
  loss. The next production build must be numbered above 1271 to update this phone.
* Staging has its own empty database: sign in again if asked (real OTP), and there are no ASKODOX sellers there, so
  local results come from Google Places / the web.
* WhatsApp is switched off on staging (it can never message real users). Payment gateway, SMS/email, Firebase push,
  YouTube Data API key and affiliate partners are **not configured** -- steps that need them are marked.
* Location allowed (Vijayawada area). Each step says what must happen; note anything different.

## English

1. **Search.** Main Chat: type *"Samsung 43 inch TV review videos"*.
   A **Videos & reviews** section appears after the local/online results, with real YouTube thumbnails, channel
   name and duration. Each card is labelled *"Creator's opinion — not verified by ASKODOX"*.
2. **No videos unless asked.** New chat: *"Samsung 43 inch TV"* → no Videos section.
3. **Watch in the app.** Tap a YouTube thumbnail → the video plays inside ASKODOX (youtube-nocookie player).
   Back → the same chat, same scroll position.
4. **Not embeddable / not YouTube.** If a card is Instagram/Facebook, or the owner blocked embedding, the viewer
   says so and shows **Watch in …**; it never shows a broken player.
5. **Ask ASKODOX.** In the viewer tap **Ask ASKODOX about this video** → back in the same chat, a message
   *"Tell me more about …"* and an AI answer that:
   * says it has not watched the video (only title/description/channel are known),
   * separates what the creator says from ASKODOX's own explanation,
   * invents no specs, prices or ratings.
6. **Follow-up (continuity).** Type *"Is it worth buying, and where can I get it here?"* → ASKODOX searches the
   same TV (no new questions) and shows real local / online options. It must **never** name shops or dealers
   (e.g. "Poorvika", "Reliance Digital") that are not on a result card.
7. **Next step.** Open the video again → tap **Find near me** / **Show deals** / **Compare** / **Used / cheaper** →
   the chat searches that text and shows real local / online / deal options in the same conversation.
8. **Service video.** New chat: *"AC service video"* → service videos straight away (no "tutorial or book a
   technician?" question); the viewer shows **Book a local service**; tapping it searches *"ac service near me"* and
   shows local providers (not product stores). A plumbing search never shows marketing videos made for plumbers.

## Telugu

9. Switch the conversation to Telugu. Type *"శామ్‌సంగ్ 43 అంగుళాల టీవీ రివ్యూ వీడియో"* → videos appear
   (Telugu words రివ్యూ / వీడియో / సమీక్ష / పోలిక are understood).
10. Viewer labels and next steps are Telugu (*దగ్గరలో కనుగొనండి*, *డీల్స్ చూపించండి* …); the disclosure reads
    *"క్రియేటర్ అభిప్రాయం — ASKODOX ధృవీకరించలేదు"*.
11. Ask ASKODOX → the answer is in Telugu and says the video was not analyzed.

## Disclosure

12. No web video is ever labelled Sponsored: without the YouTube Data API key (**not configured**) nothing can be
    declared a paid promotion, so every video shows *"Creator's opinion — not verified by ASKODOX"*. (With the key,
    declared paid promotions would appear **after** all organic results with *"Includes paid promotion (declared on
    YouTube)"* -- not testable yet.)
13. Command Center on **staging** (`https://podx-ai-connect-staging.up.railway.app/admin/console`, your usual admin
    key) → **Video & Social → Videos** → **New**: title *"Samsung 43 inch TV demo"*, the YouTube link from step 1, keywords
    *samsung 43 inch tv*, relationship **Sponsored** (then a second one as **Affiliate**) → it starts *Pending review*: approve it to
    **Active** →
    on the phone search *"Samsung 43 inch TV review videos"* again → the admin video card and its viewer show
    *Sponsored* / *Affiliate — ASKODOX may earn a commission*. (No real affiliate
    partner exists, so no commission is ever recorded.)

## Attribution (staging Command Center → Analytics → Video funnel, and Event stream)

14. After steps 1–7 the video funnel shows video impression → open → watch start → ask → local search / product
    click for the same video reference (`yt_<id>`), tied to the search's trace id. Affiliate click / conversion stay
    0 (no partner configured).

Report for each step: pass / fail + a screenshot for any failure.
