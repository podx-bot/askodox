# Sprint 14 security, privacy, consent and release readiness

> **Status: client-side preparation only.** This application is not declared secure or legally approved. All Sprint 14 workflows and repositories are local mocks. Legal counsel, privacy reviewers, security engineers, and backend owners must approve production behavior.

## Security audit

| Risk identified | Client mitigation | Backend / launch requirement |
|---|---|---|
| Role checks existed mainly in navigation/UI | Permission vocabulary, permission service, and deep-link route checks were added | Authorize every request and object on the server; test database rules |
| Tokens/private data could enter ordinary cache or logs | Separate secure-storage contract and redacting logger were added | Integrate OS secure storage, rotate tokens, revoke sessions, and manage real keys |
| Developer/mock tools may be reachable | Central build-mode feature flags deny all developer flags in release | Build and penetration-test signed release artifacts; remove demo accounts server-side |
| Session/account status handling was incomplete | Inactivity, absolute-expiry, re-authentication, suspended/deleted decisions are modeled | Server remains authoritative for expiry, revocation, suspension, deletion and device sessions |
| Inputs/files trusted client assumptions | Reusable field and reference-only file validation was added; bytes never enter domain objects | Revalidate type, size and content; scan malware; moderate images; use signed URLs/private buckets |
| Seller access could reveal buyer identity | Privacy contract limits seller-facing data and blocked-seller filtering happens before matching | Shape seller APIs so prohibited buyer fields are never returned; aggregation thresholds are required |
| Sensitive admin actions lacked a uniform record | Permission, mandatory reason and append-only audit record contracts were added | Require MFA/re-auth, enforce permission, and store tamper-evident immutable server audit logs |
| Mock payment or rate limits could be trusted | These are explicitly local/UX-only and hidden through release flags | Webhook-confirm payments; enforce distributed rate limits and fraud controls server-side |
| Detailed errors/analytics could leak data | Safe errors expose only support correlation IDs; logging masks common sensitive fields | Sanitize server errors and analytics schemas; configure retention and access controls |

## Architecture and responsibilities

- **Authorization:** roles group permissions, but routes and sensitive commands ask for a specific permission. The backend must independently authorize each operation and resource; client checks are bypassable.
- **Consent:** records are versioned with outcome, time, source, required/optional status, and withdrawal time. Required consent blocks only its associated flow. Optional choices start unselected and remain withdrawable. A server must retain authoritative consent evidence.
- **Deletion lifecycle:** not requested → confirmation → re-authentication → requested → grace period → processing → completed/failed, with cancellation during the allowed window. Production retention exceptions must be disclosed and approved.
- **Secure storage:** mock memory storage is deliberately separate from cache. Replace it with platform secure storage, hardware-backed protection where available, short-lived access tokens, refresh-token rotation, and remote revocation.
- **Uploads:** models contain opaque references and metadata, never file bytes. Production needs server-side filename/type/size/content validation, malware scanning, moderation, private document access, and expiring signed URLs.
- **Abuse prevention:** local counters, reports, and seller blocks demonstrate UX only. Enforce rate limits, spam/fraud detection, appeals and manual-review operations on trusted infrastructure.
- **Audit and logging:** audit writes are append-only through the normal client interface. Reasons are mandatory. Never log OTPs, credentials, tokens, full phone/address, documents, payments, buyer requests, or private admin notes. Production logs require access control, retention, integrity and alerting.
- **Location/privacy:** buyer home and saved locations are never seller-facing. Seller surfaces should receive approximate areas and aggregated demand only. General shop lists must not expose exact coordinates.

## Release configuration checklist (all are launch blockers unless approved otherwise)

- [ ] Real backend and production secrets are securely configured (no secrets in source or example files)
- [ ] OTP provider, resend/login limits, recovery, MFA and device-session management are enabled
- [ ] Payment webhooks and subscription entitlement verification are tested
- [ ] Database authorization rules and object-level permissions are tested
- [ ] Server file validation, private storage, scanning and moderation are enabled
- [ ] Privacy Policy, Terms, Seller Terms, policies and retention schedule are legally reviewed
- [ ] Account export, correction and deletion workflows—including retention exceptions—are verified
- [ ] Analytics, location, marketing and push consent are verified; store privacy labels are complete
- [ ] App signing, integrity controls, crash reporting, monitoring, backup and recovery are configured
- [ ] Server rate limiting, abuse response and fraud monitoring are enabled
- [ ] Admin permission matrix, re-authentication/MFA and immutable audit storage are reviewed
- [ ] Threat model, dependency review, static/dynamic tests and independent penetration test are complete

## Recommended security testing

Test deep links with every role and account state; authorization/object ownership at every API boundary; session fixation, rotation and revocation; consent version upgrades and withdrawals; deletion retry/idempotency; log/analytics redaction; upload polyglots and oversized files; blocked-seller exclusions across alerts, promotions and matching; accessibility with screen readers and keyboards; and release binaries for absence of developer/demo controls.

## Production blockers

There is no real backend authorization, secure-storage plugin, legal approval, identity verification, OTP/payment integration, malware scanning, production rate limiting/fraud detection, secrets management, monitoring validation, or penetration-test evidence. **Do not launch until every applicable item above has an accountable owner and verified evidence.**
