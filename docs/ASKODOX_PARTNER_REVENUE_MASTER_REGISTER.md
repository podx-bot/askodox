# ASKODOX Partner & Revenue Master Register

Status: FOUNDATION / CONTINUITY LOCK
Updated: 2026-10-02

## Purpose
Maintain one canonical integration register for external commerce, B2B, BFSI and services. ASKODOX must prefer user relevance over commission. Monetization is applied only when a verified/approved attribution route exists.

## Universal routing order
1. ASKODOX local seller/service-provider match.
2. Direct partner API or authorized feed.
3. Aggregator API.
4. Verified affiliate/referral/deep link.
5. Staff-curated product/service/lead record.
6. Normal merchant/service URL when no monetized route exists.

Never hide a better user result only because it has no commission.

## Integration modes
- DIRECT_API
- AGGREGATOR_API
- AUTHORIZED_FEED
- AFFILIATE_LINK
- REFERRAL_LINK
- LEAD_API
- CALLBACK_HANDOFF
- DEEP_LINK
- STAFF_MANUAL
- NORMAL_URL

## Canonical partner fields
- provider_id / company
- sector / category / subcategory
- integration_modes
- API enabled + API base URL + allowed hosts
- affiliate/referral/deep-link templates
- callback/webhook support
- human advisor/call support
- regulatory/compliance notes
- commercial model: commission / CPA / CPL / revenue share / unknown
- attribution/sub-ID capability
- settlement/reconciliation status
- staff fallback enabled
- active/disabled
- last_verified_at
- evidence/source notes

Secrets and credentials MUST stay in environment variables, never this register.

## Sector register

| Sector | Target examples | Preferred route | Staff fallback |
|---|---|---|---|
| Ecommerce | Amazon, Flipkart, Meesho, Myntra, AJIO, Tata CLiQ, Nykaa, FirstCry | aggregator/direct affiliate/API | Yes |
| Grocery / Quick commerce | Blinkit, BigBasket, Zepto | API/affiliate/deep link | Yes |
| B2B / Wholesale | IndiaMART, TradeIndia, wholesalers | lead/API/referral | Yes |
| Classifieds / Used | OLX, Quikr | lead/deep link | Yes |
| Vehicles | CARS24 and dealer networks | lead/API/referral | Yes |
| Insurance | insurer APIs, regulated intermediaries, Riskcovry/Turtlefin/PBPartners-type routes | quote API + digital journey + authorized callback | Assisted only |
| Loans | banks, NBFCs, lending partners | lead/full-journey API | Assisted only |
| Credit cards | issuers/banks/approved distributors | lead/referral/API | Assisted only |
| Investments | AMCs/MF/broker platforms | authorized distributor/API | No unapproved fallback |
| Payments | payment/UPI partners | approved partner/API | No |
| Travel | flights, hotels, holidays | API/affiliate | Yes |
| Bus | bus aggregators/operators | API/affiliate | Yes |
| Food | restaurants, food platforms | local + partner/deep link | Yes |
| Home services | local providers, national platforms | local lead + partner | Yes |
| Healthcare | hospitals, teleconsult, diagnostics | approved API/referral | Assisted |
| Pharmacy | pharmacy platforms/local pharmacies | approved API/affiliate | Yes |
| Education | courses, coaching, EdTech | affiliate/lead/API | Yes |
| Jobs | recruiters/job platforms | feed/API/lead | Yes |
| Real estate | builders/brokers/portals | lead/referral | Yes |
| Logistics | Shiprocket-type platforms, local logistics | API/referral | Yes |
| Mobility | cab/bike/parcel/rental | API/deep link/local | Yes |
| Entertainment | tickets/events/OTT | API/affiliate | Yes |
| SaaS / Business tools | hosting, CRM, AI, business software | affiliate/referral/API | Yes |
| Local commerce | ASKODOX registered sellers/providers | native ASKODOX | N/A |
| Open commerce | ONDC ecosystem | approved network integration | N/A |

## Staff Desk workflow
Use only where permitted by partner terms and applicable regulation.

1. Staff signs in.
2. Staff selects assigned sector/provider/category.
3. Staff adds original product/service/lead URL and verified tracked/referral URL when available.
4. ASKODOX pre-fills only metadata obtained from authorized/permitted sources.
5. Staff verifies title, price, category, image, destination, commission label/status.
6. Deduplicate using provider + stable product/service ID or normalized original URL.
7. Publish.
8. Search ranks by relevance/value, not commission.
9. Click/lead/conversion is recorded using ASKODOX attribution.
10. Expired/stale records are reverified or disabled.

## Affiliate Product Desk
Individual product records are primary. Collections may be stored as optional landing/grouping URLs but must not replace structured product records required for search.

Minimum fields:
provider_id, merchant, external_product_id, original_url, tracked_url, collection_url,
title, category, subcategory, price, currency, image_url, commission_rate(nullable),
commission_label(nullable), active, verified_at, created_by, updated_at.

## BFSI Partner Desk
BFSI requires explicit consent and applicable authorization. ASKODOX must not assume that API availability grants distribution or commission rights.

Supported connection types:
- discovery/quote API
- lead API
- full digital journey
- callback/advisor handoff
- referral/deep link
- status webhook/API
- commission/revenue attribution and reconciliation

Target experience:
User intent -> minimum required details -> explicit consent -> relevant offers/quotes ->
digital purchase/application OR authorized human advisor -> status callback -> attribution.

## Revenue ledger
Every monetized route should be traceable:
ASKODOX request/session -> provider -> external item/lead -> click/lead -> external reference ->
conversion/status -> expected commission -> confirmed commission -> settlement.

Unknown commission must remain UNKNOWN; never infer a percentage from a URL.

## Scale rule
Do not design the catalog as a small manual list. Product/service records must be migration-ready for a scalable relational catalog/search layer. Images should be references/object storage rather than large binary rows. Add indexes for provider, category, price, status and external IDs.

## Partnership leverage
Before special enterprise deals are available, build with approved public/partner routes. Preserve metrics per provider:
searches, impressions, clicks, leads, conversions, GMV/value where available, commission, callback outcomes.
These metrics can later support negotiations for dedicated APIs, account management, callback support, offers and commercial terms.

## Compliance locks
- No scraping or reverse engineering prohibited by partner terms.
- No fabricated affiliate URLs, credentials, commission rates or API support.
- No secret committed to GitHub.
- Financial/insurance journeys require explicit consent and applicable regulatory/partner authorization.
- Sponsored placement is distinct from affiliate attribution and must be labelled separately.
- User relevance remains the primary ranking principle.
