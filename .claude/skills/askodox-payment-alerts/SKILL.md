---
name: askodox-payment-alerts
description: Use when fixing or changing ASKODOX payment voice alerts (bank SMS / UPI app notifications, double voice, missing payer name, history rows) or when the owner reports a payment-sound problem.
---

# ASKODOX payment voice alerts

The phone reads bank SMS and UPI / bank app notifications, says "₹X received" (with the payer's name when known) and
keeps one history row per payment. The owner tests on real phones with real money, so every bug he reports is a real
message shape or a real timing. This skill keeps a fixed bug from coming back.

## Where things live

| What | File |
|---|---|
| Reading a message (amount, payer, RRN, account, handle, fake signs) | `android/app/src/main/kotlin/com/askodox/askodox/PaymentAlertParser.kt` |
| Is this message the same payment as an earlier row? | `PaymentAlertParser.pickSamePayment` + `samePaymentWindow` (same file, pure Kotlin) |
| Listener, voice, history JSON, upload | `android/app/src/main/kotlin/com/askodox/askodox/AskodoxPaymentAlerts.kt` (`handle`, `mergeSameMoney`) |
| Tests (message shapes + `Sim()` scenarios) | `android/parser-tests/ParserTest.kt` |
| Voice pack (offline amounts in the same voice), ASKODOX lines, night count rules | `android/app/src/main/kotlin/com/askodox/askodox/PaymentVoicePack.kt` (pure; checks in `voicePackChecks()`) |
| ASKODOX tune | `android/app/src/main/res/raw/askodox_tune.ogg` (made by `tool/make_askodox_tune.py`) |
| CI gate | `.github/workflows/payment-parser-gate.yml` |
| Owner's rules (history) | `docs/ASKODOX_EXECUTION_TRACKER.md`, comments starting `Owner YYYY-MM-DD` |

## The owner's rules (do not break)

1. One payment = one voice, one row. The second message of the same money (SMS after the app, the app after the
   SMS, a late bank-app notification) joins silently, however late it comes (owner 2026-11-17, 2026-11-22).
2. Whichever message arrives first speaks at once. It does not wait for a name.
3. Two real payments are never merged: two messages from the same app, two SMS, or two different RRNs = two payments,
   even for the same amount a minute apart (owner 2026-11-15).
4. The payer's name on the notification must be spoken (owner 2026-11-22: "the name was there but not read").
5. A fake "money received" SMS is never money (owner 2026-11-19 / 22).
6. A payment app's SUMMARY of several transactions ("2 new completed transaction updates · ... · ...") is several
   EARLIER payments, never one message (owner 2026-11-23: one line's amount + another line's name was said as money
   sent). Each line is read alone; it joins its row silently; a line with no row is written and said once as
   "found out late", never as new money.
7. What the phone is NOT SURE about is never said as a fact: ❓, not counted, an ASKODOX notification at once and a
   voice that asks to check the bank balance. When the bank's SMS shows that an earlier voice was wrong, the phone
   says sorry once (owner 2026-11-23).
8. No net / slow net never changes the voice: a sentence is put together from parts heard before + the voice pack
   (`PaymentVoicePack.clipsFor`); a name heard for the first time is left out (same voice), never a second voice. A new
   sentence in `PaymentAlertParser` must stay inside `PaymentVoicePack.packTexts` -- the gate checks every clip of every
   sentence is in the pack (owner 2026-11-23).
9. ASKODOX lines (tune / hello / customer / night) are switches in the Payment voice folder, all ON by default. ASKODOX is
   the voice, never where the money went. A day with no payment says nothing at night (owner 2026-11-23).
10. A bank's debit SMS is money that went out whatever the payee is CALLED: "; Jio Prepaid Recharge credited" (ICICI),
    "To JIO PREPAID RECHARGE" (HDFC), "to jiorecharge@paytm" (Kotak), "Cr. to x@y" (BoB), a shop named "OFFER MART".
    Words in the payee's name (recharge, emi, loan, offer, credited) never drop it (`withoutPayee`). The operator's own
    "Recharge Successful" SMS stays ignored: it reaches the recharged number, maybe paid by someone else (owner
    2026-11-23).

11. Each money ACCOUNT is ON for one side -- "My own" (`mine`), the shop this phone listens for (`shop`) -- or `off`.
    The ACCOUNT decides, not the app it came through (one PhonePe / one SMS app carries both): `PaymentAlertParser.
    accountSide` (last digits, 1234 = 234; else an app linked to an account) runs right after `parse` in `handle`
    (`routeByAccount`); shop money never falls into My own nor the other way round; nothing chosen = the app list, as
    before. Earlier rows move to the shop only on the person's yes (`moveAccountRows`, server `moved`: owner only,
    never spoken) (owner 2026-11-23).

## How a message joins a row (`pickSamePayment`)

- Same RRN on both → same payment, any order, within `SAME_REF_MS` (24 h). Two different full RRNs → never.
- Otherwise: same amount + direction, a source kind the row does not have yet, no clue that says "two payments"
  (different account tail, different payer UPI handle), within `LATE_PAIR_MS` (2 h).
- Same payer handle or payer name on both → `SAME_PAYER_MS` (6 h).
- If several rows fit, a row with a clue wins, then the row closest in time.
- Known trade-off: with no clue at all, another customer's QR payment (SMS only) of exactly the same amount that
  arrives within 2 h of an unpaired notification joins it. Payer handles usually prevent this, so keep handle parsing
  strong rather than shortening the window.

## Summaries, unsure rows, late and sorry voices

- `digestLines` / `digestLinesOf` decide what a summary is (two or more lines / bullets that each carry an amount,
  plus a counting heading or bullets). The listener hands over every piece of the notification; the fullest single
  piece is read. Never add the pieces together: the same line twice would look like two payments.
- A summary line uses `Msg.summary`: it reaches `SUMMARY_MS` (48 h) back and may join a row the same app made;
  `namesClash` keeps another person's same amount out. `skip` gives each row to one line only (Rs 1 + Rs 1).
- The row's own message is the first thing to ask for when a row looks wrong: My phone payments → History → the row →
  "Read from this message". The owner's phone keeps it; the server never has it.

## Procedure for an owner bug report

1. **Write the case down as a test first.** Add a `Sim().run { ... }` scenario to `ParserTest.kt` using the real
   message shape (made-up names and numbers) and the real gap in minutes. Use `check(...)` for a parse problem
   (name or amount). Confirm the test FAILS on current code.
2. **Fix in `PaymentAlertParser.kt`** (pure). Change `AskodoxPaymentAlerts.kt` only to feed data in or out.
3. **Run the gate locally:**
   ```bash
   curl -sSL -o /tmp/kc.zip https://github.com/JetBrains/kotlin/releases/download/v2.0.21/kotlin-compiler-2.0.21.zip
   unzip -q -o /tmp/kc.zip -d /tmp
   /tmp/kotlinc/bin/kotlinc android/app/src/main/kotlin/com/askodox/askodox/PaymentAlertParser.kt \
     android/parser-tests/ParserTest.kt -include-runtime -d /tmp/parser.jar && java -jar /tmp/parser.jar | tail -3
   ```
   It must end with `ALL PASS`. Never delete or flip an older test to make a new one pass. If an older test encoded
   the bug (as "sms 20 min after app = new" did), rewrite it with the owner's dated rule in its name.
4. **Android compile:** `AskodoxPaymentAlerts.kt` needs the Android SDK, so the Android APK CI is the real compile
   check. Wait for it to pass before calling the work done.
5. **Report to the owner** in Telugu: what was wrong (one line each), what changed, which tests now guard it, and
   that nothing is phone-verified until he tests. Merge only on his "1".
