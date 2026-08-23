# ASKODOX Universal Deal Brain

## Product rule

ASKODOX is not a menu chatbot and must not be implemented as separate scripted conversations for products, jobs, services, rides, rentals, appointments, catering, parcels, or future categories.

Every user utterance — text, voice, image/OCR extraction, barcode result, or quick action — is normalized into the same **UniversalDeal** state.

The system's job is:

1. Understand what outcome the user wants.
2. Identify which side of an exchange the user represents.
3. Identify the opposite party required to complete the outcome.
4. Extract every detail already supplied by the user.
5. Merge new information into the existing deal state; never restart the questionnaire.
6. Ask only for a field that is genuinely required for useful matching or to resolve a conflict.
7. Search/match the opposite side.
8. Rank matches by relevance, location, timing, price/terms, availability, trust and category-specific requirements.
9. If no match exists, save the demand/supply lead, notify the opposite side when available, and optionally offer an online/deep-link fallback when appropriate.
10. After both sides accept, open the direct deal/conversation flow and track the deal to completion.

## Party A / Party B model

Party names are contextual, not hard-coded user types.

| User says / does | Current side | Opposite side ASKODOX must find |
| --- | --- | --- |
| Wants to buy | Buyer / demand | Seller / supply |
| Wants to sell | Seller / supply | Buyer / demand |
| Needs a worker | Employer / demand | Worker / supply |
| Needs work | Worker / supply | Employer / demand |
| Needs a service | Service seeker / demand | Service provider / supply |
| Offers a service | Service provider / supply | Service seeker / demand |
| Needs a ride | Passenger / demand | Driver / available seat / supply |
| Offers a ride | Driver / supply | Passenger / demand |
| Sends a parcel | Sender / demand | Delivery partner / supply |
| Offers delivery | Delivery partner / supply | Sender / demand |
| Needs a rental | Renter / demand | Owner / supply |
| Offers rental | Owner / supply | Renter / demand |
| Needs appointment | Customer / demand | Professional/slot / supply |

A registered person may participate on either or both sides in different deals. Registration roles are capabilities/preferences, not rigid conversation branches.

## Universal core fields

Use shared fields wherever possible:

- subject/item/outcome
- intent
- quantity and unit
- price/budget and price basis
- quality/type/variant
- size/weight/model
- availability
- pickup/delivery/online/onsite fulfilment
- location/radius/route
- timing/deadline
- dynamic category-specific fields

Category schemas add only what that category needs. Examples: job skill/experience/pay type; ride origin/destination/seats; catering guest count/menu; rental duration/deposit; appointment specialty/time slot.

## Clarification policy

Do not ask a fixed checklist.

Ask only when:

- a required match field is missing;
- two extracted values conflict;
- a safety/legal/verification requirement requires explicit confirmation;
- the user must choose between materially different deal interpretations.

If ASKODOX can safely infer or derive a value, continue without interrupting the user.

## Matching policy

Matching is opposite-side first:

`currentDeal.intent -> oppositeIntent -> eligible opposite-party leads/listings -> filters -> ranking -> match`

Matching should work across user modules rather than requiring a buyer to enter a buyer-specific scripted flow or a seller to enter a seller-specific scripted flow.

## UI rule

The home input is the primary entrypoint. Quick buttons such as Buy, Sell, Work, Service, Ride are shortcuts that seed intent only; they must not create separate brains.

Voice and text must enter the exact same deal state. OCR/image/barcode are additional input methods that enrich the same deal state.

The UI may show category-specific cards after intent recognition, but business logic remains in the Universal Deal Brain.

## Backend contract direction

Production endpoints should expose provider-neutral concepts such as:

- `POST /deals/understand` or equivalent intent/extraction endpoint
- `POST /deals` create/update universal deal state
- `GET /deals/{id}/matches`
- `POST /deals/{id}/accept-match`
- `GET /deals/inbox`
- `POST /deals/{id}/messages`
- lead/save-and-notify fallback when matches are empty

Existing `/debug/*` deal endpoints are temporary integration surfaces and must not define the final product architecture.

## Non-negotiable anti-patterns

Do not:

- implement WhatsApp-style fixed question trees per feature;
- discard the user's original sentence when navigating to another screen;
- ask again for information already captured;
- show fake/mock inventory or fake locations in production;
- force one permanent role onto a person when the same person can buy, sell, hire, work, provide or seek services in different deals;
- make commission/payment the primary matching objective.

ASKODOX exists to understand demand/supply and get the user's outcome done by connecting the right two sides.
