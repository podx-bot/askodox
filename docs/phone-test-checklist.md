# ASKODOX phone-testing checklist

Generated from `backend/app/services/owner_os.py` `ACCEPTANCE_CHECKS` -- the same list is seeded into Command Center -> QA checks
as CODE READY. Only a real phone test with evidence (screen recording / screenshot + note) moves an item to PHONE VERIFIED.
Automated tests use fakes for Sarvam, Brave, Maps and Gemini; they never prove a live integration.

How to record a result: Command Center -> QA checks -> the item -> status PHONE VERIFIED or FAILED, build number, what you saw.

| # | Area | Check | First build | Steps and expected result | Result |
|---|---|---|---|---|---|
| 1 | results | Result Board: Expand shows category boxes with up / down and n/N; position kept after minimize | 1292 | Search something with several options, tap Expand, use the arrows and a vertical swipe, minimize, restore, Expand again. Expected: the same position; full cards; the default board unchanged. | NOT TESTED |
| 2 | results | Provider failure shown as a service problem, not 'no results' | 1292 | When a search provider is out of quota: the board says which source failed and why, never 'nothing found'. | NOT TESTED |
| 3 | voice | Voice: pause / resume / mute / replay, never two voices | 1292 | Ask by voice; pause and resume the reply; ask again while it speaks; mute; long-press a reply -> Replay. Expected: one voice at a time, Telugu stays Telugu, Stop silences everything. | NOT TESTED |
| 4 | chat | Long-press a message: copy / select / share | 1292 | Long-press a reply and your own message. Expected: plain text copied (no ** markers), selectable text, the Android share sheet. | NOT TESTED |
| 5 | chat | Reply meaning colours | 1292 | Ask for advice with a risk. Expected: risky line red, cautions orange, good points green, with icons; most lines plain; readable in Telugu. | NOT TESTED |
| 6 | profile | Profile memory: remembered needs by role; correct / delete / switch off | 1292 | Make two requests, open Profile -> What ASKODOX remembers. Expected: grouped by role, no OTP or card number, correct / complete / delete / delete all / off all work. | NOT TESTED |
| 7 | business | My Roles and My Business sections open real screens (Home unchanged) | 1292 | Profile -> My roles; Profile -> My business: every section opens a real screen; Home has no business tile. | NOT TESTED |
| 8 | business | Conversations & automation: approved answers, handover, honest platform status | 1292 | Add an approved answer, switch ON, try 'refund'. Expected: handover; Instagram / Facebook / WhatsApp not shown as connected without a verified connection. | NOT TESTED |
| 9 | business | My Creations: AI draft from my facts, share only by me | 1292 | Write with AI from your facts, save, share. Expected: no invented price / offer; nothing posted by itself; image generation shown as not available. | NOT TESTED |
| 10 | advisor | TV: advisor asks size / budget / brand, then real results | 1292 | Say 'I want a TV'. Expected: one question at a time (size, budget, brand), 'any' skips only that question, then local + online results; nothing invented. | NOT TESTED |
| 11 | actions | Chicken: typing 'yes' sends the order request | 1292 | Ask for 1 kg chicken near you, open a seller card, type 'yes'. Expected: the same order request as the card button (sign-in asked if needed), shown in Updates. | NOT TESTED |
| 12 | conversation | Car: Maruti then Tata replaces the brand | 1292 | Ask for a Maruti car, then say 'Tata instead'. Expected: results switch to Tata; Maruti is not kept. | NOT TESTED |
| 13 | nearby | AC repair nearby uses the real place | 1292 | Allow location, ask 'AC repair near me'. Expected: Places results near the current place with distance; with location denied, ASKODOX asks for a place instead of searching all of India. | NOT TESTED |
| 14 | jobs | Job openings show job results, not products | 1292 | Ask 'driver job openings in Vijayawada'. Expected: job / employer results only. | NOT TESTED |
| 15 | advisor | Multi-category request keeps each item separate | 1292 | Ask 'I need a fridge and a gas stove'. Expected: both are understood; questions and results per item. | NOT TESTED |
| 16 | location | Location: allow, deny, change place | 1292 | Allow -> header shows the named place; deny -> 'Current location' / pick a place; hand-pick a place -> it is kept even when the phone moves. | NOT TESTED |
| 17 | notifications | Silent notification + tap opens the right screen | 1292 | Receive a request update with the app in the background. Expected: silent notification; tapping it opens Updates on that item. | NOT TESTED |
| 18 | privacy | Privacy: export and delete my data | 1292 | Profile -> Privacy -> Export (file arrives) and Delete account (signed out; old token rejected). | NOT TESTED |
| 19 | voice | Telugu voice in and Telugu reply out | 1292 | Tap the mic, speak Telugu. Expected: correct Telugu transcript, Telugu answer, Telugu audio reply. | NOT TESTED |
| 20 | seller | Seller Opportunities: accept / decline / expiry | 1292 | As a seller open Opportunities. Expected: matching buyer demand listed; Accept opens the request, Decline removes it, expired ones show as expired. | NOT TESTED |
| 21 | video | Video page chat bar answers from the video | 1292 | Open a studied seller video, ask about it in the chat bar. Expected: answer cites the video (time / fact) or says 'not in this video'. | NOT TESTED |
| 22 | updates | Updates + unified inbox | 1292 | Open Updates. Expected: requests, opportunities and messages in one list with unread counts; tapping each opens it. | NOT TESTED |
| 23 | advisor | Advisor: 'car phone holder' = accessories, budget optional | 1292 | Ask 'car phone holder'. Expected: no car questions; budget is optional; 'show me' shows results at once. | NOT TESTED |
| 24 | affiliate | Affiliate catalog product shows with its labels | 1292 | Staff adds an in-stock product with commission ACTIVE. Expected: it appears in matching results labelled Affiliate link; out-of-stock products never appear. | NOT TESTED |
| 25 | affiliate | Marketplace rows: Amazon / Flipkart / Meesho with unverified price | 1292 | Ask for a product sold online. Expected: marketplace rows after local + online, price marked unverified. | NOT TESTED |
| 26 | demand | Demand alert reaches a matching seller | 1292 | With demand alerts on, search for something a test seller sells. Expected: that seller sees an Opportunity (within 10 min), with the reason. | NOT TESTED |
| 27 | flags | Command Center flags reach the app | 1292 | Turn advisor.enabled OFF in Command Center, reopen the app after 10 min. Expected: no advisor hold; turn it back ON and the questions return. No flag change breaks the app offline. | NOT TESTED |
| 28 | selling | Listing with contact details is held for review | 1292 | Add a listing whose description contains a phone number. Expected: 'saved -- will appear once the team reviews it'; staff Approve in Listing reviews makes it searchable. | NOT TESTED |
| 29 | discovery | Search keeps working when web search is paused | 1292 | When Health -> web search is paused/quota, search again. Expected: local + earlier (cached) rows with 'cached' marking, never invented rows. | NOT TESTED |
| 30 | update | In-app update keeps data and sign-in | 1292 | Update from the previous build through the in-app prompt. Expected: no uninstall, same chats, still signed in. | NOT TESTED |
| 31 | web | askodox.com/chat answers like the app | 1292 | Open askodox.com, tap Ask ASKODOX, ask 'TV under 30000'. Expected: the same advisor questions / results as the app. | NOT TESTED |
| 32 | profile | Registration: role drafts + Verify request | 1322 | Profile -> add roles (e.g. Restaurant, Cab driver) -> Menu -> Business & roles. Expected: each role shows Draft with the missing details, or Complete; Verify on a complete role sends a request (only the last 4 characters of the number are kept); staff see it in Command Center -> Role verifications. | NOT TESTED |
| 33 | selling | Ready-made catalogue: Smart Fill from your own words | next release APK after 1322 | My Listings -> Ready-made catalog -> a category -> Details -> type 'cotton, MRP 999, home delivery' -> Smart Fill. Expected: only empty fields fill, only with what you typed; your own choices and price stay; a missing required detail keeps the item a draft. | NOT TESTED |
| 34 | results | Result Board attribute chips filter the shown cards | 1322 | Search for something sellers listed with details (size / colour). Expected: chips like 'Size: 9 · 2' above the cards; tapping narrows the SAME cards (no new search); no chips when no seller gave details. | NOT TESTED |
| 35 | mobility | Rides: goods transport, stops, quotes / counter / accept | 1322 | Menu -> Rides, parcels & delivery -> Tempo -> add a stop, weight, size -> Send. As an approved partner, send a quote; as the customer, counter then accept. Expected: nothing is booked until one side accepts the other's exact amount; the agreed fare shows. | NOT TESTED |
| 36 | radio | Travel Radio: internal tester only, no price | next release APK after 1322 | Staff add your user id in Command Center (POST /admin/cc/radio/testers). Menu -> Travel Radio -> Play next. Expected: 'Internal testing -- no price' label; real place / nearby / news only; the same segment never repeats; Stop silences it; a non-tester sees 'not switched on yet'. | NOT TESTED |
| 37 | plans | Plans: Free / Plus Rs 499 / Pro Rs 999 (7-day trial) shown, nothing sold | next release APK after 1322 | Menu -> Plans & subscription. Expected: Free can be chosen; Plus and Pro say 'Not available yet' with no button; no payment screen anywhere. | NOT TESTED |

## Before you start
- Install the APK from the direct link in `docs/qa-evidence.md` (latest row); check its SHA-256.
- Sign in with your phone number (OTP). Allow location when asked (then also test Deny / Change).
- For Travel Radio, staff must first add your user id as an internal tester (Command Center, POST /admin/cc/radio/testers).
- Billing is NOT active: no step should ever ask for payment. If one does, mark it FAILED.
