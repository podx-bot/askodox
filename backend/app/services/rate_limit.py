"""Tiny in-process rate limiter for public (no sign-in) endpoints.

A sliding window per client key (forwarded client IP, else socket peer).
Protects paid external APIs behind /deals/discover and /api/discover/*
from abuse. Process-local by design (like the API cache); a shared store
can replace it without changing callers.
"""
from __future__ import annotations

import threading
import time
from collections import defaultdict, deque

from fastapi import HTTPException, Request

_lock = threading.Lock()
_hits: dict[tuple[str, str], deque] = defaultdict(deque)


def client_key(request: Request) -> str:
    forwarded = (request.headers.get("x-forwarded-for") or "").split(",")[0].strip()
    if forwarded:
        return forwarded
    return request.client.host if request.client else "unknown"


def check(request: Request, bucket: str, *, limit: int, window_seconds: int = 60) -> None:
    """Raise 429 when this client exceeded ``limit`` calls in the window."""
    key = (bucket, client_key(request))
    now = time.monotonic()
    with _lock:
        hits = _hits[key]
        while hits and now - hits[0] > window_seconds:
            hits.popleft()
        if len(hits) >= limit:
            raise HTTPException(status_code=429, detail="Too many requests -- please wait a moment and try again")
        hits.append(now)


def blocked(request: Request, bucket: str, *, limit: int, window_seconds: int = 60) -> bool:
    """True when the client already reached ``limit`` in the window (no hit recorded)."""
    key = (bucket, client_key(request))
    now = time.monotonic()
    with _lock:
        hits = _hits[key]
        while hits and now - hits[0] > window_seconds:
            hits.popleft()
        return len(hits) >= limit


def hit(request: Request, bucket: str) -> None:
    with _lock:
        _hits[(bucket, client_key(request))].append(time.monotonic())


def reset_for_tests() -> None:
    with _lock:
        _hits.clear()
