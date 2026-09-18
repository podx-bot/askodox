---
paths:
  - ".github/workflows/**"
---

# CI workflow gotchas

- `in-app-e2e-smoke.yml` (and any similar script that needs `/deals` or
  other routes only `server.py` mounts) must import `from server import
  app, container` — not `app.api.app_factory.create_app()` directly, which
  omits `/deals`, `public_home`, and `connected_actions` routers and will
  404.
- `GEMINI_API_KEY` and `BRAVE_SEARCH_API_KEY` are intentionally left blank
  in CI. Anything that depends on real LLM classification (e.g.
  `container.universal_request_extractor.extract`) will not work as-is —
  stand in for just that one method with a deterministic fake result
  rather than skipping the test or trying to configure a real key.
- To call an authenticated route from a CI script, mint a real token
  in-process: `from app.services.session_tokens import issue_token;
  issue_token(user_id, container.settings.session_token_secret)`. The
  script already has `container` in scope, so this needs no real OTP flow.
- Before editing a workflow's `on.push.paths` trigger list, check what the
  workflow's script actually imports/calls now — a stale path list watches
  files the test no longer touches and misses files it does.
