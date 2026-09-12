# ASKODOX UI LOCK — Canonical Home Experience

Status: LOCKED
Date: 2026-09-12

This file is the canonical UI decision for the ASKODOX home experience and must be checked before any future home-screen redesign.

## Locked target
- Keep all existing ASKODOX features and business flows. Do not remove working features just to match the visual mockup.
- Change the Home theme/layout to the approved single-screen design shown by the user on 2026-09-12.
- Home must remain the main conversational surface.
- No second results page for normal discovery/matching. After typing/speaking, chat expands in the same Home screen and seller/product/service result cards appear inline in that same screen.
- Existing Location, Language, Notifications, Deals/Offers, History, Voice, Image/OCR, matching, seller/service flows, and relevant navigation remain available.
- Profile structure/features remain as they currently exist unless the user separately requests a Profile redesign. Do not force the Home theme into Profile behavior or remove Profile functions.
- Existing backend/business logic should be preserved unless a functional bug requires a change.
- Blank/empty results navigation is not an acceptable replacement for inline results.

## Non-negotiable interaction rule
Home → user request → same-screen chat → inline matching/result cards → continued conversation/refinement.

## Change-control rule
Do not replace, reinterpret, or supersede this UI lock from memory or a new mockup unless the user explicitly asks to change it. Any future redesign must first compare against this file and record what is being superseded.

## Completion proof
This UI is not considered complete from code/CI alone. It must be visible and usable in the user's installed Android app, including a live flow that shows an actual request and inline matching cards without a blank second page.
