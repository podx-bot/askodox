---
paths:
  - "backend/app/api/routes/**"
---

# Identity & auth in backend routes

- Never trust a client-supplied identity field alone. Use
  `_authenticated_app_user(request)` to get the token-proven caller id
  (401 if missing/invalid/expired/forged), and
  `_matching_app_user(claimed, authenticated)` to reconcile it with any
  client-supplied field (403 on mismatch). Both are defined in
  `in_app_deal.py` and imported elsewhere (e.g. `universal_deals.py`).
- A counterparty's id on a request (e.g. `responder_user_id`,
  `other_user_id`) is a different thing — it names the other party, not a
  claim about the caller. Don't check it against the caller's own token;
  its safety comes from a separate check that the caller is genuinely one
  of the two parties on record for that specific deal
  (`_accepted_interest()` in `in_app_deal.py`).
- `/deals` and everything under it is mounted only in `backend/server.py`,
  not in `app_factory.create_app()` alone. If you're writing or debugging
  a test/script that hits these routes, import from `server`, not
  `app_factory`.
- If you change what identity a route requires, grep the entire Flutter
  app (`lib/`) for every caller of that route before merging — a route's
  auth requirement changing without every caller being updated has caused
  a real production outage before (see `CLAUDE.md`).
- `debug.py`'s `/debug` prefix is legacy naming, not a signal that
  something mounted there is safe to leave unauthenticated or dead —
  `in_app_deal.py` shares that prefix and is a real, live feature.
