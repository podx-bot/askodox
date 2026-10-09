# APK 1314 — real-phone regression checklist

Build: Android Live Build run 37885318118 (main `bae9c9e`), private artifact
`askodox-phone-test-1314` (signed APK + VERIFICATION.txt). NOT on the in-app
update channel (askodox-latest stays 1313) and NOT a public release.

Install: download the artifact zip from the run page, unzip, install the APK
over 1313 (same package `com.askodox.askodox`, same certificate, higher
versionCode — data and sign-in must survive). Backend: production.

How to record: for each line mark PASS / FAIL / BLOCKED + a screenshot or
screen recording for anything that fails. Only a real phone result moves a
Command Center QA check to PHONE VERIFIED. Test in English AND Telugu where
marked (te).

## 0. Install / update
- [ ] 0.1 1314 installs over 1313 without uninstalling; still signed in; old chats / profile kept
- [ ] 0.2 App does NOT offer an in-app update to anything (channel is still 1313)
- [ ] 0.3 Cold start < ~5 s; no crash; Home unchanged (no My Business tile on Home)

## 1. Voice (one audio lifecycle)
- [ ] 1.1 Centre mic: speak, press Stop -> transcript appears once, request runs
- [ ] 1.1b Continuous recording: talk ~45 s with short pauses (2-3 s); recording keeps going until YOU press Stop
- [ ] 1.2 Reply is spoken by ONE voice only (never Sarvam + device voice together)
- [ ] 1.3 Pause while speaking -> stops; Resume continues from about the same place
- [ ] 1.4 Mute -> next replies are not spoken; Unmute -> speech returns
- [ ] 1.5 Replay on an older message speaks that message (even when muted)
- [ ] 1.6 Start a new voice request while a reply is speaking -> old speech stops at once
- [ ] 1.7 (te) Telugu voice in -> Telugu reply text and Telugu speech
- [ ] 1.8 Silence for 8 s / 2 min limit ends recording safely; no stuck mic

## 2. Messages & replies
- [ ] 2.1 Long-press an assistant message: Copy, Select text, Share, Replay, Mute all work
- [ ] 2.2 Copied / shared text has no [ok] / [caution] / [risk] tags and no markdown symbols
- [ ] 2.3 Meaning colours: good advice green-ish, caution amber, risk red; most lines uncoloured
- [ ] 2.4 Tall Telugu lines are not clipped
- [ ] 2.5 Headings / bullets / bold / tables / links render (no raw ** or #)

## 3. Conversation & search decisions
- [ ] 3.1 "I want an AC" -> asks ONE question (type / room size), no cards yet
- [ ] 3.2 Answer size + budget -> guidance + real results
- [ ] 3.3 Usage note ("multi use") or "Godrej okay, others okay" after results -> NO new search (known risk: may still re-search; report if it does)
- [ ] 3.4 Car: Maruti then "Tata instead" -> brand replaced, not both
- [ ] 3.5 Chicken order: typing "yes" sends the order request (same as the button)
- [ ] 3.6 "Should I buy 1.5 ton or 2 ton?" -> advice only, no search
- [ ] 3.7 Topic change ("now a plumber") -> old deck archived (restore chip), new need searched
- [ ] 3.8 "delivery cheyali" (te) -> asks parcel vs delivery job
- [ ] 3.9 No reply says "showing / here are" when no cards are shown

## 4. Results & Result Board
- [ ] 4.1 Default board = the locked one-rail layout (unchanged from 1313)
- [ ] 4.2 Expand (mega) -> category boxes with up / down and n/N; positions kept after minimize + restore
- [ ] 4.3 Minimize pill "N Results • subject" restores the board
- [ ] 4.3b Pinning: the latest results stay pinned above the chat while you keep chatting (there is no manual pin button)
- [ ] 4.3c Cards: images load, prices shown only when known (else "price not verified"), Open/links open the right page
- [ ] 4.4 Local / online / marketplace / videos / jobs sections appear only when relevant
- [ ] 4.5 Marketplace prices marked unverified; strict budget ("max 30000") hides over-budget rows
- [ ] 4.6 Provider problem (if it occurs) shows "service problem" text, not "no results"
- [ ] 4.7 Follow-ups over cards (cheapest / nearest / compare / reviews) answer from cards, no new search
- [ ] 4.8 Job openings show job results, not products

## 5. Profile & memory
- [ ] 5.1 Profile -> My memory lists remembered needs by role (buyer / seller / service)
- [ ] 5.2 Correct an item; delete an item; switch memory off -> no new items are added
- [ ] 5.3 Privacy: export my data works; delete account removes memory too (test account only!)

## 6. Roles & My Business
- [ ] 6.1 Profile -> My Roles opens; roles shown match what I said I am
- [ ] 6.2 My Business: Analytics/insights first, then Promotions, Automation, Creations; each opens a real screen
- [ ] 6.3 Automation: approved answers saved; handover; platform status honest (not "connected" when not)
- [ ] 6.4 My Creations: AI draft from my own facts; nothing is posted anywhere unless I share it
- [ ] 6.5 Seller Opportunities: accept / decline / expiry

## 7. Location
- [ ] 7.1 Allow location -> header shows the real place name (e.g. Uyyuru)
- [ ] 7.2 Deny location -> honest "set your place", nearby asks for a place (no country-wide search)
- [ ] 7.3 Change place by hand -> stays even when moving; "near me" goes back to the device
- [ ] 7.4 AC repair nearby uses the real place; map picker "Pin here" / "Near X" works

## 8. Attachments
- [ ] 8.1 Photo (camera + gallery) -> described facts used in the reply
- [ ] 8.2 Several photos at once
- [ ] 8.3 PDF / document -> facts extracted
- [ ] 8.4 Short video -> frames analysed, honest when unclear

## 9. Videos
- [ ] 9.1 "Show review videos of <product>" -> videos section; Shorts first when I say shorts
- [ ] 9.2 Video page chat bar answers from the video ("not in this video" when absent)
- [ ] 9.3 Talking about Facebook / Instagram setup stays chat (no video search)

## 10. Existing functionality (no regressions)
- [ ] 10.1 Sign-in with real OTP; act-needs-sign-in flow retries the same action
- [ ] 10.2 History, Updates (request status + unified inbox), Profile tabs
- [ ] 10.3 Silent notification while app open; tap opens the right screen
- [ ] 10.4 Rides / parcels screen opens; honest NEEDS_PARTNER (no driver yet)
- [ ] 10.5 Listing with a phone number is held for review
- [ ] 10.6 Language chip locks reply language; English / Telugu / Hindi replies
- [ ] 10.7 Companion / avatar shows and does not block the chat
- [ ] 10.8 askodox.com/chat still answers like the app
- [ ] 10.9 No crashes in a 15-minute mixed session; battery / heat normal

## 11. Permissions, stability, network
- [ ] 11.1 First use of mic / camera / location / notifications asks permission with a clear reason
- [ ] 11.2 Deny each permission -> app explains and keeps working; allowing later from Settings works
- [ ] 11.3 Airplane mode during a request -> honest "no connection" message, no crash
- [ ] 11.4 Network back -> retry works without restarting the app; chat history intact
- [ ] 11.5 Switch apps / lock screen mid-reply and come back -> no crash, no double voice
- [ ] 11.6 Any crash: note the time + what you tapped (screenshot / screen recording)

## Admin (owner, browser)
- [ ] A.1 Command Center -> API Health & Billing shows real or UNKNOWN balances (no fake numbers, no recharge button)
- [ ] A.2 Incidents + actions: read-only actions run; change actions ask for approval
- [ ] A.3 Release gate shows NOT READY until the phone checks above are PHONE VERIFIED
- [ ] A.4 /admin/backup still creates a verified backup (owner key only)
- [ ] A.5 Command Center -> Integrations -> Brave -> Check: production web search is LIVE (staging is quota_exhausted)

Release of 1314 (update channel or public) needs the owner's separate approval
after this checklist passes.
