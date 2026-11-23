---
paths:
  - "backend/app/services/shop_free_core.py"
  - "backend/app/services/ai_credits.py"
  - "backend/app/services/billing.py"
  - "backend/app/services/subscription_plans.py"
  - "backend/app/api/routes/pos.py"
  - "backend/app/api/routes/pos_frontdesk.py"
  - "backend/app/api/routes/in_app_assistant.py"
---

# Shop core is free for ever (owner 2026-11-23)

Payment voice, quick bill, the dues (baaki) book and the day / month sales reports are never charged and never
put behind a plan. The list is `backend/app/services/shop_free_core.py` (`FREE_FOREVER`, with the API routes that
ARE each tool).

- Do not reserve AI Credits, answer 402 or check a plan / entitlement in the handler of a route in that list.
  `backend/tests/test_shop_free_core.py` reads every such handler and fails when it does.
- `/api/in-app/voice/speak` is in the list: the phone fetches the spoken parts of a payment there. If reply voice
  is ever charged, payment voice must be let through free FIRST.
- A new AI Credits feature can never use one of the list's keys (`ai_credits.py` asserts it at import).
- Paid extras (AI agents, photo studio, chat, radio) are outside the list and may use credits.
- Adding a tool to the list = the owner's decision. Taking one out needs the owner's own word (registry entry
  `shop_core_free_forever`).
