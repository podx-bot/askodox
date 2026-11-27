"""Where a viewer's question goes after the stored study (owner decision 2026-11-27).

1. answered -- a stored fact (with its basis and timestamp) answers it
2. product  -- not solved, and the video has an ASKODOX listing: show it (view / order / ask seller)
3. uploader -- still not solved: the uploader gets it in-app (no phone number is ever shown)
4. none     -- an external video with no in-app uploader, or nothing to offer

Pure rules only: no database, no model. The routes pass in what they know.
"""

from __future__ import annotations

from typing import Any, Dict, Optional

ANSWERED = "answered"
PRODUCT = "product"
UPLOADER = "ask_uploader"
NONE = "none"


def uploader_reachable(record: Optional[Dict[str, Any]], viewer: Optional[str]) -> bool:
    """An in-app uploader exists, the video is live, and the viewer is not the uploader."""
    if not record:
        return False
    owner = record.get("owner_ref") or ""
    return bool(owner) and record.get("status") == "ACTIVE" and viewer != owner


def next_step(found: bool, has_product: bool, reachable: bool) -> str:
    """The first step that applies. ``ask_uploader`` is offered on its own flag too,
    because a viewer may still want the uploader after a product was shown."""
    if found:
        return ANSWERED
    if has_product:
        return PRODUCT
    if reachable:
        return UPLOADER
    return NONE


def offer_uploader(found: bool, reachable: bool) -> bool:
    """The in-app 'ask the uploader' button: only when the study did not answer."""
    return (not found) and reachable


def uploader_push_text(language: str = "en") -> Dict[str, str]:
    """Push wording for the uploader. It never carries the question or the viewer's details."""
    if (language or "").lower().startswith("te"):
        return {"title": "ASKODOX", "body": "మీ వీడియో గురించి ఒక ప్రశ్న వచ్చింది. చూడండి."}
    return {"title": "ASKODOX", "body": "A viewer asked a question about your video. Open to answer."}


def sender_push_text(language: str = "en") -> Dict[str, str]:
    """Push wording for the viewer when the uploader replies. No reply text in the push."""
    if (language or "").lower().startswith("te"):
        return {"title": "ASKODOX", "body": "మీ ప్రశ్నకు వీడియో యజమాని జవాబు ఇచ్చారు."}
    return {"title": "ASKODOX", "body": "The uploader answered your question."}
