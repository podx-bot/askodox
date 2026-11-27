# ASKODOX — Claude Code project memory

Compact by design. Full history lives in `docs/ASKODOX_EXECUTION_TRACKER.md` —
read only its most recent 1–2 round sections, or grep it for a specific past
decision. Never read it in full "just in case." If anything here conflicts
with the actual repo or `git log`/`git show origin/main`, the repo wins — fix
this file, don't trust it blindly.

## Current verified checkpoint
- `main` PR #556 (2026-11-28, owner "do the three remaining parts of item 2"; squash d83ad9c; NOT in any Play bundle): GUIDE SESSION FINISH --
  (a) `GuideSessions.arrangement` + GET `/api/me/guide-session/arrangement`: page ids (`b.` / `s.`) from the person's OWN kept words
  (consent only; `PAGE_HINTS` = page functions, never categories); app `guide_arrange.dart` `askodoxBringFirst` only MOVES top-level
  pages to the front (never hides / groups / deletes), `askodoxApplyGuideArrangement` for Buyer + the shop in view, Undo card
  `askodoxGuideArranged`. (b) intro "Hear it again" `askodoxIntroHear` (same app voice). (c) one push `guide_done:<user>:<time>` when
  the session finishes (te / en / hi, route `/money-home`, `GuideSessions(tell=)`). Registry `guide_session_finish`. Seller side is
  arranged only when a shop is already chosen. Nothing phone verified. Flaky `full-app (3)` (no Android consent prompt) failed twice, not ours.
- `main` PR #546 (2026-11-27, owner "Merge" 22:01; squash 91d77c0; first piece of phase 6; NOT in any Play bundle): YIELD &
  RATES -- buy in one form, sell in another (live birds -> dressed, goat, fish, paddy, cloth roll). Pure integer maths
  in TWO twins: `backend/app/services/yield_math.py` == `lib/features/yield/yield_math.dart`, both run
  `test/fixtures/yield_vectors.json` (change the two together; grams, paise, basis points, halves away from zero).
  cost of a sellable kg = (weight x rate + transport + unloading - by-product income) / what came out; rate up by d ->
  cost up d / yield; day: opening + made - sold = expected, against the scale. App `lib/features/yield/`
  (`/pos/:id/yield`, Seller page `s.yield`, hub `money.yield`; 3 steps bought -> weighed after -> rate, board, day
  end, last lots), book on the PHONE only (`askodox.yield.v1`, account-scoped, per shop id). The owner trials it on
  his own chicken / mutton shop: every number is his entry, NO presets, `AskodoxEstimateNote` on the page. PIECE 2
  (branch `claude/yield-forms-measure`, 2026-11-28): `yield_extras.dart` = other forms (own yield + rate ->
  `askodoxYieldFormCost`), measure card (`askodoxYieldPortionCost` = grams x cost; `askodoxYieldMeasure` = batch /
  plates), `askodoxYieldBoardText` = SELLING rates only for customers (never cost / yield / profit). NOT built:
  sold kg from bills, server sync for staff phones, trend chart.
  Registry `yield_and_rates`. Nothing phone verified.
- `main` PR #544 (2026-11-27, owner "Merge"; squash 1b7a5af; phase 5; NOT in any Play bundle): TABLE WATCH, QR ONLY
  -- `pos_table_watch.py` (`pos_table_sits`: a table + a time, NO customer identity; `sat` from the customer
  `GET /order-desk/resolve` of a TABLE code -- route-level, best effort; states empty / seated / unseen (`UNSEEN_MINUTES`
  5) / waiting (open desk order or staff table order not served) / eating (served); a sitting with no order ends after
  `SIT_HOURS` 3; `seen` / `free` by floor staff; `due_alerts` once per sitting, max 20 a table a day) + periodic job
  `table_watch` (60 s, push to owner / manager / waiter / cashier, route `/pos/:id/tables/watch`). Routes
  `/api/pos/businesses/{id}/desk/table-watch[/{table}/seen|free]` (in `routes/pos_frontdesk.py`). App
  `lib/features/table_watch/` (`/pos/:id/tables/watch`, opened from the Tables page ⋮ `askodoxTablesStepsWatch` or
  the push; refresh 30 s). Camera watch NOT built (owner: QR only). Registry `table_watch_qr`. Nothing phone verified.
- `main` via PR #544 (PR #543 closed: its commits landed inside the #544 squash; 2026-11-27, owner "set the points
  aside, do the rest" = phase 4; NOT in any Play bundle): LIVE WORK WORKOUT -- `lib/features/workout/`
  (`workout_logic.dart` pure rules: better set = heavier or same weight more times, a record needs an EARLIER
  workout's best and is said once per exercise per workout, streak counts to today or yesterday, weight in grams;
  `workout_store.dart` prefs `askodox.workout.v1` account-scoped, last 400 workouts; `workout_screen.dart` pick ->
  set (2 steppers, 2.5 kg step) -> rest timer 90 s by itself -> done), route `/work/workout`, button
  `askodoxWorkWorkout` on the Live Work bar, "my gym" card from `askodoxMyMembershipsProvider`. Free: no server
  call, no AI, NO POINTS (owner gives the rules later -- do not add them). Own code and own exercise list.
  NOT built: own exercise by voice, pay the gym fee from here. Registry `live_work_workout_tracker`. Nothing phone verified.
- `main` PR #540 (2026-11-27, owner "merge and continue phase 3"; squash 06c30d8; NOT in any Play bundle):
  MEMBERS & ATTENDANCE = the gym owner kit as ONE universal engine `pos_memberships.py` (tables `pos_term_members` /
  `pos_term_payments` / `pos_term_visits`; `add_months` == Dart `askodoxTermEnd`, keep equal): term in months + fee ->
  END DAY worked out; `renew` = a fee RECORD that moves the end day (from the old end day if not passed, else today);
  `overview` (members / ending this month / fee to come, ENDING_DAYS 5, LEFT_AFTER_DAYS 30), `attendance` (staff tap
  or the member's own check-in with today's 4-digit `visit_code`, once a day; ABSENT_DAYS 7), `report` (reports perm),
  `mine` / `check_in`, `ending_count` -> morning brief key `renewals`. Every reminder / message = a WhatsApp DRAFT the
  owner sends. Routes in `routes/pos_work.py` (`/api/pos/businesses/{id}/members*`, `/api/pos/me/memberships*`).
  App `lib/features/memberships/` (`/biz/:id/members`, `/attendance`, `/report`, `/me/memberships`), hub key
  `money.members` + Seller page `s.members` (kit flow 5), Buyer page `b.memberships`. `PosMonthly` stays the
  calendar-month due book. NOT built: QR scan by camera (the code is typed), fee by payment voice with automatic
  renewal, voice-filled new member form. Nothing phone verified.
- `main` PR #539 + #541 (2026-11-27, owner "merge without asking; ask only before the Play link, after all work is done"): TEST SWEEP -- web build of the new look driven in headless Chrome (217 routes, demo shop, 390 px + Hindi at 320 px): no crash / blank page / overflow; kiosk `/biz/:id/staff/kiosk` is still a light page (camera, left on purpose); emoji boxes only in the sandbox (no emoji font). BUG FIXED (#539): `PosPaymentAlerts._allowed_with_devices` ignored the owner's per-person "Payment sound" tick (`pos_members.tools` `payalerts`) -- an unticked cashier still heard the owner's payments. `tests/test_pos_payment_routing_audit.py` = who hears what (owner / ticked / unticked / kitchen / removed / other shop / two-shop owner / QR +1 paise / same notification vs two customers). Backend 2107 pass. Local load (single sandbox process, 20 concurrent): /health 120 rps, POS reads ~35 rps, `/api/me/ai-credits` ~11 rps (p50 1.7 s under load, 55 ms alone) -- the heaviest read; per-user rate limits answer 429 by design. Not done: real-AI persona tests (sandbox cannot reach providers), beta 20-50 users, final load test. Nothing phone verified.
- Branch `claude/morning-brief` (2026-11-27, owner "Ok go" = phase 2 of the new plan): MORNING BRIEF --
  `morning_brief.py` (`MorningBrief.shop` / `.me`, READ ONLY: dues `PosDuesFollowup.to_remind` (no pay link made),
  `Automations.low_stock` / `winback` / `habit`, yesterday's bills, own unpaid bills without marking them seen,
  family list open items; max 3 tasks in a fixed order + `more`; `handled` = yesterday's real counts for a member
  with `reports`, a count that cannot be read is left out) + GET `/api/me/morning-brief`,
  `/api/pos/businesses/{id}/morning-brief` (in `routes/automations.py`). App `lib/features/morning_brief/`
  (`/brief`, `/pos/:id/brief`, chip `askodoxMorningBriefChip` above the Home chat only when something waits; flag
  `askodoxMorningBriefChip` on in `main()`; the brief never opens by itself and sends nothing). Money rows show
  `AskodoxEstimateNote` (`shared/widgets/estimate_note.dart` = the owner's rough-figures note, ONE place for the
  wording). Registry `morning_brief_three_things`. New-look Play bundle = `askodox-play-1733.aab` (run 733 on
  2858a66; owner on his phone: "came out well" -- first look only, QR scan not confirmed). Nothing else phone verified.
- `main` PR #527 + #529 + #533 + #537 (2026-11-27, owner "1"; Play bundle `askodox-play-1735.aab` = Live Build run 735 on 76f8fcd, public release `play-bundle-1735`): IN-APP VIDEO Q&A + PAID AUTO SEND -- (#527/#529) uploader pays ONCE for a video's study (AI Credits `video_study`), viewers read the stored study free (`video_study.answer` `use_model=False`), `video_ask_flow.py` next_step answered / product / ask_uploader, viewer messages the uploader in-app (`/api/videos/{id}/message`, generic pushes, no numbers). (#533) bills + baaki: MANUAL = owner's own WhatsApp, free for ever; AUTOMATIC = one `shop_message` use from the OWNER's AI Credits per message (`MIN_RATE_PAISE` 5 while charging ON, `AiCredits.price`, `shop_messages.charge/give_back`; too few credits = nothing sent, refused = given back); `pos_bill_auto.py` (settings `bills.auto_send`, `bills.auto_daily_per_shop`, `whatsapp_cloud` `bill_template_name`, bills < 24 h, ASKODOX users in-app free); reminders `auto.price_paise` + app switch price line. Meta bill template NOT approved yet. (#537) APP LINKS: askodox.com `/v/` `/s/` `/p/` open the app (manifest autoVerify, router redirect to '/'; Caddyfile `assetlinks.json` lists the Play app-signing SHA-256 ONLY, so sideloaded APKs do not verify; `/v/*` proxied to the backend). Nothing phone verified.
- Branch `claude/new-look-1b-all` (2026-11-27, owner "B" = all pages at once; after #530 palette + #531 guard):
  NEW LOOK ON FOR THE WHOLE APP -- 137 files, every hand-written light-UI colour mapped to the dark look (white ->
  card, near-white -> page, pale -> line / dark tint, dark inks -> soft white, strong colours -> their light
  shade, shadows stay black), `Colors.white` -> `AskodoxLook.sheet`, `askodoxNewLookOn` true (not a setting).
  Paper kept light (`AskodoxPaper` on the quick-bill picture and the two QR share pictures; QR poster, PDFs, print
  untouched). No Flutter in the sandbox: only CI saw it compile -- NOBODY HAS SEEN IT ON A SCREEN. Known weak spots
  to check on the phone: bright badges (amber / light green) with letters on them, pictures with white edges, pages
  drawn for a light page. Nothing phone verified.
- `main` PR #522 + #523 + #524 + #525 (2026-11-27, owner "1" / "merge"; server deploy 82f1db2 SUCCESS; NOT in any Play bundle; newest is still 1719): PAYMENT VOICE PAGE + WEB PREVIEW -- (#522) `PaymentAlertsBridge.saveVoiceKinds` / `readVoiceKinds` (the native `_call` swallows PlatformException, so a refused save used to look saved: the switch now goes back + SnackBar `askodoxVoiceSaveFailed`), sheet shows 4 kinds (`askodoxPrimaryVoiceIds` in, out, request, fake) + `askodoxVoiceMoreKinds` ("More (N)"), lock text `askodoxVoiceKindLocked-<id>`, ON / OFF word; onboarding step count `askodoxOnboardingStepCount` ("step N of 5" when the pre-stages are skipped, else of 8). (#523) manual workflow `web-build-preview.yml` (`workflow_dispatch`, `--no-web-resources-cdn`, release `web-preview-N` with `askodox-web-N.zip`). (#524) `Platform.environment` is not supported on web: bottom bar showed the "could not be shown" view (kIsWeb guard in `app_shell.dart`, `askodox_hub_icons.dart`). (#525) 8 px gap before the ON / OFF label (Telugu on 320 dp touched the sentence). LOCAL WEB TEST (cloud sandbox, no Flutter): serve the zip with `python3 -m http.server`, run `backend` with `ASKODOX_DEMO_LOGIN=yes` (demo 9999999999 / OTP 123456), drive with headless Chrome (playwright, `--no-sandbox`), route the production host to localhost:8000; Telugu glyphs need `fonts.gstatic.com/s/notosanstelugu/**` answered with `backend/app/assets/fonts/NotoSansTelugu-Bold.ttf`; other scripts show boxes (no font). Nothing phone verified.
- `main` PR #516 + #518 (2026-11-26, owner "1"; server deploy SUCCESS; Play bundle `askodox-play-1719.aab` = Live Build run 719 on 3de29f8; NOT in any bundle yet: #502, #503, the app side of #496): GUIDE JOURNEY -- onboarding `_pre` stages (location, 23 language boxes, helper intro, terms scroll-to-accept) before the unchanged `_step` flow; `guide_session.py` + `routes/guide_session.py` (`/api/me/guide-session*`, adaptive questions, facts only with consent, `plan(minutes)`, pause / resume, delete, `/api/me/guide-reminders`, `/api/me/feature-requests` + console view `featurerequests`); app `/guide-session` (`lib/features/guide_session/`), reminder chips above the chat (`AskodoxGuideReminderChips`, flag `askodoxGuideReminderChip` on in `main()`). Auto page arrangement, intro voice replay and the done push came in #556. Nothing phone verified.
- `main` PR #495 + #498 + #502 + #503 + #504 (2026-11-26, owner "1" / "merge the pending ones, no Play link now"; Play bundle
  `askodox-play-1708.aab` = Live Build run 708 on fa4260c holds #495 + #498 + chat speed #496 / #500 ONLY -- #502 / #503 need a new build):
  (#495) payment voice customer line = "free for YOU too" in 12 languages (never names a shop). (#498) real HDFC e-mail shape ("account
  ending 1234", payee in brackets after the VPA); a PROVEN debit (debit word + own account + 12-digit RRN) is stopped only by
  `noMoneyMoved` words, never by a mail's banner ad words; `spokenAccountName` = the voice never says "A/c" / digits; mail apps are never
  auto-added -- e-mail card `askodoxMineMailCard` on My phone payments. Skill rule 19. (#502) BILL PHOTO: selling price never demanded --
  a new item without one = `pos_products.buy_only` (never billed: `_issue` 400 `buy_only`; never on the customer menu / online listing;
  app `sellableProducts`; a price > 0 clears it); reader gets TODAY + `total_qty`; screen shows the bill date, row amounts, the rows'
  total; a quantity / rupee mismatch asks "save as it is?" (resend without `supplier_total_paise`). (#503) TRY-ON is not a page: Buy tile
  `b.tryon` removed (route `/try-on` + "Try it" on result cards stay); `image_studio.brand_strip` adds an ASKODOX strip under every
  try-on picture. (#504, another session) hard advice / guides on the reasoning model. OWNER QUEUE (asked 2026-11-26, NOT built): (1) no
  Guide chip / guide button / per-page mics -- ONE Ask button on every page that answers in place (central: `app.dart` overlay,
  `step_kit` `AskodoxStepBottom` mic, `AskodoxFillBar`, `AskodoxGuideChip`); (2) Items list + Add an item + Stock & barcodes = one tile;
  (3) calculator bill (qty x rate rows, share, print) inside Make a bill; (4) "Try it" on a shop's own items / cart (customer menu must
  show item photos first; kit `try_on` kind decides on_me / in_home); (5) a skill for app-wide one-command changes. Nothing phone verified.
- `main` PR #496 + #500 (2026-11-26, owner "1" + "do 1-4, no link now"; NO Play bundle yet -- the app side of #496 needs a build): CHAT SPEED
  rounds 4-5 -- chat calls send `thinking` off (Haiku `disabled`, Sonnet `between_tools`, `_quick_thinking`; the 5.5 models think by default:
  Haiku first word was 5-7 s), a 400 naming thinking / ttl is remembered and retried without it (`_refused_thinking`); fixed instructions cached
  1 h (`_content` ttl "1h", `_TTL_REFUSED` fallback); short plain replies = bubble, no answer card (`answer_card.build`); talk mode echo gap
  (`askodoxTalkEchoGap` 700 ms, counted in 350 ms loop ticks) + `askodoxTalkNoSpeechTimeout` 10 s. Skill `.claude/skills/askodox-chat-speed`
  (log lines + the rules that must stay). NOT built: shorter prompts for small talk, ElevenLabs streaming playback (decide after the phone
  test's new `first_token_ms` / `VOICE SPEAK` numbers). Nothing phone verified.
- `main` PR #497 (2026-11-26, owner "1" = build, then "1 merge, no link now"; NO Play bundle yet -- newest is still 1703, the app side
  needs a new build): (A) AI PLAN -- `ai_credits.py` `PLAN_DEFAULTS` (settings `plan`): Rs 10 free per INDIA day (ledger mode `free`, never a
  balance; `daily_free_days` 0 = for ever), a use takes the free part first then the pack (`usefree:` row for a use paid from both), first
  recharge +`first_bonus_pct` (100 = double, once; refund takes it back, never a second double), first recharge of a day +`daily_bonus_pct`
  (`bonus:` rows), `friend_joined` refill once a day (hooked in `redeem_referral_safely`), `status()` = percent bars + pace + bonus,
  `plan_estimate()`; GET `/api/me/ai-credits` `status`, GET `/admin/cc/ai-credits/plan`, console card `acPlanCard`. App `AskodoxAiBarsCard`
  (shown only when charging is ON; rupees only in the recharge part). Works only once staff turn charging ON with rates (still OFF in
  production). Play builds keep the recharge part hidden (Play payments policy); Play billing NOT built. Older ledger tests pass
  `plan` zeros. (B) PHONE HEALTH -- `phone_health.py` + POST `/api/me/phone-health/report` (`consent` true each time, fixed `CHECKS` only),
  console view `phonereports`; app `/phone-health` (`lib/features/phone_health/`, ☰ `askodoxMenu-phone`): own settings only from the
  payment-alerts `status`, maker families `askodoxPhoneFamily` + `askodoxBatterySteps` / `askodoxAutostartSteps`; no Kotlin change, no
  Accessibility. Not built: opening by itself when payment voice fails / setup stalls. (C) AUTOMATIONS -- `automations.py` +
  `routes/automations.py` (drafts only; `automation_dismissals` = వద్దు / ఇక చూపించకు; settings `automation.*` in `SETTING_BOUNDS`): habit
  (`/api/automations/buyer`, chip `askodoxOneTouch-habit`), bill reminder = app `askodoxAutoBillDues` into the native `dues` (needs My
  phone alerts on), low stock -> DRAFT PO + win-back list (`/api/pos/businesses/{id}/automations`, app `/pos/:id/automations`, chip
  `askodoxOneTouch-noticed`), console view `automations` (call list + staff-pressed help push, once per 7 days a shop), AI cost guard
  (periodic job `ai_cost_guard`, warns only; budget 0 = off). Backend 2029 pass. Nothing phone verified.
- `main` PR #493 (2026-11-26, owner "1"; Play bundle `askodox-play-1703.aab` = Live Build run 703 on 8c64a7a): PAYMENT VOICE -- (1) a late
  app notification of money the person SENT joins the bank's message up to 24 h, any order, unless names clash (`PaymentAlertParser.
  ownMoneyLate`, `OWN_OUT_LATE_MS`; owner: Rs 6,500 SMS 14:03, PhonePe 22:10 spoken again). (2) BANK ALERT E-MAIL = 3rd source: mail
  apps kind `email` (`isMailApp`; catalogue Gmail / Outlook / Samsung Email / Yahoo / Zoho), read only when `bankMail(sender)` AND the
  mail names the person's own account; `BANK_KINDS` sms + email = bank-confirmed; debits carry `rrn(text)` as reference; app hint
  `askodoxBankMailHint` (Gmail Notifications "All"). (3) wording: `A/C 1234XXXX1234` tails, card purchases (`cardSpent`, card's last 4 =
  account, shop after "at"), ATM "withdrawn", "refunded to your account". Account Aggregator NOT built (FIU needs a regulated entity;
  owner chose e-mail). Skill rules 17-18. Nothing phone verified.
- `main` PR #490 + #491 (2026-11-25, owner "finish this" + "1"; Play bundle `askodox-play-1701.aab` = Live Build run 701 on cb4ce24): (#490) FAMILY
  SHOPPING LIST `/me/family-list` (`family_lists.py` + `/api/me/family-lists`: one list per home made on first open, members by 10-digit number,
  invited numbers join on sign-in via `auth_accounts`, numbers shown as last 4 + `member_ref` hash, item open / done / paused, pushes to the others,
  "find nearby" -> chat, account deletion = leave) + BULK PRICE CHANGE `/pos/:id/prices` (`pos_bulk_price.py`, POST
  `/api/pos/businesses/{id}/prices/bulk` preview / apply in one tx with history + audit, `new_price` == Dart `askodoxBulkNewPrice`, never < ₹1,
  tiers / packs / online price untouched); one-touch chips `askodoxOneTouch-family` / `askodoxOneTouch-prices`. (#491) CHAT SPEED: hard turns route on
  the REASONING model (strongest model only for written guide / advice); logs `BRAIN TIMING ... level= search= plan_ms=` + `ASKODOX CLAUDE STREAM`
  (first_token_ms, cache_read); app first spoken part `askodoxFirstSpeechMax` 90 / talk 80 with a comma cut (`askodoxFirstChunkMin` 24);
  answer card `shownReplyIndexes` (no reply = primary label), grid tiles 3 lines shrink-to-fit. Nothing phone verified.
- `main` PR #488 (2026-11-25, owner "5 start" on design B9qtmKXMoH1pdzuvsJKk5u; Play bundle `askodox-play-1698.aab` = Live Build run 698 on fbad2b3,
  branch `play/bundle-1125d`): FINANCE ITEMS -- `finance_items.py` (tables `fin_meta` / `fin_docs` / `fin_qa` / `fin_callbacks` / `fin_misses`; an item is a
  `financial_offer` row of the item store) + `routes/finance_items.py`: staff upload the company's PDFs (pypdf) / photos (vision reader), text kept page by
  page (file not kept); `study` = AI points + Q&A, each kept only when its quote stands on the named page (`_quote_on_page`); `confirm` = staff checked ->
  only then customers see / ask (a new document un-checks); `ask` = answer from the pages with the page, or an executive's saved answer (labelled), else
  "not in the document" + call-back offer (misses counted in `fin_misses`, no person). Call back = sign-in + `consent` true, own `app-phone-` number only,
  staff list masked, `reveal` audited, number wiped on close, deleted with the account; staff task `finance_callback:<item>`. Staff Workspace tab
  "💼 Finance" (shown when `item_types` holds `financial_offer`). App `/finance/:id` (`finance_item_screen.dart`, 3 steps) + result card button
  `askodoxFinanceAskCard-<id>` (`UniversalMatch.itemType`). Log lines `ASKODOX FINANCE DOC|STUDY|ASK|CALLBACK`. Registry
  `finance_items_document_answers_callback`. Limits: scanned PDFs need page photos; ~28k characters of document per question. Nothing phone verified.
- `main` PR #485 (2026-11-25, owner "1"; Play bundle `askodox-play-1696.aab` = Live Build run 696 on 64b2026, branch `play/bundle-1125c`,
  holds #481-#485; design canvas 1uCjwAqSveuZsREavyp7bm "ఒక్క టచ్"): ONE TOUCH STRIP on the కొను / అమ్ము side pages (`money_home/one_touch.dart`,
  key `askodoxOneTouch`): Buy = `askodoxReorderOf` (last finished desk order -> `/order-desk?code=&kind=&cart=`, dine-in -> takeaway, ends on
  total + Send), need it now / compare / problem via `AskodoxChatRequest.ask`; Sell = owner open <-> paused switch (`setBusinessStatus`, Undo),
  `askodoxTodaySpoken` via the guide speaker, stock (desk menu), dues, flash offer (`/notices/new`), shop link; staff by permission.
  Registry `one_touch_buy_sell_strip`. Family list + bulk price change built in #490. Nothing phone verified.
- `main` PR #481-#484 (2026-11-25, owner "do 1-4, show a design for 5"; Play bundle `askodox-play-1694.aab` = Live Build run 694 on 873feb8, branch
  `play/bundle-1125b`): (#481) BAAKI AUTO WHATSAPP -- `pos_dues_followup.py` sends the day's reminder to customers NOT on ASKODOX from ASKODOX's own
  WhatsApp number only when staff set `dues.auto_whatsapp` = 1, the approved UTILITY template is configured (`whatsapp_cloud` `dues_template_name`, five
  body values: customer, shop, amount, pay date, bill link; `comms.send_whatsapp_named_template`) AND the shop OWNER switched it on (`PUT
  .../dues/auto`, `pos_due_settings`); cap `dues.auto_whatsapp_daily_per_shop` (30, `pos_due_auto_days`); a failed / over-cap send stays in the owner's
  one-tap list; no credits (free for ever). NOT usable until the Meta template is approved. (#482) SHOP LINK PHASE 2 -- public menu shows the shop's
  own item photos (`GET /s/{slug}/p/{product_id}`), installs from the link counted once (`POST /api/pos/shop-links/installed`, count kind `install`,
  a number only) via the Play Install Referrer (`MainActivity.readInstallReferrer`, gradle `com.android.installreferrer:installreferrer`,
  `shops/domain/shop_link_install.dart`), the shop opens once after sign-in; owner page shows installs (30 days). `otp-autofill-e2e` now seeds the
  guide intro as seen (the card covered the number field since #411); its "no Android consent prompt" failures stay the known flaky ones.
  (#483) GUIDE TOURS -- `live_work_tour`, `money_tour`, `bill_tour`, `dues_tour` (all info stops), auto-start by exact route or `:id` pattern
  (`askodoxAutoGuideIdFor`). (#484) ASK-NET -- `PaymentAlertParser.unreadBankMoney` + `askAbout`: a registered bank's SMS (own account + amount) the
  phone cannot read = ONE ❓ row + notification, answered in the row (in / out / not a payment), learned by `skeleton`; max 3 a day; skill rule 16; the
  consented shape upload is NOT built. Item 5 (finance items) was built in #488. Nothing phone verified.
- `main` PR #449 + #454 + #455 + #456 (2026-11-24, owner "don't stop, finish the remaining pages; no link needed now"): 3-STEP WORK PAGES BATCHES 15-21 --
  `desk_settings_steps_screens.dart` (Desk settings `/desk/:id/settings`), `desk_menu_steps_screens.dart` (Desk menu `/desk/:id/menu`: list, add by text),
  `printer_steps_screens.dart` (`/pos/:id/printer`), `biz_menu_steps_screens.dart` (`/biz/:id/menu*` sections), day report (`/biz/:id/reports/day` ->
  `AskodoxReportsStepsScreen(date)`), `att_setup_steps_screens.dart` (`/biz/:id/staff/setup`), `my_bills_steps_screen.dart` (`/me/bills`); old pages at `?full=1`.
  NOT converted then (several done in batches 25-36 below): kiosk (camera / face), shop advance / terms pages, hubs, `/me/payment-alerts`.
  Then batches 22-24 (PR #459 / #460 / #461): `my_deliveries_steps_screen.dart` (`/me/deliveries`), `branches_steps_screen.dart` (`/me/branches`),
  `agents_steps_screens.dart` (`/pos/:id/agents`, `/pos/:id/agents/:agent`); the owner's `/pos/:id/deliveries` was ALREADY 3-step (step kit). Old pages at `?full=1`.
  Then batches 25-36 (PR #464-#475, 2026-11-25, owner "Ok good go"), all in `lib/features/steps/presentation/`, old pages at `?full=1`:
  `my_work_steps_screen.dart` (`/me/work`), `hire_steps_screen.dart` (`/hire`), `catalogue_steps_screen.dart` (`/pos/:id/catalogue`),
  `payment_methods_steps_screen.dart` (`/me/payment-methods`), `buyer_agent_steps_screen.dart` (`/me/agent`; `/bills/:id` = `AskodoxBillHistoryStepsScreen(fullRoute:)`),
  Coming up `/me/dues` (`AskodoxUpcomingStepsScreen` in `money_screens.dart`), `order_track_steps_screen.dart` (`/order-desk/track/:oid`),
  `order_code_steps_screen.dart` (`/order-desk/enter`), `table_order_steps_screen.dart` (`/pos/:id/order/:oid`), `shop_chooser_steps_screen.dart` (`/pos`, `/crm`;
  `/pos/:id/crm/leads` without `?stage=` = Enquiries), `purchase_steps_screen.dart` (`/pos/:id/purchase/new`), `item_details_steps_screen.dart` (`/pos/:id/item/:pid`).
  Then batches 37-38 (PR #477 / #478, owner "Ok go"): `selfshop_steps_screens.dart` (`/pos/:id/selfshop` = `AskodoxSelfShopOwnerStepsScreen`,
  `/pos/:id/selfshop/:sid` = `AskodoxSelfShopCheckStepsScreen`: photo first, then the button becomes Bill; `/shop-scan` = `AskodoxShopScanStepsScreen`),
  `order_desk_steps_screen.dart` (`/order-desk`: items -> way -> total + Send order; tap = one more, hold = less / note; a chat cart opens the later step).
  STILL old pages (left on purpose): payment alerts / payment voice settings, kiosk (camera / face), shop advance + terms (consent), and the four big
  owner-shaped screens `/pos/:id` dashboard (a hub), `/pos/:id/sale` counter bill (owner layout 2026-11-23), `/me/payments` (four tiles), `/money`.
  Play bundle `askodox-play-1688.aab` = Live Build run 688 on 58dfc93 (branch `play/bundle-1125`) holds batches 1-38. Owner 2026-11-25: the three big-page
  designs (dashboard / payments / Money, artifact N7YST95Zv6eTpGzJzyPAsw) are KEPT AS A PLAN, not built -- decide after his test. Then the Money row sheet
  shows the row's own message for my-phone rows (`askodoxMoneyDetailMessage`, after bundle 1688). Nothing phone verified. Flaky: `test_profile_memory` (rerun the registry job);
  build-apk can fail on a Maven Central 429 while Gradle downloads (not our code -- rerun the job).
- `main` PR #452 (2026-11-24, owner "1"; Play bundle `askodox-play-1671.aab` = Live Build run 671 on 5e463b9, dispatched from branch `play/bundle-1124` because main merges kept cancelling main builds (concurrency group per ref); owner: one payment
  said twice (second message an hour later / two at once), voice cut before the last word then said again, 9 pm count 4-5 times):
  `pickSamePayment` checks the SAME reference before the same-app rule (same RRN from the same app / SMS app = same money);
  two apps of ONE kind join only WITH PROOF (same payer id / name or the very same text `messageKey`) within
  `SAME_KIND_APPS_MS` 10 min -- never on amount + time (owner: two customers can pay the same amount at once); payer id
  compared before '@'; `Row.apps` / `Row.textKeys` (event `merged_keys` / `text_keys`). Shop push vs this phone's own
  message: `claimHeard` pairs one local + one remote per shop + amount within 2 h (prefs `voice_heard`, was 2 min). Voice:
  `PaymentVoicePack.joinMp3` (frames only, no ID3 / Info frame mid-file) + `mp3DurationMs` -> `Player` limit; a voice already
  heard is never repeated (`sayAgainAfterFailure`). Night = ONE voice per phone (`nightTotal`, mark `night_said:<day>`).
  Skill rules 12-15. Bank SMS vs app notification amount-only 2 h join kept (owner asked whether to change it -- open).
  Nothing phone verified.
- `main` PR #438-#447 (2026-11-24, owner "remaining pages, all in order"; Play bundles `askodox-play-1650.aab` / `askodox-play-1655.aab` before these): 3-STEP WORK PAGES BATCHES 4-14 --
  `glance_steps_screens.dart` (Baaki reminders `/pos/:id/dues`, Bills `/pos/:id/invoices`, Stock `stock-report`, Cashbook, Reports),
  `report_steps_screens.dart` (GST, Purchase orders, Bill history, Sales), `account_steps_screens.dart` (customer / supplier account),
  `person_steps_screens.dart` (one staff member's month `/biz/:id/staff/person/:ref`, Night report settings), `collect_steps_screens.dart`
  (Collect by UPI), `invoice_steps_screens.dart` (one bill), `crm_steps_screens.dart` (CRM lead), `crm_more_steps_screens.dart` (complaint,
  customer history), `desk_qr_steps_screens.dart` (shop / table QR), `items_steps_screens.dart` (Items), `pos_staff_steps_screens.dart` (POS
  staff); every old page stays at `?full=1`. NOT converted (forms / pairing / settings): Desk menu + settings, Printer, `/biz/:id/menu*`,
  staff setup / kiosk, reports/day, hubs. Nothing phone verified. CI note: `AskodoxStepPersonRow` needs `onTap` (use `() {}`) and a SHORT
  `amount` word (the row overflows in the wide test font).
- `main` PR #434 + #435 + #436 (2026-11-24, owner "13 work pages, split 5 at a time, merge each after CI"; Play bundle `askodox-play-1650.aab` = Live Build run 650 on a51022a): 3-STEP WORK PAGES BATCHES 1-3 --
  `order_steps_screens.dart` (Live orders `/desk/:id`, Kitchen, Tables, Suppliers & purchases), `people_steps_screens.dart`
  (Customers, Enquiries `/pos/:id/crm`, Workers & team), `staff_steps_screens.dart` (Today's attendance, Salary); old pages at
  `?full=1` (CRM `?tab=` still opens the old page). Already 3-step, not rebuilt: Delivery, Today's post, Add an item (desk menu),
  Tasks. Still not 3-step: ~47 pages (31 glance, 21 settings, minus these). ASKODOX Lite steps 4-5 ON HOLD. Nothing phone verified.
- `main` PR #433 (2026-11-24, owner "finish the 2; Lite steps 4-5 = HOLD, do not build"): 3-STEP WORK PAGES -- `work_steps_screens.dart`
  (`AskodoxJobStepsScreen` job cards: one number + list, tap = next status / owner UPI QR, New job = what -> estimate -> token;
  `AskodoxMonthlyStepsScreen` who paid -> how much -> done; `AskodoxBookingStepsScreen` today's list, tap = status / QR); routes
  `/biz/:id/jobs|monthly|bookings` open the old pages at `?full=1`. Table / parcel / delivery bill pay sheet now passes `shopUpi`
  (owner's QR). ASKODOX Lite steps 4-5 are ON HOLD by the owner. Still not 3-step: the other ~60 pages (13 work, 31 glance,
  21 settings). Nothing phone verified.
- `main` PR #432 (2026-11-24, owner "finish the pending work, then bundle + link"): OWNER QR IN EVERY WAY -- `pos_collect_refs.py` + POST
  `/api/pos/businesses/{id}/collect/for` (job card balance / booking price / monthly due -> the OWNER's own UPI QR, one open QR per
  thing via `pos_payment_requests.ref_key`, +1 paise rule kept; `_tell_both` -> owner + the person who showed it, route
  `/pos/:id/payment-alerts`; owner confirm -> `settle` records it on the card / due); app `askodoxShowCollectQr`
  (`collect_qr_sheet.dart`) + buttons `askodoxJobQr-` / `askodoxMemberQr-` / `askodoxBookingQr-`. BRANCHES: `pos_branches.py`
  (`pos_branch_groups` / `pos_branch_members`, owner links his OWN shops; `sibling_ids` -> `pos_delivery_jobs._people` = one
  delivery pool; GET/PUT `/api/pos/me/branches`, `.../{group}/overview` today per branch + total); app `/me/branches`
  (`AskodoxBranchesScreen`, Seller page `s.branches` owner-only). Not built: Lite steps 4-5 (native), the 3-step design for the
  remaining pages; table / parcel bills use the counter pay sheet QR. Nothing phone verified.
- `main` PR #429 + #430 + #431 (2026-11-24, owner "finish 3-6, merge, link after everything"): ONE-SCREEN ANSWER CARD
  (#429, design WfPV8AhvZsPFqmwzYpfvap) -- capability `answer_card`: the brain writes spoken part + a `[[more]]` line +
  details (`answer_card.PROMPT_RULES` in routing + `_advise`); route `_answer_card` builds `card` (one fast `write_text`
  call, `answer_card.clean` validates: helplines / 10-13 digit numbers / https links present in the text only, fixed
  action kinds; `from_text` fallback); old apps get the reply without the mark. App `AskodoxAnswerCardView`
  (`answer_card_view.dart`): headline + voice, 4 icon tabs, swipe cards / tiles / checklist / steps, replies with in-card
  follow-ups, risk meter + coloured SMS + `openUpiApps` (MainActivity, opens apps only) + 3 don'ts + share; `_cardByTurn`,
  streaming shows / speaks only `askodoxStreamingSpokenPart`. LANGUAGE: `romanized_language.py` == Dart
  `romanized_language_tables.dart` (generated; drift test) + fixture `test/fixtures/romanized_language_cases.json`;
  server `reply_locale` overrides the app locale unless capability `lang_lock`; `reply_language` back to the app.
  Capabilities max 20. Rich reply: a tag after a bullet no longer prints a stray "-". WORKFORCE (#430 steps 1-2):
  `pos_delivery_jobs.py` (one line -> job card #order number, Google Routes cached per pair, ask free people, answers,
  give / first "now", colours `pos_work_status` free / busy / off, grey 3 h, red 23:00, cash per person, day report),
  `/pos/:id/deliveries` + `/me/deliveries`; owner-UPI collect: same open amount -> +1 paise, matched -> `_tell_both`.
  (#431 steps 3-6) `workforce.py` + `routes/workforce.py`: worker cards (18+, no phone) to every GST / Udyam business of a
  matching category (resource `work_types`, agency = all), invite / accept (joined = pos_members delivery), documents by
  the worker's one-time code view-only 10 min, customer `/hire` -> business + its FREE workers, self-taken = CASH (owner),
  refusing while free = minus point (1 star), share record, complaints, postings + live-face site attendance, ratings
  (done + paid, once a month per customer) + స్వతంత్రుడు badge (settings `workforce.*`). Plan + owner changes:
  `docs/WORKFORCE_PLAN.md` (no advice card; multi-branch shared pool NOT built). Backend 1979 pass. Nothing phone verified.
- `main` PR #425 (2026-11-24, owner "do all 4, merge after" -> "1"; Play bundle `askodox-play-1635.aab` = Live Build run 635
  on f887310): BUSINESS KIT -- 23 categories / 200 sub-categories (`business_kit.py`, Command Center resource `business_kit`,
  staff add rows, no code), one shop = many businesses (profile `more`), pages from the union of the ways of working,
  customer questions answered from the owner's answer only (`shop_qa`). ITEMS BY THEMSELVES: shelf / packet photo -> each item
  cut out with its photo (`read_shelf`), barcode -> name / brand / pack / MRP / photo (`product_master.py`, Open Food Facts).
  WAYS 3-6: bookings (slot or day), job cards (token, ready -> push / WhatsApp), monthly members (`pos_work.py`), enquiries
  = CRM up front; Buyer pages My bookings / My repairs & orders / My monthly. PHOTO TRY-ON: `POST /api/images/try-on` + `/try-on`
  + "Try it" on result cards. Backend 1943 pass, CI green. Nothing phone verified.
- `main` PR #423 + #424 (2026-11-24, owner "no more designs, merge and finish everything"): (#423) ☰ menu: Feedback + "Your
  idea" = ONE "సలహాలు & సూచనలు" / Ideas & suggestions (`askodoxMenu-ideas` -> `/me/ideas`); Customer care (`askodoxMenu-care`,
  `askodoxCareMenuValue`) opens the Home chat with `askodoxCareOpening` (AI-first care in `app_care.dart`, unsolved -> ticket
  email + Command Center); website support / report-a-problem links removed. (#424) PAID NOTIFICATIONS: `notice_broadcast.py`
  + `routes/notices.py` (`/api/notices/preview|mine|{id}|{id}/image`, POST `/api/notices`): anyone sends to own shop's
  followers (owner only) / people within 1-10 km (profile lat/lon) / both; rate `notices.rate_paise` (5) x people via
  `AiCredits.spend` (free while charging OFF; `refund_unused` for phones not reached); receivers: push kind `offers`
  (app switch), max `notices.per_day_receiver` (3) a day + 1 per sender, quiet 21:00-08:00 IST, no links / phone numbers,
  `talk_moderation` masks words; app ☰ `askodoxMenu-notify` -> `/notices/new` (subject -> AI design via `/api/images/edit`
  or own photo -> audience chips -> count + price -> Send, sent list), viewer `/notice/:id`. TODAY'S POST: the box is a
  subject, "AI design" (`askodoxShopPostDesignPrompt`) draws picture + greeting line, card keeps the shop + ASKODOX bar
  (post limit 2 MB). CUSTOMER SUGGESTIONS: `pos_customer_suggestions.py` (orders with phone + sent bills, not in the list,
  ✕ = `pos_customer_suggest_skips`) + GET/POST `.../customers/suggestions[/skip]`, strip `AskodoxCustomerSuggestions` on the
  Customer list. STAFF PAGE holds "Order alerts: who hears each step" (`askodoxStaffOrderAlerts` -> `/desk/:id/settings`);
  Seller pages `s.orderalerts` + `s.agents` removed. చెప్పు BUTTON: guide tab label "చెప్పు" / "Tell"; guide sheet top =
  `AskodoxCommandMic` (`command_mic.dart`: stops 2 s after speech / 6 s no speech, 3 s countdown with Stop / Change, then
  `AskodoxChatRequest.ask` + Home). LITE STEP 6: shop link GET `sms_text` (`ShopLinks.sms_card`, <= 160) + button
  `askodoxShopLinkSms` (sms: composer). TASKS: `rank_task_chips` (90 days, half weight / 14 days, x1.6 near this hour,
  usual person, pin / hide in `pos_task_chips`, day-one starters by template) + GET/PUT `.../tasks/chips`, chips strip
  `askodoxTaskChips`, person picked by face (`AskodoxStaffFace`, today's check-in photo). COUNTER ORDERS: Counter bill chips
  Bill now / Table / Parcel / Delivery (`pos_counter_orders.dart`) -> "To kitchen" = `deskStaffPlace` (source counter) ->
  Live orders (KOT, delivery person, bill). Also #421 (counter pay UPI QR + బాకీ). Lite step 4 (staff phones over Bluetooth)
  and step 5 (Lite app) NOT built. Nothing phone verified.
- `main` PR #411 (2026-11-23, owner "1"; in Play bundle `askodox-play-1625.aab` = Live Build run 45235830781 on 029e161, with
  #414; design artifact SpUyet3NmCbMqCQZNorWYE "ASKODOX గైడ్ ఆన్ / ఆఫ్"): GUIDE SWITCH -- `lib/features/guide/guide_switch.dart`:
  `askodoxGuideOnProvider` (prefs `askodox.guide.on.v1`, default OFF), `AskodoxGuideChip` (key `askodoxGuideSwitch`, grey
  "గైడ్ ఆఫ్" / gold "గైడ్ ఆన్", 2 s SnackBar banner) inside the header wordmark FittedBox (Phase 1; the header language chip
  is Phase 2 only -- language lives in the ☰ menu) and on the sign-in screen; `askodoxGuideIntroOnce` = one card on the
  first open (only when `askodoxGuideIntroEnabled`, set in `main()`), ON there starts the `signin` walkthrough at once.
  Engine: guide ON + no touch for `askodoxGuideIdle` (5 s) -> `askodoxAutoGuideRoutes` ('/onboarding' -> `signin`, '/' ->
  `home_tour`), each until finished once (prefs `askodox.guide.done.v1`) or stopped twice; the `signin` flow runs on the
  private sign-in route (`_pausedFor`) and never reads input; new step kind `info` (tour stop, moves on with "తర్వాత").
  New keys `askodoxLanguageContinue`, `askodoxComposerField`. Registry `guide_switch_idle_walkthrough`. Home tour stop 4
  targets `askodoxNavPayments` (Buyer side only). Next (not built): walkthroughs for Live Work / Money pages / bill / dues,
  voice in all 23 languages (guide speaks te / en). Nothing phone verified.
- `main` PR #415 (2026-11-24, owner "charging on + show users their bill + test with real users, no money cut";
  server deploy SUCCESS; Play bundle `askodox-play-1627.aab`, Live Build run 45248778919): TRIAL METER -- `ai_usage_meter` binds the signed-in user per request (`AiUsageUserMiddleware`, outermost,
  valid token only; `bind_user` / `current_user`; `Thread.start` + `ThreadPoolExecutor.submit` carry the id) and every
  metered provider call also writes `ai_usage_user_daily` (day / user / group chat|voice|web_search|image / uses = one per
  request + group / calls / cost_paise ESTIMATE). `user_usage` = value (cost x markup) today / month -> `usage` in GET
  `/api/me/ai-credits` when setting `show_usage` (default ON) -> app card `askodoxAiCreditsUsage` ("testing: nothing is
  deducted"); staff GET `/admin/cc/ai-credits/users` (masked last 4) + console AI Credits card + `show_usage` switch.
  Worker threads carry the user only via `ai_usage_meter.carry(fn)` (a global threading patch broke a video test).
  `PlatformRepository.update` now runs under BEGIN IMMEDIATE (lost-update race behind the flaky native-video DM test,
  `tests/test_platform_update_lock.py`). Real charging stays OFF (ON with no balance answers chat with a Recharge notice -- `test_ai_credits`). Not phone verified.
- `main` PR #414 (2026-11-23, in Play bundle 1625; owner: "I drop Report settings on Sales and it becomes a group; it must sit in
  THAT place, Buyer and Seller alike"): a page dropped on a page = `AskodoxLaunchLayout.placeAt` (takes the target's place, the rest
  shift), never a folder. Folders only from the page menu "Put in a folder" (`_folderSheet`: an own folder or another page); a drop on
  the middle of a folder the person already made still goes into it. Tests: `launcher_layout_test.dart`, `money_home_screen_test.dart` (+2).
- `main` PR #406 + #407 + #408 (2026-11-23, owner "1"; server deploy 8b5a5b3 SUCCESS; Play bundle `askodox-play-1619.aab`, Live Build run 45216267983): (#406) SORT WITH AI
  = `pos_menu_sort.sort_menu` numbers items once, 25 per part in parallel, missing items asked again, `_parse` skips a cut
  last line; `MenuSortJobs` (one running job per shop, 30 min) + `POST .../desk/menu/sort?background=1` / `GET` -> push
  when done. Counter bill: grid on top, folding cart only when not empty, command + search boxes BELOW above Total; pay sheet
  one tap for the typed amount + `askodoxPosAllDue`; `askodoxBillModeHow` (other_upi / bhim -> UPI, never "Other"); bottom
  bar 8 dp side padding (అమ్ము not cut). (#407) ACCOUNT SIDES: `AskodoxMoneyPlace.side` mine / shop / off,
  `PaymentAlertParser.accountSide` (suffix match, then app side) -> `routeByAccount` in `handle` (OFF = `account_off`, not
  read); accounts card "నా QR / ఖాతాలు" (switch per account, "whose is ••1234?", shop ON -> `moveAccountRows` this month's
  rows to the shop as `moved` events: owner only, <= 40 days, never spoken). Money = money pages only
  (`askodoxMoneySectionIds`); కొను / అమ్ము = shell branch 2 `/mode` (`AskodoxMoneyHomeScreen(section: 'side')`, search
  `askodoxSidePageSearch`), layouts per section (`.side` prefs keys). (#408) ATTENDANCE: own phone needs the real location
  (`require_location`; fake GPS `GeoPoint.mocked` -> 403 `mock_location` + owner told; no pin -> 409 `no_pin`, owner sets it
  in one tap; far -> 409 `far` unless `outside` = "ask the owner", note `outside`); coming in / half = live face check
  (`AskodoxLiveCheck`, `live_face_screen.dart`, google_mlkit_face_detection on the phone, random turn / nod / blink, method
  `face_live`, kiosk `kiosk_live`); older app = note `old_app`. Rule `.claude/rules/attendance.md`. Proves a live person, not
  WHICH person (no face matching). Nothing phone verified. Then #410 (owner "1", Play Console "significantly increases
  the size" on 1619 = 118.9 MB): the face model comes from Google Play services (`play-services-mlkit-face-detection`,
  bundled `com.google.mlkit:face-detection` excluded in `android/app/build.gradle.kts`, manifest
  `com.google.mlkit.vision.DEPENDENCIES` = face, guard `tests/test_android_app_size.py`) -> Play bundle
  `askodox-play-1621.aab` = 105.3 MB (1611 was 104.5 MB), Live Build run 45228699477.
- `main` PR #405 (2026-11-23, owner "step 3" = ASKODOX Lite step 3): NO NET CHAT --
  `home/domain/offline_questions.dart`: `askodoxOfflineAsk` (pure, money + time words te / hi / en) ->
  `askodoxOfflineAnswer` from the phone's own payment rows (today / yesterday / week / month, last, who paid; always
  says "phone's payment messages, not the bank balance"; phone voice); any other question -> `AskodoxHeldQuestions`
  (prefs `askodox.offline_questions.v1`, account-scoped, max 10, 24 h) and asked by itself when
  `AskodoxNetQuality` leaves offline (`_askHeldQuestions`, notification when the app is not in front). Strip above the
  composer `AskodoxOfflineAskStrip`. Steps 4-6 of ASKODOX Lite NOT built. Nothing phone verified.
- `main` PR #403 (2026-11-23, owner "2" = ASKODOX Lite step 2, choice A): LITE MODE --
  `lib/core/net/net_quality.dart`: `AskodoxNetQuality.instance` (ValueNotifier, started ONLY in `main()` with
  `askodoxHealthProbe` = `/health` timing; >= 2.5 s slow, failed / 6 s = offline, two readings < 1.5 s = good again,
  pure `askodoxNetAfter`; checked at start, on every send, every 20 s while Lite / 2 min otherwise). Home chat:
  `AskodoxLiteBanner` on top of the column; in Lite `_streamSpeaks` is false (text streams and shows at once),
  `_speakChunks` sets no reveal and shows chip `askodoxVoiceComing` until the first audio is here; result card photo =
  `AskodoxLiteImage` (tap to load). Steps 3-6 of ASKODOX Lite NOT built. Nothing phone verified.
- `main` PR #400 (2026-11-23, owner "1"; no Play bundle yet; owner phone: Jio recharge Rs 448 from ICICI, "debited for Rs
  448.00 ...; Jio Prepaid Recharge credited" = no voice, no row): `PaymentAlertParser.withoutPayee` drops the payee slot
  ("; NAME credited", "and Cr. to X", "and credited to X", a UPI id) from the DEBIT checks only, so words in a payee's
  name (recharge / emi / loan / offer / credited) never drop a debit; HDFC / Kotak "Sent Rs.X from" and BoB "Rs.X Dr. from
  A/C ... Cr. to" = the bank's own debit (BoB payee from "Cr. to"). The operator's "Recharge Successful" SMS stays
  ignored (reaches the recharged number). Skill rule 10. Parser gate +17 checks + one-row scenario. Nothing phone verified.
  Offered next (owner has not said "చేయి"): a ❓ net for bank SMS with an amount the parser cannot read (ask in / out /
  not a payment, learn the skeleton, shape-only upload with consent).
- `main` PR #399 (2026-11-23, owner "1"; Play bundle `askodox-play-1611.aab`, Live Build run 45132985124; owner "start the 6
  in order" on design artifact MUmbrCksUD9Mq1HR1ELT4U, ASKODOX Lite step 1 of 6 -- steps 2-6 (slow-net Lite mode, offline
  questions, staff phones over Bluetooth, Lite app, light shop page + SMS card) NOT built): NO NET = SAME VOICE -- `PaymentVoicePack.kt` (pure, in the parser gate): number words te / hi / en
  (`numberWords`, Indian system; te 1 = "ఒక్క", 100 = "వంద", 1xx = "నూట"), `packTexts` = number words + the words of EVERY
  sentence the phone speaks (from the same builders; gate `voicePackChecks` fails if any clip of any sentence is missing),
  `clipsFor` (part -> clips). `CloudVoice`: parts kept per voice + language (`payvoice/<voice>_<lang>/`, pack in `pack/`,
  never pruned), `warmPack` once per voice + language, `say(..., alt)`: fetch fails -> `offlineFiles` (heard parts + pack)
  -> the name-less `alt` -> phone voice last. Server header `X-ASKODOX-TTS-Voice-Id` -> `checkVoiceId` drops a voice's
  parts when the ElevenLabs voice changes (prefetch asks fresh first). ASKODOX LINES (all ON, switches `tune` / `hello` /
  `night` / `customer` in the Payment voice folder, `askodoxBrandVoiceKinds`): tune `res/raw/askodox_tune.ogg` replaces
  the chime (`Player.playTune`), hello before the day's first spoken payment, customer line from the 3rd payment max 2 a
  day 2 h apart (`brandChoice`, prefs `brand_*`), night count 21:00 (`night_at`) via AlarmManager -> receiver action
  `ACTION_NIGHT` (Play builds only declare the receiver) -> `nightCount` per side only when today had counted incoming
  payments (no payment = no voice, no notification). Voice language: first My phone visit / a shop's first settings save =
  app language, else the region from the location label (`voice_language.dart`), else the phone's. Nothing phone verified.
- `main` PR #398 (2026-11-23, owner "1"; in Play bundle `askodox-play-1611.aab`; owner "female voice for all languages, remove Automatic / Male / Female"):
  ONE APP VOICE = `elevenlabs_tts.APP_VOICE` (ElevenLabs "Chaitra G", lively Telugu female) for every reply / payment
  part in every language; `voice_for(lang, "automatic")` -> `app_voice_for` (override `ELEVENLABS_APP_VOICE_<LANG>` /
  `ELEVENLABS_APP_VOICE`); explicit genders stay only for product-video presenters. `/api/in-app/voice/speak` always asks
  "automatic" (older apps' male / female2 ignored, header echoes them), Sarvam fallback = female. App: Profile voice row
  gone, saved choice dropped on start; payment-alert voice dropdown -> fixed row (key `askodoxPayAlertVoice` kept), phone
  config voice "female"; Kotlin `CloudVoice` keys kept parts with `VOICE_CACHE_TAG` (old-voice parts never joined), phone
  voice fallback female. Nothing phone verified.
- `main` PR #396 (2026-11-23, owner "1"; in Play bundle `askodox-play-1611.aab`; owner phone: PhonePe "2 new completed transaction updates · A has
  sent ₹3,000 to your bank account HDFC Bank-NNNN · ₹3,360 has been sent to B" came 9.5 h after the ₹3,000 had come IN
  and was read as ONE message: row "❓ −₹3,000 · B", voice "B కి 3000 రూపాయలు వెళ్ళాయి"; owner "do it + late + sorry +
  an immediate 'check once' notification"): SUMMARIES -- `PaymentAlertParser.digestLines` / `digestLinesOf` (two or more
  lines / bullets that EACH carry an amount + a counting heading or bullets; the listener passes every piece of the
  notification, the fullest ONE is read, pieces are never added together); `parse` of a whole summary = Ignored; phone
  `handle` reads each line alone (`summaryKey` = line identity kept 2 days, `summaryTaken` = one row per line):
  `Msg.summary` joins the row of the same amount + direction up to `SUMMARY_MS` (48 h) before it, even a row the SAME
  app made, unless both names share no word (`namesClash`); joined = silent; no row = written (`from_summary`), said
  ONCE as "ఆలస్యంగా తెలిసింది: ..." (`late_in` / `late_out`, follows the in / out switch), never uploaded from a shop
  phone. UNSURE (❓ `doubtful`) app debit = `excluded` + doubt `wording` (not counted, not on the Money screen until the
  bank SMS or the person settles it), an ASKODOX notification AT ONCE ("check once"), after the 60 s wait the voice asks
  to check the bank balance (`unsure`) -- never "went out". SORRY: `setAsideOpposite` (bank SMS says the opposite within
  10 min) on a row already SPOKEN -> `saySorry` (`sorry_out` / `sorry_in` voice + notification, once). Voice kinds
  `check` / `sorry` have no switch yet (on). `recheckSummaries` sets aside rows an older build made from a summary (once).
  `accountTail` reads "HDFC Bank-1234". Parser gate 349 checks (made-up names; a real payer name was removed from the
  tests). Nothing phone verified.
- Branch `claude/free-shop-core-retention` (2026-11-23, owner "1+4 do" on the ProfitWell idea): (1) SHOP CORE FREE
  FOR EVER -- ONE list `shop_free_core.py` `FREE_FOREVER` (payment_voice, quick_bill, dues, sales_reports + the route
  patterns that ARE each tool, incl. `/api/in-app/voice/speak` where the phone fetches payment voice): `AiCredits`
  refuses a rate for them (400 `free_forever`), `reserve` answers free; `tests/test_shop_free_core.py` reads every
  such route handler and fails on a credits reserve / 402 / plan check; AI Credits console page shows the locked
  list; rule `.claude/rules/shop-free-core.md`. Nothing is shown to shops yet (where to say it = owner's decision).
  (4) SHOPS KEEP USING? -- `shop_retention.py` (roll-up `shop_activity_days`: a shop is active on an India day with
  a bill / payment / payment-voice event / day close / attendance / table order / purchase; MAX upserts, periodic job
  `shop_activity` 6 h + lazily on read, survives the 90-day event purge) + `GET /admin/cc/shop-retention`
  (analytics:view; shop names + the shop's counter number only with users:view, owner number masked) + console view
  `shopretention` "Shops వాడకం" (active 7 / 30, quiet, stopped, never used, week 1 / week 2 / month 2 kept -- None =
  too early, join-month table, 30-day trend, call lists). Backend 1882 pass. Not checked on production data.
- `main` PR #392 (2026-11-22, in Play bundle `askodox-play-1606.aab`, owner: PhonePe notification with the name came first but the
  voice had no name; the bank SMS came ~1 h later and was spoken AGAIN; SMS first + late notification also spoken
  twice): payer name now read from "NAME (id@ibl) sent you ₹X", "NAME sent you ₹X", title/text split (`payerOf`).
  The join decision moved to pure `PaymentAlertParser.pickSamePayment` (RRN 24 h; same payer handle / name 6 h;
  amount-only any order 2 h, was SMS 10 min after an app / app 60 min after an SMS; closest row wins; masked handles
  "*akar@ibl" now count; the shop's own id / e-mails are never the payer). `Sim()` scenarios of every reported case
  in `android/parser-tests`; the gate also runs on `AskodoxPaymentAlerts.kt`. New `.claude/rules/payment-alerts.md`
  + skill `.claude/skills/askodox-payment-alerts`. Nothing phone verified.
- `main` PR #394 (2026-11-23, Play bundle `askodox-play-1606.aab`, owner "Ok" on design artifact GyGuSkNsVrf6cxXQBZk7h4, PlayboxTV / Linktree idea):
  SHOP LINK -- one free public page per shop `askodox.com/s/<slug>` (`shop_links.py`: tables `shop_links` /
  `shop_link_aliases` (old names 301 -> new, printed posters keep working) / `shop_link_counts` (per day + kind, no
  customer identity); HTML `shop_link_pages.py`, NO script (CSP script-src 'none'; menu = plain GET form; call / UPI
  taps counted with `ping` -> `POST /s/{slug}/c/{kind}`); routes `routes/shop_links.py`: owner `GET|PUT
  /api/pos/businesses/{id}/link` (PUT owner ONLY; GET / check / stats need `reports`), public `/s/{slug}`,
  `/s/{slug}/order` (via=wa -> WhatsApp message page + app ask; via=app -> install steps, Play with
  `referrer=utm_source=shop_link&utm_campaign=<slug>`), `/s/{slug}/go/app|follow|join|map|chat` (counted 302).
  Menu = the front desk's `_menu`; pay = the owner's own default UPI (`payment_methods.pay_to`, no amount); offer /
  about refuse web links; paused / closed shops show but take no orders. Caddyfile `@askodox_shop_links path /s/*`.
  App: `/pos/:id/link` = `AskodoxShopLinkStepsScreen` (what to show -> colour + name checked live -> ✓ WhatsApp / copy /
  QR poster / open + 7-day counts), Seller Money page `s.link` (owner), biz page `customers.link`. Phase 2 (not built):
  app reads the install referrer + opens the shop, order tracking from the link, install counts, product photos.
  Fix (owner phone 2026-11-23, "WhatsApp number enduku?" with an EMPTY box): a shop from the short setup card has no
  phone -> GET returns `whatsapp_default` (shop phone, else the OWNER's own sign-in number, owner only), first save
  falls back the same way, the box explains where orders go. ORDERS INTO THE APP (owner "order ravataniki app vundhi"
  -> "into the app + WhatsApp backup"): the menu form POSTs `/s/{slug}/order`; via=shop = name + 10-digit phone (not
  OTP-checked, honeypot `website`, desk limit 3 running per phone, `MAX_LINK_ORDERS_PER_DAY` 150) -> `PosFrontDesk.place`
  as `weblink-<phone>` with source `shop_link` (added to `SOURCES`) -> the shop's Live orders (card tag 🔗); customer page
  `/s/{slug}/o/{token}` (`shop_link_orders`, meta refresh 20 s, cancel while placed, UPI with the bill amount once
  billed); via=wa = the old WhatsApp page, only when a WhatsApp number is set. Nothing phone verified.
- `main` PR #391 (2026-11-22, owner "1", owner test: 30-40 s before a spoken reply): SPEAK WHILE WRITING -- spoken turns
  (`askodoxSpeakTypedReplies` + `_streamSpeaks`) no longer hide the stream until the whole answer: `_liveFeed` queues each
  finished `askodoxSpeechChunks` part (last part only after `text_done` / the final), `_liveFetch` shares audio through
  `_earlyAudio` (first part's engine locks the rest), `_liveRun` plays + shows each part (`_streamingReply`); `_speakChunks(
  continueLive:)` waits for the part playing, then goes on from the first part not heard (`_liveHeard`; added words of the
  last heard part only; Stop / mute -> nothing more). Replay / resume never continue. Stream event `{"type":"text_done"}`
  (`_ReplyStream` -> `on_text.text_done`). ElevenLabs `DEFAULT_MODEL` eleven_v4_turbo, refused (400/404/422) -> eleven_v3
  once + 30 min rest (log `ASKODOX VOICE MODEL refused`). Routing JSON "reply" first; planner max_tokens 400; first Gemini
  photo read `thinking_budget=0` (next model keeps thinking). Registry `speak_while_writing`. Railway variable ELEVENLABS_TTS_MODEL
  OVERRIDES the code default (staged eleven_v4_turbo on 2026-11-22, a redeploy followed; the value is not readable --
  deploy log 2026-11-23: payment voice parts 413 ms / 790 ms uncached, was 5-13 s on eleven_v3). Nothing phone verified.
  ROUND 2 (PR "planner in parallel", owner "Ok go"): `_EarlyRoute` starts the routing call (fast model, no evidence) next
  to `_plan`; its reply waits in `_HeldText` until the planner says no search + not hard (then `take` releases it), else
  it is dropped (never shown) and routing runs again with grounding / the hard model. Never when `_needs_lookup` (the
  user's own words need live evidence) or the guide path. Timing log path `routed_early`.
- `main` PR #390 (2026-11-22, Play bundle `askodox-play-1603.aab`, owner: a JK-xxxxx-S "DEPOSIT SUCCESS ... A/c: <whole 10-digit number>
  Amount: Rs.8,551,00 Status: RECEIVED Open: bit.ly/.." SMS was said + counted as ₹8,55,100 received, "Bank SMS"):
  `PaymentAlertParser.fakeSigns` = public short link / broken comma groups (`wellGrouped`) / a whole account number
  after "A/c"; `looksFakeCredit` -> parse Ignored even over a confirmed wording (only "wrong -> came in" on it wins),
  `notice` = suspect (no amount when the amount is broken); phone `recheckFakes` turns rows an older build saved into
  ⚠️ info rows once per `FAKE_RULES`. Parser gate 278 checks, made-up numbers only. Nothing phone verified.
- `main` PR #389 (2026-11-22, Play bundle `askodox-play-1602.aab`, owner "సరే ఒకసారి ఇది చేయండి" on design artifact RGYB6de8vhoNeDwY3DBG9z
  page "3 స్టెప్స్"): SECOND PAGES IN 3 PIECES, JOBS IN 3 STEPS -- kit `lib/features/steps/presentation/step_kit.dart`
  (`AskodoxStepScaffold`: back = one step back, 1·2·3 bar, one big question, middle, `AskodoxStepBottom` = mic + ONE
  big button; ⋮ holds the rest; keypad / choice cards / ✓ / round actions) + pure rules `steps/domain/step_logic.dart`.
  Phase 1 replaces four routes, the old pages stay at `?full=1`: `/me/business/:id/bill` (`AskodoxBillStepsScreen`:
  item tiles tap = 1 / again = more / hold = weight, no items = amount pad -> cash / online / due (name + pay date) /
  part cash -> ✓ WhatsApp + print; mic = `askodoxParsePosOrder` fills tiles + `askodoxSpokenPayMethod` pre-selects,
  never bills by itself), `/biz/:id/money/dues` (`AskodoxDuesStepsScreen`: who -> keypad -> ✓ receipt; one payment
  over the bills oldest first = `billSettle(amountPaise:)`), `/biz/:id/staff/checkin` (`AskodoxCheckInStepsScreen`:
  round button from the caller's own day = attendance today `me` (new, owner included) -> phone lock / selfie -> ✓),
  `/pos/:id/day` (`AskodoxDayStepsScreen`: online right? -> drawer keypad, asks once (final) -> ✓ + WhatsApp).
  Next phases (not built): the other 13 work pages, 31 glance pages, 21 setting pages. Nothing phone verified.
- `main` PR #387 (2026-11-22, owner "Ok start work" on the Money / ☰ design artifact VJpPz7Ckp6yh7CiCZ4v3Zf): MONEY ON BOTH
  SIDES -- bottom bar Home · Live Work · Ask · Money · Buy|Sell (Seller said "Shop"; keys stay `askodoxNavPayments` Buyer /
  `askodoxNavShop` Seller), Money = shell branch 1 `/money-home` (`AskodoxMoneyHomeScreen`, `lib/features/money_home/`; old
  `/search` = top-level redirect); the switch stays on the tab in view. Buyer = own money card (this month on this phone ->
  `/money?owner=me&lock=1`) + pages; Seller = shop chooser (owner + staff shops, `askodoxMyShopsProvider`,
  `askodoxMoneyShopProvider`), today's sales / dues / new orders (-> `/money?owner=<id>&lock=1`), the shop's tools from
  `askodoxSellerPages` (role perms via `askodoxBizAllowed`, food-only tables / kitchen, Phase 1 `askodoxRouteShownNow`),
  first time = `AskodoxShopSetupCard` (name + state + kind template). Phone-style pages = `AskodoxLaunchLayout` (folders,
  move, hide never delete, fitTo adds new pages at the end, Reset), saved per side and PER SHOP (prefs
  `askodox.money.layout.v1.buyer|seller`, account-scoped); press and hold arranges, the card's place shows the arranging
  panel (the grid never moves under the finger). ☰ = `AskodoxMenuBox` dropping from the TOP (`showGeneralDialog`), per side:
  person card (`askodoxMenu-more`) or shop card + `askodoxMenu-mybusiness`, history / language (`askodoxApplyLanguage`, shared
  with the header chip) / location / notifications / AI Credits / settings / feedback / idea, company pages
  (`askodoxCompanyLinks`, askodox.com), Sign in / Logout. PAYMENT VOICE FOLDER (`payment_voice_sheet.dart`): 11 kinds on my
  phone, 4 on a shop counter; native `voiceOn` / `setVoiceKinds` / `voiceKinds` / `speakKind` (prefs
  `voice_kinds_personal|shop`), "fake" always on, "out" follows announce_debits unless chosen; paid bill / EMI speaks
  `billPaidParts`. Parser: cashback / interest landed = Accepted(bonus) (offers never), "cancelled" in reject, notices
  `cancelled` / `autopay` / `autopay_off` / `request` (`noticeParts`, `voiceKindOf`, never received words). Parser gate 256
  checks. Nothing phone verified. ROUND 2 (PR #388, owner "pages in a group don't move / any page as a Home chat
  shortcut / I am a businessman AND an employee / don't group anything"): shipped screens are FLAT (old app folders
  `askodoxRetiredFolderIds` dissolve on load, user folders `u*` stay); press-hold-release = page menu (pin above the Home
  chat via `askodoxOfferChatPin` -- the same 5 pins for everyone, id `money:<shop|me>:<page>`, route `pinRoute`; move; take
  out; hide), press-hold-move = arrange; an open folder = in-screen panel (`_folderPanel`, drag inside = `moveInFolder`,
  drag out = the panel fades + `_loosen`/`takeOut`). New routes `/payment-voice[?shop=]`, `/me/dues`; pins open tabs with
  `askodoxOpenPinRoute`; `/profile?view=settings`. Seller pages per shop = the person's side: `_SellerSpec.who`
  owner / self / staff / all + owner ticks (`tools`, else role perms); staff own month = `/biz/:id/staff/person/me`
  (read only).
- `main` PR #386 (2026-11-22, owner HDFC "Bill Paid!" SMS + "bill payment is a payment too, bill generated etc."):
  PAID BILLS ARE PAYMENTS -- `PaymentAlertParser.paidBill` (bill / premium / EMI / instalment / challan + "paid" /
  "payment successful", or "... paid / successful ... from your A/c XX1234" -> `Outgoing(bill, ownAccount)`, party via
  `billPayee`), `paidOut` ("Payment of ₹962 to X successful" = the PAYER's message; was read as IN), guards `billNotPaid` /
  `billToMe` / `stillDue` / `paidByOther`; `outgoingOrIgnored`: a strong debit word keeps a debit whatever it was FOR
  (`purposeWords` emi / loan / recharge / bill pay -- they were dropped; not when credited / disbursed / will be);
  `serviceAck` (boards naming SC / USC / consumer no, card issuers, insurers, lenders) never with `fromOther`;
  `dueReminder` ("ignore if already paid", 25-Nov-2026, the date after "due / pay by" wins, sender id -> company name).
  Phone: kind `billpay` = the bank's own "Bill Paid ... from your account" SMS (bank-confirmed, `SIDE_KINDS` with
  `biller`: joins the bank's debit SMS within 10 min + app message + company receipt into ONE row; same kind never
  joins); a bill that came = due row + an `info` bill note with `due_date` (`askodoxBillNote`). App:
  `askodoxDueSuggestions` skips a due already paid, `_powerBoard` (board initials -> Current). Parser gate = 201 checks
  with made-up numbers ONLY (public repo: never the owner's service numbers / account tail). Nothing phone verified.
- `main` PR #383 (2026-11-21, owner "6, 7 + design, then merge + aab"; Play bundle `askodox-play-1590.aab`, Live Build run 44932718383; server deploy SUCCESS) + round 2 (2026-11-22, owner "finish all": Buyer Money = `/me/payments?mine=1` (`mineOnly`: own phone only), Seller greeting, reply `switch_mode` -> chip `askodoxSwitchMode-*` (`switch_mode_offer`, `askodoxSetSellerMode`), `RESULT_CARD_RULES`; PR #384, Play bundle `askodox-play-1592.aab`) + round 3 (2026-11-22, owner "start": header chip `askodoxHeaderModeChip` inside the wordmark FittedBox, `GUIDE_FRIEND_RULES` in how-to answers, Meta Page login `routes/meta_oauth.py` `/meta/oauth/start|callback` from old PR #259 -- needs `META_APP_ID` / `META_APP_SECRET`, stores no token): BUY / SELL SWITCH --
  `askodoxSellerModeProvider` (false = Buyer; kept on the phone under `askodoxSellerModePrefsKey`), bottom bar = Home ·
  Live Work (`askodoxNavLiveWork`, `/work`) · Ask · Money (Buyer) / Shop (Seller, `/me/business`) · switch
  (`askodoxNavHistory`, where Tools was; Tools / settings open from the ☰ menu). "ASKODOX Club" and the header game pill
  are gone in Phase 1. Chat sends `buyer_mode` / `seller_mode` (`app_mode_rules`; seller also `shopping_tools`; no other
  shops' menus for an unnamed item in Seller mode). LIVE WORK DOT = `live_work_status.dart` (green blink = steps in the
  last 5 min, grey, red "!" after a failed reading); the shell reads the step counter once a minute only when a job is
  chosen and an earlier reading exists. BRAIN: `FRIEND_REASONING_RULES` (seven category-free ways: fit to their life,
  work backwards, another way, who really pays, turn it around, odd questions, the sum behind it; verdict first) after
  `DECISION_GUIDANCE_RULES` and in `_advise`; how-to guides keep `GUIDE_ANSWER_RULES`. RESULTS: asked-for sections
  (`requested_groups`) come third, after `local` + `affiliate`, unless staff fixed `section_order`. Guide step
  `_profile` now points at the header Menu. Nothing phone verified; no live before / after answer comparison.
- `main` PR #381 (2026-11-21, owner "2 voices + ElevenLabs not coming + Rs 3,000 minus"; server deploy f83c576 SUCCESS;
  Play bundle `askodox-play-1588.aab`, Live Build run 44913389941):
  ONE VOICE PER REPLY -- `/api/in-app/voice/speak` takes `engine` (''|elevenlabs|sarvam; elevenlabs waits 20 s and never
  answers with Sarvam), app `_speakChunks` locks the first part's engine (`askodoxAudioEngine` Expando on the bytes);
  log `ASKODOX VOICE SPEAK` (status / ms / locked / cache). Cause found in logs: eleven_v3 > 8 s on some parts -> that part
  Sarvam. ElevenLabs lines <= 160 chars kept on the volume `tts_cache/` (every phone, restarts). PAYMENT VOICE: parts
  fetched in parallel with engine=elevenlabs, 6.5 s budget (was 3.5 s serial -> phone voice), common amounts warmed.
  BANK SMS WINS (personal phone): `rejectView` ("sent/paid/credited to your" = incoming), doubtful debits (❓),
  `setAsideOpposite` / `bankSaysOpposite` (10 min, rows `excluded` + `doubt`), app debits wait 60 s (`spoken` waiting /
  skipped_bank), rows keep `raw_title` / `raw_text` (phone only, never uploaded), row sheet "తప్పు" -> `correctEvent`
  -> `learned_kinds` by `PaymentAlertParser.skeleton`. Totals / ledger skip `excluded`. BILLER ACKS ("Thank you for the
  payment of Rs 3081 for your Airtel number", AD-AIRTEL-S passes `isBankSender`) = Outgoing `biller` (kind "biller", joins
  the bank's debit SMS from the same SMS app) -- they were spoken as money RECEIVED. NOTICES: `PaymentAlertParser.notice`
  (refund_started / pending / failed / bill / suspect) -> `saveNotice` "info" rows (excluded, never spoken; suspect also
  notifies), app `askodoxNoticeNote`; "initiated / processing / will be credited" are in `reject`; a LANDED refund =
  Accepted(refund); TRAI `-P` sender ids ignored (`isPromoSender`). Nothing phone verified.
- `main` PR #375 (2026-11-21, owner "mothma finish, aab"): STUDIO STEP 1 -- a pasted store / Wishlink link in the search
  -> `AffiliateCatalog.find_by_link` (canonical key / product id, or the stored `affiliate_url` host + path) -> that LIVE item is
  the ONLY catalog card (`_marketplace_and_catalog` status `link_match`). Bottom-bar Shopping switch labelled "ASKODOX Club"
  (keys unchanged); staff form "🔗 For your reference". Owner rule: NO "Affiliate" words on product cards / `/p` / `/shop`
  (catalog `disclosure` = "" for products; partner campaigns + Sponsored keep labels); disclosure = footer "నిబంధనలు" link to
  askodox.com/affiliate-disclosure (`product_pages.TERMS_URL`). Share captions still carry #Affiliate (store rule).
  Follow-up PR: routing = `affiliate` whenever an `affiliate_url` exists and commission is not INACTIVE (UNKNOWN used to
  open the plain store link); `is_block_page_title` rows are ineligible (old "Access Denied" items); compare with one card
  on screen returns null in `askodoxAnswerFollowUp` -> normal search; deploy log `ASKODOX LINK MATCH`. Normal name searches
  stay as they are (owner: ours appears among the regular results).
  Staff "For your reference" form: AI video tick OFF by default (owner: video not needed now), Category / Brand / Sizes
  (-> `variants`) boxes filled from photos; catalog search also matches `description`.
  COLLECTION VIDEO (owner 2026-11-21, Meesho Magic Club style): `collection_video.py` + `POST /admin/cc/workspace/collections/
  ai-video` (2-5 LIVE items, any store; ASKODOX on top, `clean_theme` Latin-only title, per-item photos zoom + name + ₹ tag;
  fixed name+price voice via `product_video.synthesize`; reel `collection` ids; log `ASKODOX COLLECTION VIDEO`; shares the
  AI video daily cap). Share texts (single + collection) add `whatsapp` status; Meesho items -> `@meeshoapp` and NO buy link on
  WhatsApp (`MEESHO_WA_NOTE`: staff paste the Share & Earn link). Staff UI: My items "🎞️ Collection వీడియో".
  STUDIO round 1: `studio_store.py` (tables `studio_purchases` / `studio_accounts` / `studio_reminders`, paise, IST) +
  `routes/studio.py` (`/admin/cc/workspace/studio*`, staff own / publishers all) + staff tab "🎥 Studio" (home tiles,
  filters, buy form, stage / return / keep) + periodic job `studio_reminders` (30 min; log `ASKODOX STUDIO REMINDERS`).
  STUDIO round 2: `studio_video.py` (tips table by kind, `STORE_RULES` rows (Meesho; others `DEFAULT_RULES`), `checklist`,
  `script` = fixed intro / staff line / price line / fixed outro, `voice_files` cache table `studio_voice_cache` by exact text,
  `captions`, ffmpeg `render`: staff video 720x1280 + overlay PNG + voice + 2.5 s end card) + routes .../video (vertical
  <= 61 s, 80 MB), /edit (background, log `ASKODOX STUDIO EDIT`), /checks, /publish (422 names what is missing), /posted,
  staff-only /media/{raw|edited} (page fetches as blob), public `/media/studio/{32hex}.mp4` only after Publish. Columns
  added by `studio_store.MIGRATIONS`. Staff UI: "🎬 వీడియో" panel per Studio product. Nothing phone verified.
  STUDIO round 3: `studio_earnings` (one row per product + source + month, owner / publishers type it), `money()` (cost =
  kept + return fee + `voice_paise`; profit = confirmed - cost; best kinds; staff own only), `studio_unlocks` + `UNLOCKS`
  targets, Monday 10:00 IST commission push in `send_reminders`, setting `studio.voice_line_cost` (₹3); routes
  /studio/money, /studio/earnings, /studio/unlocks; UI "💰 లెక్కలు" / "🔓 Unlock". Studio spec 1-10 all built.
  NEXT (owner order): payment fix (PhonePe app row vs bank SMS: SMS wins, ❓ + 60 s wait, "wrong" button, raw
  message kept), product documents (PDF / images) + AI answers + consented callback to an executive.
- `main` PR #373 (2026-11-20, owner "Go"; Play bundle `askodox-play-1582.aab`, Live Build run 44748094784; server + website deploy SUCCESS, askodox.com/shop probe 200): AFFILIATE IN 4 STEPS -- Staff Workspace "🔗 Affiliate product" form (`affForm`): link is
  NEVER opened, store chosen from the link host, photos -> `POST /admin/cc/workspace/fill-from-photos`
  (`affiliate_publish.read_product_photos`, never a price) -> staff price -> Publish + AI video (`store` passed). The AI
  video also writes DM answers (`affiliate_publish.write_faq`, stored in `reel.faq` with `reel.reviews` / `reel.store`).
  Videos tab "📤 షేర్": `GET .../reels/{id}/share` = Facebook / Instagram / YouTube texts (+#Affiliate; Instagram + Shorts
  point to askodox.com/shop because their caption links are not clickable), DM answers, download (ACTIVE only), clicks.
  Public pages `routes/product_pages.py` (+ `services/product_pages.py`): `/p/{id}` (LIVE only, video / rating / points /
  FAQ, "Affiliate" label), `/p/{id}/buy?from=fb|ig|yt|wa|app|web` (counted in `product_page_clicks`, 302 to the commission
  link), `/shop`; proxied on askodox.com (`website/server/Caddyfile` `@askodox_picks`). Old "fetch the store page" form is
  under "పాత పద్ధతి". Log lines now print: `ASKODOX WORKSPACE PHONE_READ`, `ASKODOX WORKSPACE PHOTO_FILL`, `ASKODOX AI VIDEO`
  (app loggers at INFO never reached Railway). Nothing phone verified.
- `main` PR #371 (2026-11-20, owner "change the staff product way + videos, quick"; Play bundle `askodox-play-1581.aab`, Live Build run 44730164475; server deploy SUCCESS): Staff Workspace AI PRODUCT VIDEO --
  `product_video.py` (script from the item record + read reviews only via `write_text`; `clean_script` drops
  first-person use claims / review scenes without reviews; children never speak; ElevenLabs -> Sarvam -> captions only;
  presenter circle "AI ప్రజెంటర్" from `assets/presenters` (11 owner-made models) or the product talking; rating card +
  "కొన్నవాళ్లు ఏమన్నారు" card; end card) + routes `POST /admin/cc/workspace/reviews/read`, `POST .../items/{id}/ai-video`
  (store photos copied temporarily; DRAFT -> PENDING_REVIEW in 🎬 Videos tab; daily cap `video_ai.daily_max` 40;
  log line `ASKODOX AI VIDEO`). Staff page: review screenshots + "🎬 30 సెకన్ల AI వీడియో" tick on store-link and own
  forms, 🎬 AI వీడియో in My items, Videos tab shown. Also My phone payments: debit SMS rows lose the wrong ⏳ and
  categories match whole payee words only ("Messages" -> "mess" -> Food & hotel bug). Nothing phone verified.
- `main` PR #369 (2026-11-20, owner "Go -- finish all, one build"): PAYMENT VOICE STUCK FIX -- one clip that never finished kept
  every later payment on "Speaking..." (owner phone from 08:08): `Player` watchdog (length + 4 s) + audio focus + busy > 40 s
  restart, `Speaker` start-up 8 s / utterance 12 s limits, `CloudVoice.say` ONE answer in 45 s (else "stuck" + `beep()` on
  STREAM_ALARM), acks honest (`duplicate_local`, `stuck`, `detail` = vol / output / played_ms in the `ASKODOX PAYALERT ACK`
  line), phone rows "pending" > 2 min show "stuck"; staff phones join their shops by themselves at app start (`joinShop`,
  `askodoxJoinStaffShopVoices`); per-staff tools (`pos_members.tools`, `TOOL_PERMISSIONS`, permissions = role AND ticks;
  migration: older non-manager staff -> payment sound + one job screen; app mirror `pos_staff_tools.dart`); baaki reminders
  (`pos_dues_followup.reminders/set_date/mark_sent`, `/pos/:id/dues`, pay date default 7 days, 3 days before -> the date,
  once a day, owner push + WhatsApp text with pay link, quick bill date chips); item tiles = emoji from the name
  (`pos_item_icons.dart`) + menu number, number search / spoken "20 నంబర్ 2"; `PUT /online` saves at once (listings in a
  thread); POS network text never claims a kept bill + one silent retry for GET / PUT; `askodox_self.py` (sound-alikes ->
  ASKODOX in transcript + brain, facts from `chat_actions.CATALOG`, no live lookup); chat opens the named screen
  (`askodoxAutoOpenAppActions`, capability `auto_open`, `/my-shop/sale?say=`); first open asks location once
  (`LocationController.askOnStart`); Play builds declare REQUEST_IGNORE_BATTERY_OPTIMIZATIONS (one-tap dialog). Nothing
  phone verified.
- `main` PR #367 (2026-11-20, owner "pending andhuku chayaledu"; Play bundle `askodox-play-1577.aab`, Live Build run 44652076812): My phone
  payments = four tiles (History / Apps / Accounts / Language-voice, `askodoxMineTile-*`, one part open at a time; `askodoxMineMore` still
  shows when none is open); quick bill = sticky bottom bar (Total + QR + Make bill, `askodoxQuickBillSticky*`) and "Both" is the fourth pay
  button (`askodoxQuickBillSplit`). Nothing phone verified.
- `main` PR #364 + #366 (2026-11-20, owner "finish everything" / "Go"): packet photo -> new-item form (`pos_bill_photo.read_product`,
  `/products/photo`); counter offers per item (`pos_products.offer` bxgy / percent) and COMBOS (`pos_businesses.combos`, `/combos`,
  `pos_combo_sheet.dart`): `PosStore.offer_discount` / `combo_shares` == app `askodoxOfferDiscount` / `askodoxComboShares` (keep equal),
  applied as LINE DISCOUNTS by the sale screen (`_applyOffers`) and by `PosRestaurant.bill` via `order_discounts` (table / parcel /
  delivery orders); no stacking (combo share wins); pre-order on a reserved table (`reservation_id` in desk `place`); shop people get
  a "Running orders (n)" chip; attendance action `half`, a day under half the shift = half, shop holidays (`pos_att_holidays`, paid
  for monthly salary) + `pos_staff_bonus`; payalert FCM data ttl 1800 s. NOT built: automatic calls / WhatsApp for baaki, Bill page
  redesign, tiles on My phone payments. Nothing phone verified.
- `main` PR #361 + #362 (2026-11-20, owner "start"; Play bundle from Live Build run 44589361201): pins = 5, movable, any header-menu
  page (`chat_pins.dart`); every shop tool by talking / pin via `/my-shop/<tool>` (`pos_shop_tool_screen.dart`, chat rows `shop_*` in
  PHASE1_KEYS); chat shop menu = asked items (`focus`), three ways always, compact - n +; reply words appear WITH the voice in the real
  app (`askodoxSpeakTypedReplies`); payment alerts: a staff member never sees other staff, staff payments default to the owner only,
  `ASKODOX PUSH DATA` / `ASKODOX PAYALERT ACK` lines in the deploy log; running order / reserved table chip above the chat
  (`askodoxLiveOrdersProvider`, on only in `main()`); supplier bill photo (`pos_bill_photo.py`, `/purchases/photo` + `/from-photo`, review
  screen pushed from the purchase page -- no router path); baaki follow-up job (`pos_dues_followup.py`, customer "I will pay on" in My
  bills, in-app pushes only); daily expiry push (`expiring_soon_all`); table reservation (`pos_reservations.py`, 90 min slot, 15 min hold,
  sheets in `pos_reservation_sheets.dart`). Staff attendance + salary already existed (`pos_attendance.py`). Nothing phone verified.
- `main` PR #351-#359 (2026-11-19, owner "1"; Play bundle `askodox-play-1567.aab`, Live Build run 44560273135): QR poster, ASKODOX
  Shopping bottom-bar switch (green / grey; `shopping_mode` + `shopping_tools` capabilities add pos_bill / crm / my_bills / money /
  payments to the Phase 1 chat catalogue), tile drag + pin button on shop tiles (existing `chat_pins.dart`), live barcode scan
  (`camera_android` pinned; camera features optional), money answers from the phone's own records, sign-in = Firebase SMS first
  (`_firebaseWhenServerSilent`, server/WhatsApp failure -> Firebase at once; verify errors report plugin-code), every reply text + voice
  (`askodoxSpeakTypedReplies`, set in `main()`; Mute is the only off), no `[S#]` markers / sources list in replies
  (`live_lookup.strip_source_markers`, app `askodoxWithoutSources`), no empty bill card. Nothing phone verified.
- `main` PR #337 (2026-11-17, owner "1"): payment voice -- the FIRST message (bank SMS or app notification) speaks at once
  (no wait for a name); the other joins silently (`PaymentAlertParser.samePaymentWindow`: same UPI ref, or same amount from a
  kind the row lacks -- app up to 60 min after the SMS, SMS within 10 min of the app, two apps 30 min; different payer handles
  never join; two SMS never join). Registered sender (`isBankSender`, XX-NAME[-S/-T/-G]) = `bank_confirmed` on the phone row
  (history "✅ బ్యాంక్ SMS నిర్ధారించింది"). Server still `notification_unverified`. Not phone verified.
- `main` PR #336 (2026-11-16, owner "1"): one catalogue, three roles -- `pos_bills.py` (item numbers `pos_products.item_no`,
  pay app `pos_payments.app`, send bill to a typed number: ASKODOX user -> "My bills" `/me/bills` + push, else WhatsApp +
  public page `/b/{token}`; settle later = `bill_settle` payment row; history `/bills/:id`); parcel / delivery app orders billed
  unpaid on accept; menu photo = one fast Gemini call per photo in parallel (phone waits 90 s); payment double sound fixed on
  the notification's own time (> 2 min late = saved, not spoken); chat `shop_menu` card (named shop -> menu, quick order);
  order code QR scan + shop-name search; table requests `pos_desk_requests.py` (water / gravy / onions / bill / call waiter,
  shop's own list, waiter banner on the desk) + per-item notes. Nothing phone verified.
- `main` `be27836` (2026-11-16): #331 / #332 / #333 / #334 merged (production deploy of `91c07d2` = #333 SUCCESS). Front desk
  (`pos_frontdesk.py`, `/desk/:id`, `/order-desk`), spoken menu, real quick bill, business name rule, speak-to-fill mic
  (`AskodoxFillBar` + `POST /api/pos/form-fill`, on quick bill / menu / shop setup), My phone payments = one "Turn all on" card +
  "More settings", talk mode ends by voice level (`voice_endpointing.dart` speech peak) + silence 1.8 s + capability
  `talk_brief` (2 short sentences) + timing line in the talk overlay + `in_app_voice_speak` log. Play bundle from Live Build
  run 43771803509 (include_payment_alerts). Nothing phone verified.
- `main` `8b5ec95` (2026-11-12, server deployed SUCCESS on Railway): payment alerts round -- #315 CI pins Flutter 3.47.9
  (stable 3.50.0 broke analyze + AGP); #316 parser reads PhonePe "X sent ₹N to you"; #317 one-question setup card
  (`domain/payment_alert_setup.dart`, payment-app notifications + battery, Samsung wording) + `razorpay_signup_url`
  (env `ASKODOX_RAZORPAY_PARTNER_URL`, NOT set yet); #319 sender share (`/payment-alerts/share`), listener mute/pause
  (`/payment-alerts/listening`), `pos_members.label` spoken, server `phrases`, phone-learned wording. Play bundle
  `askodox-play-1464.aab` (run 43151344437) built, NOT yet uploaded. `otp-autofill-e2e` "no Android consent prompt" is
  a known flaky emulator failure (rerun). Nothing phone verified.
- `main` `700833e` (2026-11-12): #313 onboarding header shows the ASKODOX logo (`AskodoxLogo`) instead of the robot
  mascot; payment alerts status card explanation shortened (keys unchanged). Play bundle `askodox-play-1458.aab` built
  from the branch (Live Build run 43042339260, payment alerts listener ON) -- NOT yet uploaded to Play. Not phone verified.
- `main` `de1fa3c` (2026-11-09, owner "1"): #292 Work Mode walking game (`/work`, steps -> a real job in half
  its real time, task sizes 10/50/100, schedule, waiting scenes, hotel, day replay; native `stepCount` on
  `com.askodox.app/hardware`, ACTIVITY_RECOGNITION; on-phone only) + #294 Talk (`/talk`, anonymous topic rooms,
  `talk_moderation.py` masks words in any language, 18+, voice listen = one `voice` credit, self-harm -> support
  text) + Radio town news (`POST /api/radio/town`, one `radio` credit, still behind `radio.enabled`, OFF in
  production) + game / talk / radio buttons replace the header wordmark (`askodox_hub_icons.dart`). Talk report
  review = API only (`/admin/cc/talk/reports`), no console view yet. Nothing phone verified. Production deploy of
  `de1fa3c` NOT yet probe-verified.
- Earlier `main` `89b51eb` (2026-11-04, production deployed): #270 reply prices = card prices (APK `android-1408`); `1e4531e`: #269 reels play (CSP media-src blob:); #268 Staff Workspace Reels tab (play / approve,
  no browser dialogs); #267 Own / Brand products, store links = store data only, WebView camera / gallery (APK
  `android-1406`). Before: `9c68fc3`: #265 Phase 1 hiding
  (`askodox_release_phase.dart`), #266 centre "Ask" (one tap = voice, no companion ring), Screen Guide in the header
  Menu, AI Credits packs only when on sale, Travel Radio on AI Credits (no pass list), Staff Workspace link read by the
  PHONE (JS channel `AskodoxPageReader`) + short form. APK `android-1404` (prerelease, not on the update channel).
  Nothing phone verified. Flag `radio.enabled` still off in production (owner flips it in the console).
- `main` (2026-10-24): master command rounds 1-4 + Universal POS merged in order #220 (Smart Tools, vision inspection),
  #221 (income tax / GST / fraud / smart tricks), #222 (BLE devices, push-to-talk), #223 (photo measurement), #224 (POS
  core), #225 (restaurant tables / KOT / kitchen, held bills), POS round 3 PR (barcode from a camera photo, BLE scale reading,
  invoice PDF + native `shareFile`, suppliers / purchase bills / supplier ledger, batch + expiry FEFO, valuation, input
  tax as recorded), POS round 4 PR #227 (box <-> pieces packs, serial / IMEI, purchase orders, Classic Bluetooth + USB
  printers via `AskodoxHardware.kt` on channel `com.askodox.app/hardware`, Telugu PDF text as images, Smart Tools
  protractor / magnifier / light / sound meters / vehicle walk-around report), then #228 shop advance, #229 guide on every screen + POS online channel, #230 ready catalogue + item
  details, #231 guide offers help by itself + picture tiles + rates by quantity + spoken multi-item bill, #232 self-shopping,
  #233 guide speaks + answers, examples / pre-fill, History backup, #234 Profile tabs + search, #235 profile editor
  (mini boxes), then the new logo / app icon + Command Center heading -> category -> page grid, then #237 POS payment voice
  alerts (2026-10-26; Razorpay bank-confirmed voice with the app closed PHONE VERIFIED on APK 1374), #238 FCM speak service,
  #239 own payment methods + POS collect + "Know this first" + LIVE order checkout refused + one mixed-language console,
  #240 UPI QR photo reader (PHONE VERIFIED on 1379, PhonePe dark QR), #241 AI Credits (TEST, charging OFF), #242 collect
  safety (bank-check confirm, undo 15 min, customer pay link `/pay/upi/{id}`), #244 AI usage metering
  (`ai_usage_meter.py`, one httpx hook, counts only) -- production `d3d4df4` (2026-10-27). Then #253 (2026-10-29,
  production `24cc48b`, probe-verified): live lookup + honesty guard (`live_lookup.py`), reply follows input (voice
  only for voice turns), Test Mode Diagnostics, knowledge gaps + owner alerts, availability watches, staff AI
  description + link batches. Brave was out of credit (402) on 2026-10-29 -> Serper primary PR. Status matrices: docs/MASTER_COMMAND_STATUS.md, docs/POS_STATUS.md. Production verified by a
  throwaway probe workflow (curl /health commit). Nothing phone / hardware verified.
  Before: `604d8ff` -- PR #213 (2026-10-17): Firebase OTP on APK 1336 failed ("network-request-failed" /
  "unknown [Software caused connection abort]"): MainActivity had `taskAffinity=""`, so Firebase's singleTask
  RecaptchaActivity opened in a separate task and after the reCAPTCHA browser step ASKODOX stayed in the background
  (emulator repro: browser stays in front on 1336, MainActivity resumes after the fix). Removed it (guard test
  `test_android_manifest_firebase.py`); network-class Firebase failures named; sign-in trail -> POST
  `/onboarding/diagnostics/trace` -> Railway log `signin.trace` (no numbers / codes / tokens).
  Before: PR #211 (`e96b4c4`): APK 1335 white screen = shared_preferences_android 2.5.0 (Pigeon JNI); pinned 2.4.28 in
  `dependency_overrides` (no pubspec.lock -- deps float); `askodoxStartupPrefs` (8 s -> "Try again"); publish
  workflow runs an emulator startup gate (one bash script: the emulator runner splits script lines).
  Earlier: #205-#210 auth / Firebase SMS OTP / re-login (APK 1331-1335). Firebase project askodox-81252.
  See docs/auth-and-push.md, docs/implementation-status.md, docs/resume-instructions.md, docs/payments-setup.md.
- Dev branch `claude/friendly-ramanujan-538sbj` (NOT merged, NOT in
  production, staging only) carries the post-1313 master round: voice one-audio
  lifecycle + pause / resume / mute / replay; message copy / select / share;
  Result Board mega expand with per-category navigation + provider-failure
  notice; reply meaning colours; profile memory; My Roles / My Business
  sections (promotions, automation, creations); API Health & Billing; Admin AI
  incidents + action framework; strict release gate. Every new flow is CODE
  READY only -- no real-phone verification yet.
- Railway: production env → podx-ai-connect from `main` (`podx-ai-connect-production-3279.up.railway.app`, also
  served at `admin.askodox.com` -- same service, verified 2026-10-27; console at `/admin/console`); staging env →
  `staging.askodox.com` from `claude/friendly-ramanujan-538sbj` with its OWN
  variables + volume; askodox.com → askodox-website (root `/website`), deploying from `main`
  since 2026-10-04 (the old `claude/askodox-website` branch is retired).
- Android Live Build #253 on `c2ae7d4`: PASS, in-app update published.
  Real phone: current place named "Uyyuru" (location naming verified).
- Sprint status: NOT complete. NOT yet verified: real Brave/Maps/Routes/
  Geocoding results in production (the cloud dev container cannot reach
  Brave, Railway or OSM tiles) and real-phone acceptance for every flow
  (TV, chicken "yes" = order, car Maruti→Tata, AC nearby, job openings,
  multi-category, location allow/deny/change, silent notifications + tap
  deep-link, privacy export/delete, Telugu voice).
- Master Fix Ticket engines are all BUILT at least partially (advisory,
  map pins/route quote, roles, refer→register, offers, attribution/
  rewards, subscriptions, catalog AI, domain adapters, cost control,
  Admin tabs). Still partial: see "Known open issues".
- The identity-spoofing audit (started before round 10) is CLOSED.
- Roadmap (14 points, phased delivery): https://claude.ai/artifact/TWUnjbA2TTubwczT9Lxg4n
  — Phase 0–1 done, Phase 2 round 1 (seller tiers) done, rest of Phase 2 and
  Phases 3–9 open.
- Always confirm this checkpoint against `git fetch origin main` before
  relying on it — this line is updated after each merge, but git is truth.

## Non-negotiable process rules
- The product owner has **no shell/terminal access**. Every code change is
  delivered as a single plain-text instruction file with clearly labeled
  file boundaries (a start-of-file marker naming the path and whether it's
  new or a replacement, the file's content, an end-of-file marker, and a
  final marker after the last file) that the paste-based delivery method
  expects. Files over ~50k characters must be saved to disk and read from
  there, not pasted into chat. (The exact marker text is intentionally not
  reproduced here, so this file can never be mistaken for one.)
- **Never trust a "merged"/"done" claim at face value.** Independently
  verify with `git fetch origin main` and diff the actual committed file
  content before reporting anything as confirmed.
- Before calling a change done: run the backend suite (`pip install -r
  backend/requirements.txt`, tests under `backend/tests/`) and, for Flutter
  changes, `flutter analyze` + `flutter test`.
- Every change follows `docs/UNIVERSAL_DEVELOPMENT_RULE.md` (universal-first,
  no category-specific fixes, cross-category tests; each PR reports universal
  applicability, extension points, cross-category tests, regressions prevented,
  justified exceptions and limitations).
- Approved features are locked in `docs/approved_features.json` (routes,
  response keys, widget keys, symbols, flag defaults, acceptance tests). The
  `Feature Registry gate` workflow fails a PR that loses any of them or deletes
  an entry; removal = status `deprecated` + owner approval + migration. Add a
  registry entry with every new approved feature.
- Update this file after each round that actually merges — edit it in
  place to reflect the new checkpoint; don't append another history section
  here (that's what the tracker is for).

## Architecture gotchas (expensive to relearn — read before touching)
- `/deals` and its sibling routes (`app/api/routes/universal_deals.py`) are
  mounted **only in `backend/server.py`**, not in `app.api.app_factory.
  create_app()` alone. A script/test importing `create_app()` directly
  will 404 on `/deals`. `server.py` is what production actually runs.
- Auth pattern used everywhere a caller's identity matters:
  `_authenticated_app_user(request)` (401 on missing/invalid/expired
  token) + `_matching_app_user(claimed, authenticated)` (403 on mismatch;
  keeps a legacy client-supplied id field for compatibility without
  trusting it alone). Tokens: `app/services/session_tokens.py`
  (HMAC-signed, dependency-free).
- `in_app_deal.py` is mounted at `/debug` but is a **real, live feature**
  (deal chat), not a debug endpoint. `debug.py` itself now only has two
  genuinely-diagnostic endpoints (`/debug/whatsapp-diagnostics`,
  `/debug/voice-readiness`) plus `_prepare_askodox_app_identity`, which
  `universal_deals.py` depends on directly.
- `ConversationOSRuntimeService` builds an internal LLM-routing prompt
  prefixed `"OASAT domain="`. Anything reading raw conversation text
  (like `UniversalCorrectionService.detect()`) must ignore messages
  starting with that prefix — it's machine-generated, never a real user
  reply.
- A backend route's auth requirement changing does **not** guarantee every
  Flutter caller was updated — this caused a real production outage once
  (round 13 → round 14 hotfix). Grep the whole Flutter app for every
  caller of a route whenever its auth changes.
- Backend tests that only hit `/deals/discover` with the user's words in
  `raw_text` do NOT reproduce the phone: replay the app's real payload
  (rewritten raw_text + `trace.query`) on `POST /deals` + `/matches`.
- Video Study: only `/api/videos/{id}/study|ask|market` + the attachment
  path; never study search results automatically (cost). Answers must cite
  the stored study (fact keys / timestamps) or say "not in this video".
- Main Chat layout: the latest results turn (`_pinnedResultsTurn`) renders
  ONCE in `_resultContext` above the chat list (bounded height, foldable);
  `_chat` skips that turn's results. Don't render it in the list again.
- Main Chat (`askodox_primary_home_screen.dart`) is the primary journey:
  results are embedded per assistant turn (`chat_result_policy.dart` decides
  card actions: Party B → `acceptMatch`, numeric listing → order request,
  online/video → link only). Don't build a separate results page.
- `UniversalDealController.answer()` fills the field an answer *describes*
  (with positional fallback); short detail answers bypass the AI rewrite
  (`AskodoxHomeRequestRouting.isShortDetailAnswer`) so they can't restart the
  active deal. Keep both when touching follow-up handling.
- Main Chat voice = native `MediaRecorder` (`startVoiceRecording` on the
  `com.askodox.app/device` channel) → `POST /api/in-app/voice/transcribe`
  (Sarvam-first). Never reintroduce the `RecognizerIntent` fallback there.
- No Android SDK in the cloud dev container: Kotlin changes compile only in
  CI (`Android APK CI` / `Android Live Build`).
- `android/app/src/main/kotlin/.../MainActivity.kt` is the ONE native
  bridge. The Live Build / Flutter CI scripts (`tool/apply_android_*.sh`)
  used to overwrite it with older heredoc copies (so the phone APK lacked
  Geocoder naming + notifications); they must never write it again. CI
  greps guard reverseGeocode/showNotification/speechRange.
- Chat and card actions share ONE executor
  (`lib/features/home/application/match_action_executor.dart`): a typed
  "yes / order it / book it" must keep calling it, never answer with text.
  Supply roles (seller/provider/worker) come only from the user's own words
  (`askodoxContextRole`), never from a guessed deal intent.
- Discovery is India-first (`ASKODOX_SEARCH_COUNTRY`, default IN): Brave
  `country`, Places `regionCode`, `region_mismatch` + `classify_page`
  filters. Snippet prices are `price_verified=false`. Identical Brave/
  Places/Geocoding calls go through `external_call_budget` (cache + usage).
  `/deals/discover`, `/api/discover/place|places|route` are public and
  rate-limited per client (`rate_limit.py`); `/deals/leads` needs sign-in.
- Growth engines live in ONE repository (`growth_repository.py`, tables
  `growth_*`) + `routes/growth.py` (customer `/api/...`, admin
  `/admin/cc/growth/...`, permissions `growth:view|manage`). Offers are
  rule rows evaluated by `offers_engine.py` (never hard-coded promotions);
  rewards accrue only on customer-confirmed completion and need admin
  APPROVED -> PAID. Paid plans stay PENDING_PAYMENT (no gateway).
- Affiliate / Partner Hub + Revenue Center live in `partner_revenue_repository.py`
  (tables `partners`, `partner_secrets`, `revenue_events`,
  `partner_conversions`, `revenue_entries`), `affiliate_partner_service.py`,
  `revenue_center_service.py` and `routes/partners.py` (admin
  `/admin/cc/partners|revenue`, permissions `partners:*`, `revenue:*`).
  Partner rows join `_discover` AFTER local + online (segment `partner`);
  opens go through `/go/{click_id}` (only URLs stored with an impression);
  conversions come only from token-verified postbacks or CSV imports.
  Secrets are never returned by any API. Revenue = confirmed + paid
  commission + recorded entries; "why" findings are rule-based and graded
  CONFIRMED / POSSIBLE_CORRELATION / INSUFFICIENT_EVIDENCE.
- Offers & rewards (benefits): `benefits_repository.py` (tables `benefit_*`),
  `benefits_engine.py`, `routes/benefits.py`; results carry `benefits`
  (verified campaigns only: external types need source_url + verified_at);
  claims idempotent per (campaign, user, trigger); Scratch & Reveal is
  server-decided (highest-priority live campaign) once per completed order.
  Distinct from the older seller/admin promotions in `offers_engine.py`.
- Chat attachments: ONE endpoint `POST /api/attachments/analyze` (MIME ->
  image / video / document processor, facts via `attachment_facts.py`);
  the chat keeps real bytes (`ChatAttachment`), pickers are injectable
  (`askodoxMediaPickerProvider`); facts go in `ConversationTurnRecord.context`,
  never in the shown text.
- Chat photo studio (owner 2026-11-07, for ALL signed-in users): the photo-analysis prompt returns
  `image_request` EDIT|CREATE|NONE from the customer's own words; EDIT/CREATE -> `_imageStudioTurn` ->
  `POST /api/images/edit` (`routes/image_studio.py`) -> `container.openai_image_service` (`openai_image_service.py`,
  env `OPENAI_API_KEY` + `OPENAI_IMAGE_MODEL`, default `gpt-image-2.5-sunburst` -- `gpt-image-2.5` alone is NOT a model id;
  edits send `image[]` per photo, size `auto` keeps the photo's shape). Failures log `image_studio.failed` with OpenAI's own code.
  Guards: rate limit + one AI Credits `image` use (released on failure). Pay as you go: AI Credits charging ON
  with an `image` rate -> no daily cap (credits decide); charging OFF -> free, capped per user per day by
  `image_edit.daily_per_user` (default 5; 0 = off in both modes; table `image_studio_uses`). Never a placeholder picture. Staff
  variant: `/admin/cc/workspace/image-edit`. Generated pictures live only in memory (`_sentImages['gen_*']`).
- Work Mode scenes = ONE painter (`work_mode/presentation/work_scene.dart`, `AskodoxWorkScenePainter`) drawn in a
  250-unit-high space (canvas scaled to the real height, `_s` = 1, `_w` = logical width); every motion period must
  divide 60 s (the clock loops every minute). Jobs live in `askodoxWorkJobs` (stage days must sum to realDays / 2).
  Team = `AskodoxWorkCrewMember` list (each member moved by their own steps); solo shows only the person. No
  points / rewards / money anywhere in Work Mode (owner rule).
- Customer shell (`app_shell.dart`): Home · Live Work · centre "Ask" (one tap = voice via the hub action
  `voice`; NO companion ring -- attachments live on the composer "+") · Money · కొను / అమ్ము switch (each half opens its
  side page, branch 2 `/mode`; Money holds money pages only). No drawer.
  One place per function: request status lives in Updates
  (`features/notifications`); old mock alerts/communication/preferences
  routes only redirect. Don't re-add duplicate entry points.
- Acting (send request / contact) needs identity; the executor returns
  `needsSignIn` and the UI offers `/onboarding?signin=1` (real OTP), then
  retries the same action. `/auth/login` redirects there.
- Location: no built-in city anywhere (`LocationState.hasPlace`); follows
  the phone only while allowed + foreground (`watchPosition`, 300 m) and
  never overrides a hand-picked place (`followsDevice`).
- Nearby (Places) needs a real place: no location -> source status
  `needs_location`, never a country-wide query. Places/web rows in another
  country are filtered (`place_region_mismatch`, `region_mismatch`).
- Account deletion revokes earlier tokens via
  `session_tokens.set_revocation_check` (table `account_deletions`).
- ASKODOX's OWN YouTube channel = `youtube_channel.py` + `routes/youtube_oauth.py` (ONE channel, row id 1; scopes
  youtube.upload + youtube.readonly only; one-time 10-min connect link made by a publisher; refresh token encrypted with
  `secret_box`, never returned / logged; upload once per `ref` `studio:<id>`, default privacy private -- YouTube locks
  uploads private until the Cloud project passes its API audit). Env `YOUTUBE_OAUTH_CLIENT_ID` / `_SECRET`
  (`env_value` provider `youtube_oauth`). Never connect a customer's / shop's YouTube account through it.
  WhatsApp webhook verify token has NO built-in value: `WHATSAPP_WEBHOOK_VERIFY_TOKEN` unset = verification refused.
  Meta login: `/meta/oauth/start?dm=1` adds the messaging scopes (App Review demo); the default keeps five scopes.
- Deployment keys: read through `commerce_finance.env_value` / `youtube_api_key`
  (aliases in `ENV_ALIASES`), never `os.getenv` directly in a new caller.
- #128's campaigns live in `social_sponsored_campaigns`; `sponsored_campaigns`
  belongs to `sponsored_repository.py` (rename migration in both).
- Affiliate Product Manager: `affiliate_catalog.py` + `routes/affiliate_catalog.py`
  on #127's `affiliate_products` table (columns added by migration; history in
  `affiliate_product_history`, health in `affiliate_source_health`). Eligibility
  and affiliate/organic routing are computed on read (never stored); source
  settings live in the #113 `affiliate_providers` registry via `save_source`
  (merge, never overwrite). Permissions `affiliate_products:*` (stock /
  commission / links are separate grants); console views `affproducts` /
  `affsources`. Catalog rows are `source: online` + `origin: affiliate_catalog`.
- Marketplaces (Amazon.in / Flipkart / Meesho) come from ONE site-restricted
  Brave query after local + online (`_marketplace_and_catalog`), never for
  services, fresh food or used. `classify_page` treats a store host's catalogue
  page as a store BEFORE the article regex ("Best Prices" used to drop them).
- Universal Advisor = ONE engine (`advisor_engine.py`) configured by schema
  resources `advisor_categories` (aliases, broad aliases, required /
  optional decision fields), `advisor_questions` (generic per-field wording,
  category overrides; keyword questions only when NO category matches) and
  `advisor_rules`; defaults in `advisor_defaults.py`, seeded once by
  `platform()` (v2 archives untouched v1 keyword seeds). Category = AI
  category (ignored when it just echoes the subject) -> head noun -> alias;
  a broad AI group yields to a same-group head noun. Each field has its own
  state (known / no_preference / unknown); "any" settles only the field just
  asked. A REQUIRED unanswered question holds final results in the app
  (`askodoxAdvisorHolds`) unless "show me". A question counts as asked
(`_lastAskedQuestion`) only if the reply showed it. Flag `advisor.enabled`.
- Demand Intelligence reads `pf_events` (`search` carries `local` + budget
  band; `request` / `seller_accept` / `order` / `order_completed` via
  `journey_event`). Rules = `demand_alert_rules`; matching reuses
  `app_demand_broadcast.candidate_providers`; every alert is logged with
  reasons in `demand_alerts` (cooldown + per-seller daily max, across rules).
  Sellers read `/api/opportunities`. Flag `demand.alerts`. No cron: instant
  rules run at most every 10 min after new demand, digests via Run.
- Auto-responses: `auto_response.py` (approved FAQ only, hours, handoff,
  masked contacts) hooked into `/debug/deal-message`; sellers self-serve at
  `/api/business/auto-response`. Flag `autoresponse.enabled`.
- Bounded settings: `platform_settings` resource + `platform_settings.get`
  (e.g. `video_study.max_seconds`, 30 s cache). Contact masking: one helper
  `pii_mask.py`. Deep Video Study only for uploads and REGISTERED sellers'
  videos (`_registered_video`); external videos are playback only.
- A local server uses `PODX_DATABASE_PATH` (not DATABASE_PATH).
- Web search (`brave_web_search_provider.py`): per-thread `last_error`
  (discovery runs sources in a thread pool), pacing learned from the
  X-RateLimit headers, a breaker for quota/auth errors, and `LastGoodStore`
  (`search_last_good`) serving the last good answer (rows carry `stale`,
  `cached_at`, `price_verified=false`). Never fabricate rows on failure.
- App flags: `lib/core/flags/askodox_remote_flags.dart` reads `/api/flags`
  (role / category / stable install id for %), caches 10 min + on disk, and
  keeps defaults (all on) when the fetch fails. Read a flag with
  `askodoxFlagProvider('key')`; never block UI on the fetch.
- New seller listings go through `listing_quality.check`: prohibited terms /
  flooding -> 422; contact details / links / one number across accounts ->
  held (inactive) + a `listing_reviews` record that staff approve / reject.
- The real-phone acceptance checklist is seeded into `qa_checks` as CODE
  READY (`owner_os.ACCEPTANCE_CHECKS`); only a real phone test with evidence
  moves an item to PHONE VERIFIED.
- Universal Sources (`universal_sources.py`, schema resource `sources`):
  connectors manual / feed (synced INTO `affiliate_products`, searchable
  without web search) / json_search (live, isolated, `source_health`) /
  site_search (joins the marketplace Brave query) / api. Add sources in the
  Command Center -- never per-source code. `results.sources` flag.
- `affiliate_products` is the ONE item store for staff-curated things:
  `item_type` (product/offer/coupon/service/link/news/video/content),
  `review_status` (DRAFT/NEEDS_REVIEW/APPROVED/LIVE/PAUSED/EXPIRED; rows from
  before = LIVE), `canonical_key` (duplicate detection). Only LIVE shopping
  types reach results. Health toggles: `catalog.*` platform settings.
- Staff Workspace: page `/staff` + API `routes/staff_workspace.py`, same
  permissions as the Command Center. Staff sign in with their OWN linked
  number (staff PATCH `phone`; OTP -> `/api/staff/session` -> 12 h
  `x-askodox-staff-session`, re-checked every request) or an `stf_` token.
  App: Profile "Staff Workspace" + Android Share -> one-time handoff code.
  `workspace:approve` = may publish directly; others submit for review.
- Early Access (`early_access` resource) + `/api/feedback` (masked by
  `pii_mask.mask_sensitive`; diagnostics only with consent) + client errors;
  dashboard `/admin/cc/early-access/dashboard`. Enum options in schema
  resources must be lowercase (values are lower-cased on save).
- Result Contract v2 (`result_orchestrator.py`): `/deals/discover` AND
  `/deals/{id}/matches` return `sections` (local, deals, online, affiliate,
  partner, content, videos, shorts, jobs, sponsored), `conversation_state`
  (explicit constraints EXACTLY as given), `answer.may_claim_results`, plus
  `matches` (kept for old APKs). Sources ADD sections, never replace; a
  failing source empties only its own (asked-for empty sections carry
  `empty_reason`). Order/limits = Command Center `result_orchestration`.
  The app orders rows by sections (no client re-sort) and reports drawn
  sections to `POST /api/results/rendered`; staff read
  `/admin/cc/results/diagnostics` (console "Result diagnostics").
  20 combinations: `tests/test_result_contract_combinations.py`
  (`result-contract-gate.yml`). `/matches` now carries the advisor too.
- Chat honesty (APK 1292): no reply claims "showing / finding / here are"
  unless cards render (`askodoxReplyClaimsResults`); a reply restating a
  different size is replaced (`askodoxReplyAltersSize`); "Any" settles only
  the asked field via `no_preference` (typed slots stay empty); the user's
  size is applied exactly (`askodoxExplicitSize`); a short reply to a
  finished request refines it; one no-results notice per request id.
- Public news/content = LIVE item-store rows of type news/content/video
  (`/api/content`, page `/content`, section `content`). Nearest junction:
  `/api/discover/junction` (Places, honest `unavailable`). Feeds sync on
  the background runner (`periodic_jobs` "feeds"), never in a search.
- Web search = `web_search_chain.py` (`container.web_search_chain`): Serper (`serper_web_search_provider.py`,
  `SERPER_API_KEY`, Google results, owner decision 2026-10-29) when configured, then Brave,
  then Google Programmable Search (`GOOGLE_CSE_API_KEY` + `GOOGLE_CSE_ID`,
  backend-only) ONLY when Brave fails (never on an honest empty answer); a
  stale Brave copy yields to a live fallback answer. `_web_search(container)`
  picks the chain; tests that replace `brave_web_search_provider` alone get
  that provider. `/health/search` shows `fallbacks`.
- Nearest junction: `is_junction` needs a transit/route type or a junction
  word in the place's own name with no business type ("Unacademy Centre" is
  a school). The app's map picker shows "Near X · N m", "Pin here", and adds
  ", near X" to the confirmed label (pickup / drop / location).
- Videos: `result_orchestrator.video_preference` puts Shorts or long videos
  first from the user's own words (`demand["said"]` = trace.query); rows are
  ranked by subject relevance; videos still only when asked / relevant.
- App results: `source == 'content'` rows form the "News" compare group.
- Mobility = `delivery_jobs.py` + `routes/delivery.py` (ONE system: rides,
  parcels, local / order delivery, carpool, reports). `REQUESTED/PARTNER_SEARCH`
  is never "confirmed"; trip steps forward-only (`allowed_step`);
  `PRIVATE_DETAIL_KEYS` + phones only to the requester / assigned partner after
  acceptance; fares only from `mobility_services` (ACTIVE row). Partners are
  `delivery_partners` (apply -> PENDING_REVIEW; staff approve / correction /
  disable). Order fulfilment responsibility: `fulfillment.py` (delivery state
  derived, separate from commerce state). Older WhatsApp ride stacks
  (`ride_repository`, `local_dispatch_*`) are legacy -- don't extend them.
- Native video: `routes/native_video.py` (upload metadata may come as query
  params -- the app's `ApiClient.upload` sends only the file). Unpublished
  media only to owner / staff. Video DMs answer from approved FAQ only.
- Integration states: `integration_readiness.runtime_rows` + public
  `/health/integrations` (no secrets). Firebase "configured" is never LIVE.
- NEW LOOK (owner 2026-11-27, whole app): ONE look = `lib/config/theme/askodox_look.dart` (`AskodoxLook` tokens,
  `askodoxLookTheme()`); `AppTheme.light` and `askodoxInnerTheme` both return it (`ThemeMode.light` stays; brightness
  is dark). The colours written on pages were converted value to value (light UI -> dark look) -- so a NEW page
  must not copy a light-UI colour: read the theme or `AskodoxLook` (`sheet` = what used to be white). Guard:
  `test/config/raw_colour_guard_test.dart` (a file may not gain `Color(0x..)` / `Colors.x`; lower its number in
  `test/fixtures/raw_colour_baseline.json` when you clean it). PAPER stays black on white: QR codes / posters, bill
  pictures, PDFs, print -- wrap in `AskodoxPaper`; never give a QR a dark background. Left alone on purpose: drawn
  art (work scene, companion), camera and video screens, `rich_reply.dart` (knows light and dark itself).
- Category tree = `taxonomy.py` + resource `taxonomy_nodes` (staff-editable,
  seeded once) + `/api/taxonomy/resolve`; capabilities inherit down the path.
  The app calls it only for delivery capability / partner phrases.
- Video commerce = `video_commerce.py` (grounding basis, sensitive topics never
  AI-answered, reply plan off/draft/auto) + `routes/video_commerce.py`; the
  detail route `/api/videos/native/{id}` is registered LAST. App:
  `native_video/video_commerce.dart`; chat questions about a video go to its
  study (`_videoStudyRef`, `nv_` -> native ask endpoint), never the deal search.
- In-app Screen Guide = `features/guide/in_app_guide.dart`, mounted in the app
  builder. Steps target existing widget KEYS (`x*` = prefix); visible = a hit
  test reaches it. Renaming a targeted key breaks a walkthrough -- grep
  `askodoxGuideFlows`. Private routes pause it (`askodoxGuidePrivateRoutes`).
- Mobility draft (`askodoxMobilityDraftProvider`) is the ONE ride / parcel being
  set up, shared by chat and the Rides screen.
- Push preferences: `push_prefs` (app Notifications switches via
  `PUT /api/me/notification-settings`); `PushService.notify` obeys them.
- Own-supply fit: `supply_fit.evaluate` judges a registered listing against the
  customer's explicit constraints (matched / unmatched / unknown -- unknown is
  never assumed); registered rows carry `fit` + `why` and rank by fit; gaps are
  aggregated in `supply_gaps` (no customer identity) for sellers and staff.
- Smart Entry = `smart_entry.py` + `POST /admin/cc/smart-entry` (prepares forms
  only; value + confidence + provenance; only high confidence pre-fills); the
  console view maps results onto the real create forms. Reuses
  `affiliate_catalog.extract_metadata` -- don't add another page fetcher.
- Staff work queue items are explained by `admin_actions.enrich` (fixed en/te
  WHAT / WHY / IMPACT / ACTION per key, severity from real counts). A new queue
  key needs a TEXT entry. Integration failures come from
  `_failing_integrations` (same live state as the readiness page).
- `tests/test_admin_functional_audit.py` audits every platform resource from
  its schema; a new resource with a cross-field rule needs an OVERRIDES entry.
- Decision brain: `decide()` returns `mode` advice / follow_up / commerce / chat.
  Advice (`wants_advice` on the USER's words only -- `split_app_context` strips
  the app's "Options already shown" context) gets a separate reasoning call
  (`_advise`) and NO search; the app's `adviceOnly` keeps it out of the deal flow.
- Follow-ups over shown results (compare / cheapest / nearest / reviews / deals /
  under budget / directions ...) are answered by `follow_up_router.dart` from the
  pinned results, never a new search; unknown facts say "Not verified".
- Price truth = `price_truth.py` (list / selling / offer / starting_from /
  page_level; conditional bank / coupon prices go in `offer_price` +
  `offer_condition`, never the price). Strict budgets ("only", "max") drop over-
  budget rows into `rejected`; the app labels "with eligible offer".
- Requested place (`_requestedPlace` in the home screen) survives follow-ups
  until "near me" or a hand-picked place change; it is separate from the device
  location.
- Smart Entry everywhere: `qaStrip`/`qaSetup` in the console add Quick Add,
  templates (built-in `smart_entry.TEMPLATES` + resource `entry_templates`,
  structure only -- `TEMPLATE_FACT_FIELDS` refused), field states, Required /
  Recommended / Advanced and Duplicate previous to every create form. Bulk =
  `/admin/cc/smart-entry` (CSV too) with NEW / UPDATE / DUPLICATE / INVALID /
  NEEDS_REVIEW + `/smart-entry/import` (confirm, drafts only, per-item perms).
- Admin assistant commands = `admin_ops.py` (en/te); the assistant never writes,
  it returns an `operation` the console opens behind a confirm.
- Result Diagnostics payload also carries mode, requested location, raw vs kept,
  rejected, price provenance, ranking and card actions (`_decision_trace`).
- Search readiness belongs to the Conversation Decision Brain: `decide()` returns
  `state` (facts / flexible / unknown_critical), `search_ready`, ONE
  `next_question`, a consolidated `search_subject`, `new_need`; the app sends
  `searched_for` (what is on screen). EVERY retrieval passes
  `askodoxSearchGate` (`lib/features/home/domain/search_readiness.dart`):
  user "show me" > brain readiness > the offline schema rule (only when the
  brain gave none). Brain facts go into the deal via `applyBrainState`; the
  restore path needs `dynamicFields['searched']`. Never add category scripts,
  keyword -> question rules or "search after N answers". Changed details mark
  pinned cards outdated (`askodoxResultsOutdated`); a different need hides them.
  Real-LLM proof: `conversation-trace.yml` + `.github/conversation-traces.json`
  (branch push -> waits for staging `/health` commit -> per-turn TRACE lines).
- Conversation relation (`conversation_relation.py`) compares CONTENT words only
  (grammar, constraints, acks, option refs, numbers removed; Indic-aware tokens,
  plural-insensitive). Thin refinements / acks / choice questions keep the deck;
  a single new word is a WEAK new topic that counts only when the model agrees
  (`reconcile_relation`); a model-confirmed new need whose own description shares
  nothing with the active one retires the deck. The app sends `said_subject` +
  `sources` in `searched_for`. Never add per-category phrases.
- Video asks: a search only when there is something to search videos OF
  (`_video_search_wanted`); talk about Facebook / Instagram / Meta / setup stays
  chat (app: `askodoxTalksAboutVideoPlatform`).
- Comparisons never name a place / price / status / source label as a thing
  (`comparison_entities.py`, app `askodoxComparableLabel`).
- Result Board (home screen): `_boardMinimizedFor` (pill "N Results • ₹20k
  subject ▲", restore), fresh results re-expand, retirement clears pill +
  selected context (`askodoxSelectedContext`), "the best one" -> one card
  (`askodoxWantsSingleResult` / `askodoxBestOnly`). Built on `_resultsByTurn`.
- Header language chip = the reply language (lock > preferred > automatic);
  choosing there is an explicit lock (`lockTo`, PR #166 semantics).
- Affiliate Product Hub: `affiliate_providers.py` (adapter registry, Meesho
  __NEXT_DATA__ first; provenance per field; commission never from a page),
  `affiliate_hub.py` + `routes/affiliate_hub.py` (preview / import / bulk-action),
  console view `affhub`; grant `affiliate_products:publish`. Same item store
  (`affiliate_products`); Smart Links stay routing only.
- Provider health = real answers (`provider_health.py`): Sarvam 402 ->
  QUOTA_EXHAUSTED; readiness rows + Command Center use it, never key presence.
- One-time advice = `advice_memory.py` inside the ONE brain (`decide()` / `_advise`):
  the app keeps the ledger per conversation (`_adviceLedger`, in the snapshot) and
  sends `advice_given`; the reply returns `advice` + `advice_ledger`. A repeat is
  allowed only for new_information / user_asked / critical; others are flagged +
  counted (`assistant_health`). Never add per-category warning rules.
- Command Center feature health (`/admin/cc/health`): `assistant_health.py`
  (conversation_intelligence, media_analysis, advice_policy -- real outcomes, per
  process; no traffic = unknown) + `result_discovery` from `discovery_events`.
  Provider readiness is separate (`provider_health`); neither proves a phone flow.
- Result Board ARCHIVED: a deck retired by a topic change shows only the chip
  `askodoxArchivedResultsRestore` (restores on tap, never on its own).
- Result Board lifecycle + sizing = `lib/features/home/domain/result_board.dart`
  (`askodoxBoardStateOf`, `askodoxBoardMaxHeight` from the Home column's REAL
  height via LayoutBuilder; no room -> pill). Never size it from the full screen.
- Reasoning before results: `DECISION_GUIDANCE_RULES` in the brain prompt (ready
  turns reply with guidance, never a bare acknowledgement; estimates labelled,
  never presented as verified). The app keeps that reply with the cards; a false
  results claim is removed sentence by sentence (`askodoxStripResultClaims`),
  never the whole reply; an advisor hold keeps the brain's answer
  (`askodoxWithoutTrailingQuestion`).
- Channel = `channel_preference.py` (app `askodoxChannelPreference`): online-only
  skips local sources + forces the web search; local-only skips the web search;
  remembered as deal `dynamicFields['channel']`; a channel switch archives the old
  deck. Never per-category.
- Reply prices = card prices: `askodoxReconcileReplyPrices` (chat_result_policy.dart) drops reply sentences whose rupee
  figures are far outside the shown cards' range and adds the cards' real range; the brain never prices a named model
  from memory (DECISION_GUIDANCE_RULES). The customer's own figures are never touched.
- Assistant replies render through `AskodoxRichReply` (headings / points / bold /
  tables / links); speech gets `askodoxPlainReply`. Never show raw markup.
- Voice ends on the user's Stop; `AskodoxVoiceEndpointer` silence (8 s) and 2 min
  are safety limits only. Companion menus = `askodoxCompanionMenuActions` (no
  Location; the header chip is the one location control).
- Self-healing: APPLIED != recovered; `verify_applied` sets VERIFIED /
  NOT_RECOVERED from real evidence, else UNVERIFIED (console "Recovery").
- ONE app voice (owner 2026-11-23): never re-add a reply / payment voice picker; `/voice/speak` speaks
  `elevenlabs_tts.APP_VOICE` whatever the app sends. Changing the voice = new id there + bump Kotlin `VOICE_CACHE_TAG`.
- Reply voice engine lock: the parts of ONE reply keep the first part's engine (`engine` on `/voice/speak`); never
  remove the lock or shorten the locked ElevenLabs wait without checking `ASKODOX VOICE SPEAK` ms in the deploy log.
- Voice = ONE audio lifecycle: every `_speakReply` takes `_speechTurn`; Stop / a newer
  reply bump it so a cut-off reply never falls back to device TTS (two voices). Pause:
  Sarvam pauses in place (`pauseReplyAudio`); device TTS stops and resumes from the last
  `speechRange` start with the SAME engine (`deviceOnly`). Mute skips speech; Replay forces.
- Provider failures carry their kind: Brave `last_error_kind` (per thread) -> chain ->
  `provider_failure.failure_kind` -> source status quota_exhausted / rate_limited /
  auth_failed / error (never `no_results`); app `askodoxProviderProblemText`.
- Result Board default = the LOCKED one-rail layout (after 1303). Category boxes with
  up / down + n/N exist only in mega expand (`askodoxResultBoardMega`); positions live in
  `_boardPositions` ("dealId:kind") so they survive minimize. Don't replace the rail.
- Reply meaning colours come ONLY from the brain's [ok] / [caution] / [risk] tags
  (`askodoxSeverityOf`), never from app keyword guesses; tags are stripped from speech / copy.
- Profile memory = `profile_memory.py` + `/api/me/memory` (hooked in `create_deal` via
  `_remember`): role buyer / seller / service_provider / service_taker (= seeking services
  or jobs), same need UPDATES (history), secrets dropped / masked, private unless consent,
  deleted with the account. Separate from the live demand records.
- Personalization consent: `/api/me/memory` returns `chosen` (False = ON by default, never decided -> the memory screen
  asks once) and `cleared_at`; "delete all memory" also stops EARLIER chats (`conversation_backup.recent_requests(since=
  cleared_at)` on server `saved_at`, which an unchanged re-sync never bumps) from personalizing answers.
- My Business sections = `askodoxBusinessSections` (insights / Analytics first, then
  sections). New sections need a real route; Home must never link My Business.
- API Health & Billing (`api_billing.py`): a balance is REAL only from the provider
  (Brave X-RateLimit headers); otherwise UNKNOWN or a labelled ESTIMATE from an admin
  budget. No recharge route may exist (release gate checks it).
- Admin AI incidents (`admin_incidents.py`) are template text over telemetry; a reason is
  confirmed only from the provider's own answer. Actions only via
  `admin_action_framework.CATALOG` (read-only max 2/h; changes need approval; blocked after
  two NOT_RECOVERED).
- Release gate (`release_gate.py`, `/admin/cc/release-gate`): READY only when all PASS;
  device = qa_checks PHONE VERIFIED only. My Creations image / video generation stay NOT_AVAILABLE
  (the chat photo studio below is separate). Video generation: no provider chosen.
- Travel Radio = `travel_radio.py` + `routes/radio.py`: NO separate package (owner 2026-11-04) -- flag `radio.enabled`
  opens it to every signed-in person and each played segment is one AI Credits use (feature `radio`; free while
  charging is off; empty balance -> 402 `AI_CREDITS_LOW`). Old `addon_radio` plans stay INACTIVE and hidden; existing
  passes / testers listen free; segments only from geocoding / Places / LIVE content; cost model = ESTIMATE.
- Staff Workspace items: store links (meesho / amazon / flipkart / wishlink) keep ONLY the store's own data (no reels,
  no AI photos); Own / Brand products (platform `other`) get our photos, AI description, reels and promotions. Stores
  that refuse the server are read by the staff phone (`askodoxReadStoreBest`: plain request + an ATTACHED hidden browser in parallel, waits for product data, never opens intent:// / app links; page waits 60 s, failures come back as `phone_error`); the server only parses the HTML sent.
  The app answers the WebView file chooser (`askodoxPickFilesForWebPage`) -- without it <input type=file> does nothing.
  Reels: workspace tab `reels` (`/admin/cc/workspace/reels`, file + review routes). The page must never use
  prompt() / confirm() / alert() -- Android WebView shows none of them (inline inputs instead). Its CSP needs
  `media-src 'self' blob:` or the fetched reel never plays.
- AI product videos (owner 2026-11-20 REVERSED "no AI reels / store data only"): store items may use the store's photos
  and get an AI video (`product_video.py`, see checkpoint); the manual upload below still works.
- Product videos (owner 2026-11-06 REVERSED the 2026-11-04 no-video rule): OPTIONAL video made OUTSIDE ASKODOX, <= 60 s
  (checked on the staff phone), uploaded per store item, owner ASKODOX; Videos shows the item's buy link under it
  (`store_item_id` / `buy_url` on the `videos` row; `POST /admin/cc/workspace/items/{id}/video`). No AI-generated reels
  (story-reel PR #271 closed unmerged). Staff page hides the Reels tab / reel buttons (routes stay). Items = link / photos + price + description +
  commission link (`affiliate_url`, grant `links`) + Commission % (`verified_commission_rate`, grant `commission`; a rate
  > 0 sets `commission_status` ACTIVE) -> LIVE items show in search with their own photos.
  Edit after saving = `PATCH /admin/cc/workspace/items/{id}` (My items ✏️ Edit / 🎥 Video; a non-publisher's edit of a LIVE
  item -> NEEDS_REVIEW). Bad-item alerts = `item_health_alerts.py` via `AffiliateCatalog.on_change` (set in `catalog()`):
  OUT_OF_STOCK / commission INACTIVE / rate < `catalog.min_commission_rate` (default 1) -> ONE staff task + push to the
  adder (dedupe `item_health:{id}:{reason}`). It only sees RECORDED changes (Meesho has no API). Staff write the video
  description in English only; viewers get it translated (`video_localization.py`).
- Base plans = `subscription_plans.py` (audience `base`, seeded once from `growth()`, never overwritten);
  Smart Fill = `catalogue_templates.smart_fill` (seller's own words only; app fills empty fields only).
- Partners take jobs only with `docs_checked` complete (`delivery.docs_missing`); paid plans go on sale only
  with `billing.live_pricing`; updates install only on a matching SHA-256 (`askodoxApkDigestMatches`).
- Billing = `billing.py` + `routes/billing.py` on the ONE payment layer (`commerce_finance.PaymentService`,
  `razorpay_gateway.py`, `cashfree_gateway.py`); purchases activate only via `Platform.sync_order` on PAID
  (`billing:` order_ref). Live mode = env `ASKODOX_PAYMENTS_LIVE_APPROVED` only (never the console).
- Razorpay checkout = the hosted page `/billing/pay/{id}` (routes/billing.py `page_router`, mounted in app_factory);
  payment.failed never fails an order (retry allowed); `billing.refresh` reads back via GET only. Env-only gateway
  credentials enable TEST mode until staff configure the row (`updated_by`). The public health row must never
  contain the word "secret" (test_integration_states).
- Gateway state = `payment_gateway_health.check` ONLY (public health row, readiness, API Health, Billing); only a
  Razorpay 401 records a failed check. TEST money -> purchase TEST_PAID, never a subscription / pass. Why a tester has no Pay
  button: Railway deploy logs, filter `billing.options` (masked last 4, tester, reasons).
- Integration Platform (docs/integration-platform.md): `integration_catalog` statuses are COMPUTED (never
  hand-set; mock never counts as tested; NOT BUILT / interface_ready named honestly); sign-in OTP =
  `otp_delivery` (ASKODOX_OTP_CHANNELS); demo number works in production only with ASKODOX_DEMO_LOGIN=yes;
  KYC = `kyc_engine` (consent first, masked + HMAC only, AI extraction never verifies, staff verify only
  business / professional docs); commissions = `commission_engine` on Partner Hub (forward-only lifecycle,
  clicks never conversions); identity = `account_identity` (auth_accounts, one id per 10-digit number; the app
  stores the server's app_user_id).
- Sessions / sign-out: ONE place a verified number becomes a session (`onboarding_auth.signed_in`: returning +
  saved profile -- the app never overwrites it). Sign-out = `lib/core/auth/sign_out.dart` (Profile Settings &
  Privacy last item + header menu Logout): server revoke, FCM token delete, per-account phone data stash
  (`askodoxAccountScopedKeys`, a new account-scoped prefs key must be added there), `AskodoxAppRestart` (fresh
  ProviderScope). Start-up `askodoxCheckSession`: 401 -> signed out, offline -> kept. Firebase init only via
  `AskodoxFirebaseConfig.ensureInitialized` (single flight). Diagnostics never in APP_ENV=production builds.
- Firebase Android config is GENERATED in CI (`tool/firebase_android_config.py write`, required on main) from the
  four FIREBASE_* GitHub variables -> git-ignored `android/app/google-services.json` + Dart define file; the Google
  Services plugin (4.5.0, settings.gradle.kts) is applied only when that file exists; `check-apk` proves the APK
  carries it. Never commit google-services.json or print the values.
- `flutter analyze` in `android-apk.yml` (build-apk) is FATAL on infos too (e.g. `<x>` in a `///` comment outside backticks). The
  job log IS readable: `gh api repos/podx-bot/askodox/actions/jobs/<job id>/logs | grep "info •"`.
- AXE (`executive_ai.py`) only composes existing gate / incidents / billing / registry; it never runs actions.
- Universal POS = `pos_tax.py` (pure GST arithmetic, versioned `RULES_VERSION`, sourced) + `pos_store.py` (tables `pos_*`)
  + `routes/pos.py` (`/api/pos/*`); app `lib/features/pos` (entry My Business -> `/pos`). Money = integer paise, qty =
  milli-units, rates = basis points; issued invoices / payments / ledger / stock moves / audit are append-only (fix with a
  credit note or same-day cancel that keeps the row). Every write is idempotent on `client_txn_id`. Non-members get 404.
  Counter UPI / card = `cashier_confirmed`, never bank-verified. HSN / GST rate only from the shop's own entry. Shared
  vectors `test/fixtures/pos_tax_vectors.json` must pass in BOTH pytest and flutter test -- change both engines together.
  Offline bills use a per-device series (`<P>D<n>/<FY>/<6>`, <=16 chars). Invoice prefix max 3 chars.
  Restaurant = `pos_restaurant.py` (bills via `PosStore._issue` in the same tx); purchases / suppliers / batches =
  `pos_purchases.py` + FEFO in `PosStore._allocate_batches` (expired stock is never sold). New columns go in
  `pos_store.MIGRATIONS` (ALTER TABLE ADD COLUMN), never by recreating a table. Widget tests: never `await` a stream
  subscription `cancel()` / `Future.timeout` in code a fake-async test drives (they hung; see `AskodoxScaleReader`).
  NEVER add `mobile_scanner`: it broke the OTP SMS-consent background case (`sms-consent-e2e.yml`, A/B on 2026-10-24);
  barcodes are read from a photo with pure-Dart `zxing_lib` (`askodoxDecodeBarcodePixels`). Any new native plugin must
  pass `sms-consent-e2e.yml` (it only runs on Kotlin / gradle changes -- dispatch it by hand for a pubspec change).
- Printers / meters native code lives ONLY in `AskodoxHardware.kt` (own channel `com.askodox.app/hardware`, one
  register line in MainActivity); saved printer ids `classic:<MAC>` / `usb:<device>` route native, others BLE
  (`AskodoxRoutingPrinterTransport`). PDFs draw non-ASCII text via `lib/core/pdf/askodox_pdf_text.dart` (await `want`
  before building). POS packs: stock + FEFO always in base units (`base_qty_milli`); serials in `pos_serials`.
- Shop advance = `pos_advance.py` (record only; money stays with the shop): every deposit / deduction / refund is a
  pending `pos_advance_entries` row that ONLY the customer's own OTP-proven number (`app-phone-*`, phone_key = customer
  phone) can approve via `/api/pos/me/advances/{id}/decision`; the shop can only withdraw a pending row. Terms en/te
  (`TERMS_VERSION`) must be accepted by the owner (settings) and by each customer on first approval. Never let staff
  approve, never pay out across shops, never call it a wallet (no RBI licence).
- POS online channel = `pos_online.py`: shop default `pos_businesses.online_default` + item `pos_products.channel`
  (NULL = default); Online / Both = ONE `seller_products` row per item via `pos_online_links` (screened by
  `listing_quality`; review -> hidden + `listing_reviews`); routes call `_online_sync` after sales / stock / purchases
  (best effort, never fails the sale). Online-only items are filtered out of the sale screen picker only.
- Guide button on every screen = `features/guide/screen_help.dart` (`askodoxScreenHelp` by router path pattern, en+te)
  + `screen_help_button.dart` (mounted in app.dart). A NEW SCREEN ROUTE NEEDS AN ENTRY (or an exempt reason) or
  `test/features/guide/screen_help_test.dart` fails. Hub tiles = `shared/widgets/askodox_tile_grid.dart`;
  `AskodoxNavSection` rows without a trailing control are drawn as the same tiles.
- POS catalogue = `pos_catalogue.py` on the ONE `catalogue_templates` engine (shop template = `catalogue_template`
  or `DEFAULT_TEMPLATE[business type]`; `UNIT_MAP` to POS units; import needs the owner's price + GST % when
  regular; details via `clean_attributes` into `pos_products.attributes` -> listing attributes; `online_price_paise`
  (owner / manager) = listing price). Field "?" guides = `shared/widgets/askodox_field_guide.dart`
  (`askodoxAttributeGuide` is generated from the spec -- never per-category text); `AskodoxPosField(guideEn: ...)`.
- Startup: `AskodoxStartupHint` (in memory, cleared on sign-out / account delete) -> the router (rebuilt on every
  session change) starts at '/' after onboarding; onboarding never un-hides the language step while leaving.
  `justOnboarded` -> Home opens the welcome guide once (screen_help_button).
- Guide watching = `features/guide/guide_watch.dart` (`AskodoxGuideNudges` singleton; `AskodoxFieldGuideInfo` wraps a field
  with its help text; `AskodoxPosField(guideEn: ...)` does it). The help layer turns an empty focused box (5 s) or a
  reported error (POS `_fail` on 400/403/409/422) into "Need help?"; a page change clears it. Don't add "?" icons to fields.
  POS rates by quantity = `pos_price_tiers` (per base unit, from a minimum) + `pos_products.min_qty_milli`, applied in
  `PosStore._issue` and app `askodoxTierPrice` (keep both rules equal); photos = `pos_product_photos` (<= 300 KB PNG/JPEG).
  Spoken orders = `askodoxSplitPosOrder` / `askodoxParsePosOrder` -> `AskodoxPosOrderReviewSheet` (never adds silently);
  items match in ANY script by sound (`pos_name_sound.dart` = twin of `name_sound.py`), rule `.claude/rules/pos-spoken-orders.md`.
- Counter pay sheet (`AskodoxPosPaymentSheet`, owner 2026-11-24 "UPI select అవ్వట్లేదు"): picking a way moves a single
  full payment to it (`_choose`), added payments come off (`askodoxPosPayment-<i>`), UPI shows the shop's own QR with the
  amount (`askodoxPosPayQr`, `askodoxDefaultUpi` of `myPaymentMethods`, fetched only when UPI is chosen); way "బాకీ" /
  Due (`askodoxPosPayWay-due`) = the rest is a due: no customer -> name / phone + pay-by day in the sheet
  (`AskodoxPosPayResult`), the screen finds / adds the customer (`_dueCustomer`, walk-in prices kept) + `setDueDate`.
- Business Kit (owner 2026-11-24) = `business_kit.py` (23 categories / 200 sub-categories, ways of working 1-6,
  shop kind + catalogue per sub-category, customer questions, try-on) seeded ONCE into the Command Center resource
  `business_kit` (parent blank = category) and read back via `set_source` (30 s cache). Shop picks = profile
  `category` / `subcategory` (main) + `more` (keys, comma separated); the MAIN pick sets `pos_businesses.template` +
  `catalogue_template` when it changes; `business()` / `my_businesses()` / shop state carry `kit` (`page_family` food /
  service / retail from the union of flows + the main pick's first flow) -> app `askodoxBizKindOf` /
  `askodoxPosHasTables` (never decide pages from a category name). Customer questions: `shop_qa` table
  (`ShopFollows.questions / save_answers / asked / known_answers`), answered in `PosFrontDesk._shop_qa` from the
  owner's answer only; unanswered -> owner push once a day per question (`/me/business/:id/profile?qa=1`). Old
  category keys must keep resolving (`tests/test_business_kit.py` OLD_KEYS). Flows 3-5 = `pos_work.py`, 6 = the CRM.
- Items come in by themselves (owner 2026-11-24): `product_master.py` = barcoded packs only (name / brand / pack / MRP /
  photo shared across shops; never a selling price, never a dish photo); barcode -> Open Food Facts once (ODbL, a miss
  remembered, network errors not), MRP fills the price only when empty. Shelf / packet photo = `pos_menu_photo.read_shelf`
  (Gemini boxes 0-1000 -> Pillow crops). Shop route `/barcode-lookup` (NOT `products/lookup`: pos.py `products/{id}` wins).
- Ways 3-5 = `pos_work.py` (`PosBookings` slot-by-minutes or day = noon in / 11 AM out IST, never two on one thing;
  `PosJobs` token -> received / working / ready / delivered, ready -> `app-phone-<10>` push or WhatsApp text;
  `PosMonthly` dues made lazily per month) + `routes/pos_work.py`; perms settings (setup) / customers (work) / collect
  (pay). Money is only recorded. Tiles appear only for shops whose kit flows hold 3 / 4 / 5 (`askodoxKitFlows`).
- Photo try-on = `POST /api/images/try-on` (image_studio.py; on_me needs consent, revealing wear refused BEFORE the
  provider, same daily cap + AI Credits as edits, labelled AI picture, nothing stored) + app `/try-on`
  (`try_on_screen.dart`); result cards with an https photo carry `askodoxTryOn-<id>`.
- ONE name per shop page (owner 2026-11-24, "New bill" + "Counter bill" pins opened one page): `askodoxShopPageNames`
  (`pos/domain/shop_page_names.dart`) names it everywhere (Money pages, dashboard, `/my-shop/<tool>`, guide, chat buttons,
  ASK bar); pins are one per page (`askodoxSamePage`). Rule `.claude/rules/shop-page-names.md`.
- Self-shopping = `pos_selfshop.py` (tables `pos_selfshop_*`) + `/api/pos/selfshop/*` (customer, any signed-in user, join
  rate-limited) + `/api/pos/businesses/{id}/selfshop*` (staff). Daily 6-digit code (QR `ASKODOX-SHOP:<code>`); sessions
  OPEN -> CHECKOUT (4-digit exit code) -> BILLED via `PosStore.create_invoice` (client_txn_id `selfshop-<sid>`); weighed /
  serial items are refused to the counter. Exit check = `askodoxDecodeAllBarcodesPixels` (zxing GenericMultipleBarcodeReader,
  DISTINCT codes only -> quantities by hand). Payment stays at the counter; never mark a list paid without the cashier.
- Guide sheet = `features/guide/guide_sheet.dart` (reads the screen help aloud, ask box + mic -> `/api/in-app/guide/ask`
  grounded on the screen help only, "Show me" = `askodoxFlowsOwnedBy(path)`: flows whose last routed step is on this
  screen -- never guess a flow from a step that merely passes through). POS boxes show an example inside
  (`askodoxPosFieldExample`); item details pre-fill EMPTY details via Smart Fill from the item name / seller's words.
  History = local archive + `/api/me/conversations` backup (`conversation_backup.py`, newer copy wins, deleted with the
  account); `_user_memory` in in_app_assistant gives the brain the caller's own earlier requests (token only).
- Profile = search / talk bar (`askodoxProfileSearch` + mic; one spoken match opens it) + three tabs `askodoxProfileTab-me|
  business|settings` + recent chips (`askodox.profile.recent.v1`). Rows go through the local `row(...)` helper so they are
  indexed for search; a running walkthrough switches to the tab holding its target key. Keep every row key when moving rows.
- Profile editor = `profile_editor.dart` (`askodoxOpenProfileEditor`): mini-box grid, one box open at a time, phones
  (`phones` JSON: kind / number / same_as_personal / from / to; the verified number is shown locked) + addresses
  (`addresses` JSON; old `address` / `business_address` follow the first home / business entry server-side), roles chosen
  ONLY in its roles card (signed-in Profile shows no role chips). Guide targets open their box (`_guideTargets`).
- App icon / splash = COMMITTED PNGs in android/app/src/main/res (adaptive mipmaps, drawable-nodpi/askodox_splash_mark.png);
  source art `assets/brand/askodox_logo_source.svg`; in-app `AskodoxLogo`. `tool/apply_android_askodox_branding.sh` must never
  write launcher / splash files again (it only checks they exist).
- Command Center console map = `admin_console_nav.py` (heading -> category -> page; ONE mixed Telugu-English `label` /
  `what` / `do` per item -- "Payment స్థితి", never "English · తెలుగు" or a stacked Telugu line). A new console view or
  schema resource needs exactly one entry there or `tests/test_admin_console_nav.py` fails. View titles come from the
  nav label (`head()` -> `labelOf(VIEW)`). Errors go through `explainError` / `errText` (ONE mixed why / what-to-do per
  HTTP status). Work queue `admin_actions.enrich` -> `explain` = one mixed {what, why, impact, action, button};
  incidents: the console reads `?language=te` (= the mixed text).
- POS payment voice alerts = `pos_payment_alerts.py` (events, dedupe, devices, acks, fan-out; phone events are ALWAYS
  `notification_unverified`) + `pos_payment_providers.py` (the shop's OWN Razorpay: encrypted keys, UPI QR, signed webhook
  `/api/pos/payment-webhooks/razorpay/{id}` + Razorpay API re-check -> `record_verified`; live keys only with
  `ASKODOX_POS_PROVIDER_LIVE_APPROVED=yes`). Native = `AskodoxPaymentAlerts.kt` (channel `com.askodox.app/payment_alerts`,
  chime + max media volume + LoudnessEnhancer player, `speakRemote` once per event) + `AskodoxMessagingService` (subclass of the FlutterFire messaging service; the plugin service is removed in the manifest)
  (high-priority FCM data `type=payalert` via `PushService.send_data`, speaks with the app closed). The notification
  LISTENER is NEVER in the default manifest: Play Protect blocked sideloaded APK 1366 for it -- Play builds only
  (`tool/apply_android_payment_alerts.sh`, Live Build `include_payment_alerts` + `build_play_bundle`); CI fails a
  sideloaded APK that declares it. Flag `pos.payment_alerts` = emergency off. Flutter: `/pos/:id/payment-alerts`.
- Shop core is FREE FOR EVER (owner 2026-11-23): `shop_free_core.py` lists payment voice / quick bill / dues / sales
  reports and their routes; never reserve credits, answer 402 or check a plan there (`test_shop_free_core.py` fails).
  Shop retention = `shop_retention.py` (`shop_activity_days` roll-up; a new kind of counter work = one row in `SOURCES`).
- AI Credits = `ai_credits.py` + `routes/ai_credits.py` (append-only `ai_credit_ledger`, UNIQUE ref, live + TEST balance;
  added ONLY in `billing.on_payment`; assistant reserves one 'chat' use before the model, releases on no answer; charging
  OFF until staff rates). Packs = growth plans audience `ai_credits` (seeded INACTIVE). Play Store sale needs Play Billing.
- Business CRM = `pos_crm.py` + `/api/pos/businesses/{id}/crm/*` (app `pos_crm_screens.dart`, My Business -> `/crm`,
  shop tile `/pos/:id/crm`). ON the POS core, never a copy: customers = `pos_customers` (save-as-customer via
  `PosStore.add_customer`), quotations = `pos_drafts` kind quotation (`pos_crm_quotes` only links + status; the sale screen
  takes `?lead=&customer=` and the drafts route auto-links), staff = `pos_members` (masked refs), bills / dues read from
  `pos_invoices` / `pos_payments` / `pos_ledger`. Permission `crm` (owner / manager / cashier), reports need `reports`.
  Timeline `pos_crm_activity` is append-only; follow-up pushes = periodic job `crm_reminders` (once per follow-up).
- Role AI agents = `pos_agents.py` + `/api/pos/businesses/{id}/agents|agent-actions` (app `pos_agent_screens.dart`,
  `/pos/:id/agents`, buyer agent `/me/agent` via `/api/pos/me/agents/buyer/ask`). An agent = a role VIEW (its POS
  permission), facts via the same store methods, the model only re-words (`_phraser`, AI Credits reserve when charging ON).
  SAFE actions run as the caller; SENSITIVE ones PENDING_APPROVAL -> owner / manager approves -> run AS THE APPROVER (four
  eyes for managers, staff roles owner-only). Never add an agent action that moves money, messages customers or deletes.
- Finance items (owner 2026-11-25) = `finance_items.py`: never loosen the quote-on-page check, never show AI points / answers before a staff
  `confirm`, never put a customer's number in a list (only `reveal`, audited), never take a call back without `consent` true. No advice wording.
- ASKODOX NEVER holds buyer / seller money (owner rule 2026-10-27). Own ways to be paid = `payment_methods.py`
  (`user_payment_methods`, any app's UPI QR via `parse_upi_qr`, bank number encrypted) + `/api/me/payment-methods`; POS
  collect to the owner's own UPI = `pos_payment_alerts` collect requests (a notification only MATCHES, the shop confirms);
  orders show `pay_to` to the buyer; a LIVE platform checkout for orders is refused (409). Escrow only via a licensed
  partner after owner + legal decision. Command Center = ONE Telugu-English mixed view (no separate en / te toggles).
- Backend tests use a per-run temp DB (`backend/tests/conftest.py`); don't
  reintroduce a shared `podx_v2.db` -- data leaked across re-runs.

## Known open issues (verified, not yet fixed)
- Voice replies: Sarvam Bulbul audio first, device TTS fallback (the old
  `/discover/*` screen with the system recognizer is removed; the Kotlin
  `startVoiceSearch` method remains unused).
- A combined answer ("1 kg curry cut skinless") is stored whole in both
  `cut` and `chickenPreference` (matching still completes).
- No automated check catches "a route's auth requirement changed but a
  Flutter caller wasn't updated" — manual grep only (see gotcha above).
- Naming the current location needs the Geocoding API enabled on the Maps
  key; otherwise the app honestly keeps "Current location".
- Provider leads (`/deals/leads`) are in-app only (home-screen inbox +
  Updates): WhatsApp-only providers are not targeted.
- Background push: server (`push_service.py`) + Android FCM client are built but inactive until the Firebase
  project exists: GitHub variables FIREBASE_API_KEY / APP_ID / SENDER_ID / PROJECT_ID (APK build) and Railway
  FIREBASE_SERVICE_ACCOUNT_JSON. Until then notifications are local + silent while the app is open.
  Exact steps: `docs/auth-and-push.md`.
- Maps (2026-10-04 11:09 probe): Geocoding, Places (New), Places nearby and
  Routes are all OK in production (`/health/maps` all_ok). Real nearby rows
  and the nearest junction now come back; real-phone check still pending.
- Brands: no fixed list -- AI `brand` entity, phrasing, brands on real
  listings (`/api/products/brands`), or a short reply that filled nothing.
  A brand the AI misses in the FIRST message and that no listing carries
  can stay in the subject next to a later brand.
- Companion: human 3D personas are ONE procedural rig (`companion_human.dart`)
  on the shared rasterizer (`AskodoxRaster` in `companion_3d.dart`) --
  stylized, not photoreal; robot = Lite fallback; flat 2D = 3D off. Optional
  avatar packs (`companion_avatar_packs.dart`, `ASKODOX_AVATAR_BASE_URL`) are
  not hosted anywhere yet. Lip-sync needs device TTS `onRangeStart` (API
  26+) or Sarvam audio position; otherwise text-paced. See
  `docs/COMPANION_AVATARS.md`.
- Monetization/price-benchmark l10n strings still contain demo wording but
  are not reachable from customer screens. "Notify me" = availability watches (#253).
- Rate limits, the API cache and live counters are per process; daily API
  usage (and the ₹ estimate) is persisted in `growth_api_usage`.
- Route distance needs the Routes API on the Maps key; map tiles use the
  public OpenStreetMap server (low volume only; heavy use needs a tile
  provider).
- Subscriptions: no payment gateway (paid plans PENDING_PAYMENT);
  entitlements are exposed but not enforced by any feature yet; the older
  Flutter subscription screens are still mock-backed.
- Offers: no stacking and no customer-typed coupon codes. Rewards payouts
  are recorded by admins only (no money moves).
- Hotel/salon/healthcare adapters configure the backend (schema, search
  noun, advice); the app's follow-up questions for them are still generic.
  Advisory is rule-based, not LLM-generated.
- Pre-existing: `deal-completion-memory-smoke` block 2 fails when run
  outside its workflow env (same on `main` before PR #101).
- Partner Hub: secrets are Fernet-encrypted (`ASKODOX_SECRETS_KEY`, fail
  closed without it); click ids are HMAC-signed, counted once, expire
  (`ASKODOX_CLICK_TTL_HOURS`); raw events roll up per day after
  `ASKODOX_EVENT_RETENTION_DAYS` (run lazily at most daily -- no cron). No real
  partner is configured.
- Affiliate catalog: stock / commission change by staff edits, a feed
  import, or (once credentials exist) the marketplace API refresh;
  page-metadata extraction often gets blocked by marketplaces.
  #127's partner registry / staff assignments / BFSI flows and
  `partner_revenue_events` remain unwired (superseded by Partner Hub).
- Customer web chat is the backend-served `/chat` page (same APIs as the
  app); askodox.com proxies `/chat` + its 3 APIs to the backend (website
  Caddyfile). It cannot send requests (identity stays in the app).
- Social auto-DM: Facebook / Instagram adapters are built (`social_dm.py`,
  `/webhooks/meta-messaging`, `social_dm_accounts`, mock simulate) but need
  Meta App Review + the Meta app credentials + each business's Page token
  (EXTERNAL SETUP). WhatsApp auto-DM needs the business's own WABA number;
  Snapchat has no public messaging API.
- Marketplace product APIs: Amazon PA-API 5 / Flipkart adapters are built
  (`marketplace_api.py`, catalog "Refresh from marketplace API") but no
  credentials are configured; Meesho has no product API (feed / staff only).
- Brave web search: the plan was out of credit (HTTP 402) until the owner
  funded it on 2026-10-04; production probes since then answer 200 with real
  online / marketplace rows. The 402 breaker + stale last-good stay in place.
- Mobility: production has no approved driver yet and `delivery.matching` is
  off, so every request honestly ends NEEDS_CONFIGURATION / NEEDS_PARTNER.
  No payment for rides (fare = configured estimate only); no live tracking
  map (partner steps only). Carpool is cost-sharing, not commercial.
- Native video files live on the Railway volume next to the DB
  (`video_uploads/`); no transcoding or server thumbnails (optional upload).

## Working efficiently in this repo
- Delegate broad repo exploration, multi-file call-chain tracing, full
  test-suite runs used for diagnosis, and CI-failure investigation to a
  subagent — bring back only the conclusion, not the raw output.
- Prefer targeted grep/glob over reading whole large files, especially
  `docs/ASKODOX_EXECUTION_TRACKER.md`. It's a historical log, not a
  briefing document.
