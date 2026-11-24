# ASKODOX workforce + delivery jobs — owner-approved plan (2026-11-24)

Designs: delivery job https://claude.ai/artifact/5wns7Bm9FEEnr4ug3E9PQv · workers under an authority
https://claude.ai/artifact/73xSUHd4dbqVsLgRfCuX9X. Core rules 1-11 are the owner's words (see the plan text the owner
gave on 2026-11-24); this file records what is BUILT and the owner's CHANGES since.

## Status
| Step | What | State |
|---|---|---|
| 0 | 2 missing screens (work types per business, monthly posting + site attendance) | not drawn yet |
| 1 | Delivery job for the shop's own staff (`pos_delivery_jobs.py`, `/pos/:id/deliveries`, `/me/deliveries`) | PR #430, NOT phone verified |
| 2 | Owner-UPI collect: one-paise clash rule + both told (`pos_payment_alerts.create_request` / `_tell_both`) | PR #430 for delivery jobs; other Business Kit ways (counter / table / parcel / bookings / job cards / monthly) still show the QR without a collect request |
| 3 | Worker sign-up card -> authority cards -> invite / accept, GST / Udyam gate, checklist, OTP view-only documents (`workforce.py`, `/me/work`, `/pos/:id/team`) | built, NOT phone verified |
| 4 | Customer order -> authorities -> direct accept (cash) / assign, worker share record, complaints, reject minus points (`/hire`) | built, NOT phone verified |
| 5 | Work types resource `work_types` + monthly postings with site attendance (live face) | built, NOT phone verified |
| 6 | Ratings + స్వతంత్రుడు badge (settings `workforce.*`) | built, NOT phone verified |

## Owner changes after the plan (2026-11-24)
1. **Cash for self-accepted orders (11:17).** An order a worker accepts HIMSELF under an authority is settled in CASH
   with the worker (the customer pays him; the app only records "#32 ₹250 క్యాష్ లక్ష్మి దగ్గర"). Orders the
   AUTHORITY assigns: the authority chooses (own UPI / cash / both) — a switch, never forced. Reason given by the
   owner: fewer transactions on the authority's account, fewer commission disputes. App wording must not claim tax
   is avoided; cash per person per day stays under the ₹2 lakh cash rule (269ST).
2. **No advice card (11:40).** Do NOT show the "settle a fixed ₹500 / ₹1,000 a month" suggestion — authorities know.
3. **Category-wide authorities, documents by OTP, reject penalty (11:49).**
   - A worker's card goes to EVERY business of the matching category (all of Andhra Pradesh in the worker's area /
     km), not to one shop. Whoever accepts the worker / the order is the authority for THAT order.
   - The worker's documents (licence, passbook, RC ...) are opened by the authority only with the WORKER's OTP:
     VIEW only (no download / share / screenshot where Android allows `FLAG_SECURE`), to check they are real.
   - A worker who is green (free) and keeps REJECTING orders gets negative points (counted like a low rating); this
     blocks the స్వతంత్రుడు badge. Not free = turn OFF (red); ignored / rejected offers while OFF never count.
     The app tells the worker this once in their own language.
4. **Multi-branch businesses (12:03).** Everything must work for an authority with many branches: workers join the
   authority ONCE and can be sent to any of its branches; each branch sees its own jobs, money and day report; the
   owner sees all branches together (one list, branch name on every job). Today (step 1) each branch is its own shop
   (`pos_businesses`) and the owner opens Send delivery per branch; the shared worker pool + all-branches view are
   part of step 3.
