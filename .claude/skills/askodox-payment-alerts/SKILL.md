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

12. One payment told by TWO apps of the same kind (PhonePe + Paytm both notify a credit; one SMS shown by Messages +
    Truecaller) is ONE voice ONLY WITH PROOF: the same reference, the same payer id / name, or the very same message
    text (`messageKey`), within `SAME_KIND_APPS_MS` (10 min). The same amount + time alone NEVER joins two apps of one
    kind -- two customers can pay the same amount at the same moment (owner 2026-11-24). The same
    UPI reference is the same money even from the SAME app / SMS app (checked before the same-app rule). A payer id is
    compared before the '@' (9876543210@ybl = 9876543210@axl) (owner 2026-11-24).
13. Shop money heard as a PUSH (another phone / the bank) and later as this phone's own message: one local + one
    remote of the same shop and amount within 2 h pair once (`PaymentAlertParser.claimHeard`) -- the second is
    silent. Never a 2-minute rule again (owner 2026-11-24: "said again an hour later").
14. A voice that was already HEARD is never said again by the fallback voice (`PaymentVoicePack.sayAgainAfterFailure`).
    Parts are joined with `PaymentVoicePack.joinMp3` (sound frames only, no ID3 / "Info" frame in the middle) and the
    player's time limit is the length counted from the frames (`mp3DurationMs`), never the first part's length --
    that cut sentences before the last word and then repeated them (owner 2026-11-24).
15. The night count is ONE voice per phone: the shop and My phone added together (`PaymentVoicePack.nightTotal`),
    each side's own numbers only in the notification; one `night_said:<day>` mark (owner 2026-11-24).

16. The ❓ net (owner 2026-11-25): a REGISTERED bank's SMS with the person's own account and an amount that the phone
    could not read is ASKED about, never guessed: one ❓ row (not counted, never spoken) + one notification; the answer
    (came in / went out / not a payment, in the row's "Read wrongly?") is learned by `skeleton` for every later
    message of that kind. `PaymentAlertParser.unreadBankMoney` stays conservative (OTP, limit, offer, due, statement,
    mandate, failed / future payments, fake signs = never asked); at most 3 questions a day (`ASK_PER_DAY`); a kind
    already answered is never asked again. Nothing is uploaded.

17. Money the person SENT (owner 2026-11-25: own Rs 6,500 paid 14:03, bank SMS at once, PhonePe's notification of
    the same payment at 22:10 was said + written again): the bank's debit SMS and a UPI / bank app's message of the same
    amount join silently up to `OWN_OUT_LATE_MS` (24 h) apart, any order, unless the two names clash
    (`PaymentAlertParser.ownMoneyLate`). Money RECEIVED never uses it (two customers, same amount).
    A payment that sends NO notification and NO SMS cannot be heard by any phone app -- never guess one.

18. The bank's alert E-MAIL is a third source (owner 2026-11-25: "notification, SMS, e-mail -- if the 3 are one, say it
    once, however late"). Mail apps = kind `email` (`isMailApp`, catalogue Gmail / Outlook / Samsung Email / Yahoo /
    Zoho). Read ONLY when the sender names a bank (`PaymentAlertParser.bankMail`: "bank" or a bank's short name; not
    BankBazaar, not a bank group's insurer / fund / broker) AND the mail names the person's own account -- a shop's
    receipt mail ("payment of Rs 499 successful") would be read the wrong way round. `BANK_KINDS` = sms + email: the
    e-mail is bank-confirmed like the SMS; debits carry `rrn(text)` as their reference so SMS + e-mail + app match
    exactly. Gmail notifies only Primary by default: the app shows `askodoxBankMailHint` (Notifications "All").

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
