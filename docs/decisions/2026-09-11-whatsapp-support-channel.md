# ASKODOX Decision Record — WhatsApp as Support Channel

Status: LOCKED CURRENT DECISION
Date: 2026-09-11
Applies to: ASKODOX communication architecture, admin/customer support, HR, complaints and escalations

## Decision
The previously created WhatsApp integration must NOT be used as the primary ASKODOX business, discovery, matching, commerce, deal, product, service, ride, or daily-life assistant interface.

ASKODOX's main user experience stays inside the ASKODOX app.

WhatsApp is repurposed as a SUPPORT CHANNEL for ASKODOX operations.

## Approved WhatsApp Uses
- Customer care / helpdesk support
- User requirements that need human/admin support
- Complaints and grievance intake
- Unresolved issue escalation
- HR / recruitment / staff communication
- Business/admin operational support
- Account or verification support where appropriate
- Support follow-up and case-status communication where appropriate
- Emergency fallback support if the in-app support path is unavailable

## Not the Primary WhatsApp Use
Do not use WhatsApp as the main channel for:
- Product discovery
- Seller/buyer matching
- Service matching
- Job matching
- Ride booking
- Normal ASKODOX AI conversations
- Routine deal flow
- Main payment flow
- Main delivery/courier flow
- Affiliate product browsing
- BFSI product discovery
- General daily-life assistant conversations

These belong in the ASKODOX app unless a future explicit decision changes the architecture.

## Support Flow
User in ASKODOX app → AI Customer Desk → attempt in-app resolution → if unresolved or user requests human help → create/support case → admin/customer-care queue → WhatsApp may be used as an external support communication channel → resolution/status captured back into ASKODOX support/admin records.

## Data / Audit Rules
- Every WhatsApp support case should have a support/case ID where practical.
- Important complaint, escalation, HR or support outcomes must be recorded back into ASKODOX admin/support history so WhatsApp does not become an isolated data silo.
- Store only necessary personal/contact data.
- Respect consent and privacy before sending WhatsApp support messages.
- Support staff actions and resolution outcomes should be auditable.
- WhatsApp must not bypass ASKODOX consent, payment, trust, dispute or identity rules.

## Relationship to Earlier Architecture
SUPERSEDED: Earlier PODX/ASKODOX concepts that treated WhatsApp as the primary operational/business interface.

CURRENT: ASKODOX app is the primary experience. WhatsApp is a secondary customer-care/admin/HR/support channel.

## Implementation Acceptance Criteria
This decision is not GREEN until:
1. Primary business/user flows are app-first.
2. WhatsApp routing is separated from normal commerce/matching flows.
3. Support categories exist for customer care, complaints, HR and admin escalation.
4. Support case IDs/history are persisted.
5. Relevant WhatsApp interactions can be associated with the correct user/case without exposing unnecessary data.
6. Escalation and closure states are tracked.
7. Admin audit/history is available.
8. Tests verify WhatsApp cannot accidentally become the primary business workflow again.
