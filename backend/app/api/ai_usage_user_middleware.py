"""Binds the signed-in ASKODOX user to the request so the AI usage meter can attribute provider calls to them.

Pure ASGI (outermost), so the context var is set before any inner task / thread is created. Only a VALID session
token binds a user; a missing / bad / expired token binds nothing and changes nothing else (routes still do their
own auth). Never raises into the request.
"""
from __future__ import annotations

from typing import Any

from app.services import ai_usage_meter
from app.services.session_tokens import verify_token


class AiUsageUserMiddleware:
    def __init__(self, app: Any, container: Any) -> None:
        self.app = app
        self.container = container

    async def __call__(self, scope, receive, send):  # type: ignore[no-untyped-def]
        if scope.get("type") != "http":
            return await self.app(scope, receive, send)
        user = ""
        try:
            for name, value in scope.get("headers") or ():
                if name == b"authorization":
                    raw = value.decode("latin-1").strip()
                    if raw.lower().startswith("bearer "):
                        user = verify_token(raw[7:].strip(), self.container.settings.session_token_secret) or ""
                    break
        except Exception:
            user = ""
        if not user:
            return await self.app(scope, receive, send)
        token = ai_usage_meter.bind_user(user)
        try:
            return await self.app(scope, receive, send)
        finally:
            ai_usage_meter.reset_user(token)
