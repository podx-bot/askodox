# ASKODOX Universal AI POS — audit, architecture and status

Last updated: 2026-10-23 · branch `claude/pos-core` (PR #224, stacked on #220 → #221 → #222 → #223).
**Not merged, not deployed, not phone verified, no hardware tested.**

## Phase 0 audit (what existed before)
| Existing piece | Where | Reused / why not |
|---|---|---|
| WhatsApp business ledger (simple receivable / payable notes) | `business_ledger_runtime_service.py`, `business_ledger_repository.py` | Not reused: no invoices, GST, stock or roles. Left untouched. |
| Payment layer (idempotent orders, Razorpay / Cashfree TEST mode) | `commerce_finance.PaymentService`, `billing.py` | Not wired yet: POS records counter payments only; gateway-verified POS payments are a later phase (live mode needs owner approval). |
| Seller catalogue / listings | `catalogue.py`, `lib/features/selling` | Separate: the marketplace listing is public; POS items are a shop's private price list. An import bridge is a later phase. |
| Deal invoice PDF | `lib/features/deals/services/deal_invoice_service.dart` | Not a GST invoice; untouched. |
| BLE gateway | `lib/features/devices/data/ble_gateway.dart` | Reused for printer scanning. |
| Account deletion | `account_privacy.delete_my_account` | Extended: POS memberships end; issued invoices stay (tax records). |

Market research (capabilities only, implementation is original): Vyapar (GST billing, offline, thermal printing),
Petpooja (KOT, tables, recipe inventory), Odoo POS (offline mode). Sources at the end.

## Architecture
- **Money** integer paise, **quantity** integer milli-units, **rates** basis points; Python `Decimal` ROUND_HALF_UP
  on the server, the same integer half-up arithmetic in Dart for the offline preview. Both are checked against
  `test/fixtures/pos_tax_vectors.json`. The server bill is always the final one.
- **Tables** (`pos_*`): businesses, members, products (+history), customers, price_lists, series, invoices (+lines),
  payments, ledger, stock_moves, audit, day_close, drafts. Invoices, payments, ledger, stock moves and audit are
  append-only; products deactivate instead of being deleted.
- **Isolation + roles**: every call resolves the caller from the token, then checks membership + permission in that
  business (non-members get 404). Roles: owner (all), manager (price change, returns, cancel, stock, day close,
  reports), cashier (sell, customers, collect), accountant (view + reports).
- **Idempotency**: invoices, credit notes, collections and stock moves carry a client transaction id; the same id
  with the same payload replays, with a different payload is refused (409).
- **Offline**: each phone reserves its own invoice series (`<P>D<n>/<FY>/<6 digits>`, ≤16 characters); offline
  bills are numbered from it, queued on the phone and sent later; the server accepts a number only from that
  device's series, never twice, and only up to 7 days old. The queue is plain app storage (not encrypted) and is
  stashed per account on sign-out.
- **AI commands**: `askodoxParsePosCommand` turns typed / dictated en/te text into a proposal that the cashier must
  confirm; a changed price still needs a manager / owner role on the server.

## Feature matrix
Status words: IMPLEMENTED AND VERIFIED · IMPLEMENTED, HARDWARE TEST PENDING · PARTIALLY IMPLEMENTED · BLOCKED ·
NOT IMPLEMENTED. "Verified" here means automated tests in CI only — nothing is phone verified yet.

| Area | Feature | Status | Notes |
|---|---|---|---|
| Core | Shop setup (16 business types as templates), multi-shop per person | IMPLEMENTED AND VERIFIED | templates = configuration, one core |
| Core | Roles owner / manager / cashier / accountant, staff by phone, isolation | IMPLEMENTED AND VERIFIED | |
| Billing | Checkout: search by name / Telugu name / barcode text / SKU, cart, discounts, customer rates | IMPLEMENTED AND VERIFIED | |
| Hardware | Barcode from a camera photo (counter + item form; decoded on the phone, exact match only) | IMPLEMENTED, HARDWARE TEST PENDING | pure-Dart zxing_lib; a live preview scanner (mobile_scanner) broke OTP SMS consent in the emulator A/B and was removed |
| Billing | Weighed items (gross − tare = net), meat / vegetable counters | IMPLEMENTED AND VERIFIED | camera never weighs |
| Hardware | Read weight from a standard BLE weight scale (one settled reading, cashier checks it) | IMPLEMENTED, HARDWARE TEST PENDING | private-protocol / RS-232 / USB scales NOT supported; never legal-for-trade proof |
| Billing | Split / partial payments, balance to customer credit, credit limit | IMPLEMENTED AND VERIFIED | |
| Billing | Idempotent issue, immutable invoices, numbering ≤16 chars unique per FY | IMPLEMENTED AND VERIFIED | |
| Billing | Credit notes (partial / full, restock, refund), same-day cancel keeping the record | IMPLEMENTED AND VERIFIED | debit notes NOT IMPLEMENTED |
| Billing | Hold bill / resume, quotation shared as text (not an invoice) | IMPLEMENTED AND VERIFIED | resume uses today's prices; the customer is chosen again |
| Billing | Receipt text, share as text (WhatsApp etc. — user chooses) | IMPLEMENTED AND VERIFIED | email NOT IMPLEMENTED |
| Billing | A4 invoice / bill of supply / credit note PDF, shared via the Android share sheet | IMPLEMENTED AND VERIFIED | Telugu names print as ? in the PDF (no Telugu font embedded yet); native share needs this APK or later |
| GST | CGST/SGST/UTGST/IGST/cess, inclusive / exclusive, exempt / nil / non-GST / zero-rated LUT | IMPLEMENTED AND VERIFIED | rates & HSN only from the shop's entry |
| GST | Composition bill of supply heading, unregistered bill | IMPLEMENTED AND VERIFIED | |
| GST | GSTIN checksum, HSN digits rule (4 / 6), B2C ≥ ₹50,000 recipient details | IMPLEMENTED AND VERIFIED | GSTIN *active status* not checked (needs GST portal / GSP) |
| GST | Place of supply | PARTIALLY IMPLEMENTED | default = shop's State; the API accepts another State (no app control yet); bill-to / ship-to and special service rules are the accountant's call |
| GST | GST summary by rate / HSN / B2B / B2C, invoice register CSV | IMPLEMENTED AND VERIFIED | for accountant review, not a filed return |
| GST | GSTR-1 JSON, e-invoice IRN, e-way bill | BLOCKED | needs a GSP / IRP account + owner approval |
| Inventory | Stock tracking, purchase / wastage / count with reasons, low stock flag | IMPLEMENTED AND VERIFIED | |
| Inventory | Batch / expiry: purchase per batch, first-expiry-first-out sales, expired never sold, returns to the same batch, expiry report | IMPLEMENTED AND VERIFIED | |
| Inventory | Stock valuation at average purchase cost (before GST) | IMPLEMENTED AND VERIFIED | items never bought on a recorded bill have no cost |
| Inventory | Unit conversions (box ↔ pcs), variants, serial / IMEI, multi-warehouse, purchase orders | NOT IMPLEMENTED | |
| Customers | Ledger, running balance, monthly statement, money received | IMPLEMENTED AND VERIFIED | reminders NOT IMPLEMENTED |
| Suppliers | Suppliers, purchase bills (cost before GST, printed-total check, no duplicate bill numbers, cancel keeps the row), payments, monthly statements | IMPLEMENTED AND VERIFIED | |
| GST | Input tax summary from recorded purchase bills | IMPLEMENTED AND VERIFIED | 'as recorded' only; ITC eligibility / GSTR-2B matching NOT IMPLEMENTED |
| Cash | Day close (opening float, expected vs counted, final) | IMPLEMENTED AND VERIFIED | shifts NOT IMPLEMENTED |
| Payments | Counter cash / UPI / card / bank / cheque (UPI / card = cashier-confirmed) | IMPLEMENTED AND VERIFIED | |
| Payments | Gateway-verified UPI / card (provider API) | NOT IMPLEMENTED | payment layer exists in TEST mode; live needs owner approval |
| Offline | Device series, queue, sync, rejected bills kept with reason | IMPLEMENTED AND VERIFIED | storage not encrypted (PARTIAL for "encrypted local DB") |
| AI | en / te typed or dictated commands with confirmation | IMPLEMENTED AND VERIFIED | no in-screen mic button (keyboard dictation works) |
| Hardware | BLE ESC/POS printer (scan, choose, 58 / 80 mm, test print, receipt print) | IMPLEMENTED, HARDWARE TEST PENDING | no printer model tested |
| Hardware | Telugu receipt printing (raster image, bands ≤255 rows) | IMPLEMENTED, HARDWARE TEST PENDING | rendered with the phone font; no printer tested |
| Hardware | Classic Bluetooth (SPP), USB, LAN printers, cash drawer, customer display | NOT IMPLEMENTED | |
| Hardware | Bluetooth / USB barcode scanners that type like a keyboard | IMPLEMENTED, HARDWARE TEST PENDING | they type into the search box; not tested with a device |
| Restaurant | Tables, open orders, item notes, KOT (daily numbers), kitchen screen (new → preparing → ready → served), move / merge tables, split bill by items, takeaway | IMPLEMENTED AND VERIFIED | roles waiter / kitchen; kitchen screen refreshes every 10 s (no push) |
| Restaurant | Priced modifiers / add-ons, KOT printing to a kitchen printer, split by amount / seat | NOT IMPLEMENTED | notes are text only |
| Shipping | Courier integrations | NOT IMPLEMENTED | |
| Accounting | Chart of accounts, P&L, Tally export | NOT IMPLEMENTED | |

## Approvals needed
1. Merge order #220 → #221 → #222 → #223 → #224 and a production deploy (POS APIs are unreachable from any APK until
   the backend is deployed).
2. Any GSP / IRP / e-way bill account, or live payment-gateway mode, before those phases.
3. Hardware for testing: one BLE thermal printer (58 mm), one weighing scale model, a barcode scanner.

## Sources
- CGST Rule 46: https://taxinformation.cbic.gov.in/content/html/tax_repository/gst/rules/cgst_rules/active/chapter6/rule46_v1.00.html
- CGST Rule 49: https://taxinformation.cbic.gov.in/content/html/tax_repository/gst/rules/cgst_rules/active/chapter6/rule49_v1.00.html
- CGST Rule 5(1)(f): https://taxinformation.cbic.gov.in/content/html/tax_repository/gst/rules/cgst_rules/active/chapter2/rule5_v1.00.html
- CGST Rule 53 (State GST department copy): https://cggst.com/wp-content/uploads/2023/07/Rule-53-1.pdf
- Notification 78/2020-CT (HSN digits): https://www.gstcouncil.gov.in/sites/default/files/2024-05/notfctn-78-central-tax-english-2020.pdf
- E-invoice threshold ₹5 Cr (PIB): https://www.pib.gov.in/PressReleasePage.aspx?PRID=1990977
- GST State codes: https://tutorial.gst.gov.in/downloads/news/for_publishing_monthly_gst_data_for_apr_2026.pdf
- Market research: https://vyaparapp.in/billing-app · https://www.g2.com/products/petpooja/features · https://apps.odoo.com/apps/modules/18.0/sh_pos_offline_pwa
