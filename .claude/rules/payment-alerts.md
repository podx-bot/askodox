---
paths:
  - "android/app/src/main/kotlin/com/askodox/askodox/AskodoxPaymentAlerts.kt"
  - "android/app/src/main/kotlin/com/askodox/askodox/PaymentAlertParser.kt"
  - "android/parser-tests/**"
  - "lib/features/pos/data/pos_payment_alerts.dart"
  - "lib/features/pos/presentation/*payment*"
---

# Payment voice alerts — read before touching these files

Follow the procedure in `.claude/skills/askodox-payment-alerts/SKILL.md`. The short version:

- **One payment = one voice, one history row.** The bank SMS and the UPI / bank app notification of the same money
  can arrive in any order and hours apart. The second one joins the first row silently. Two messages from the same
  app or two SMS never join (Rs 1 + Rs 1 = two payments).
- **Whichever message arrives first speaks at once**, with the payer's name when that message has it.
- **The join decision is `PaymentAlertParser.pickSamePayment`** (pure Kotlin, no Android). Do not put matching logic
  back into `AskodoxPaymentAlerts.kt`; it only turns JSON rows into `Row`s and calls the picker.
- **Every owner-reported case becomes a `Sim()` scenario in `android/parser-tests/ParserTest.kt` first**, then the fix.
  Never change a window constant (`LATE_PAIR_MS`, `SAME_PAYER_MS`, `SAME_REF_MS`, the bill-pay windows) or a
  `samePaymentWindow` / `pickSamePayment` rule without a scenario that fails before and passes after.
- **Run the parser gate locally before pushing** (commands in the skill). CI runs the same gate on every change
  to these files.
- **No net never means another voice** (owner 2026-11-23): the phone puts the sentence together from the parts and the
  voice pack it keeps (`PaymentVoicePack`); the phone's own voice only when nothing can be put together. Keep every new
  spoken sentence inside `PaymentVoicePack.packTexts` (the gate checks it).
