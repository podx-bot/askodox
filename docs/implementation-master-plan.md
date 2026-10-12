# Master plan (dependency order)

1. Catalogue + attribute master (data-driven, admin-editable) -> DONE (code+CI).
2. Indexed attributes + buyer filters API -> DONE (code+CI); Result Board wiring next.
3. Registration wizard per role + verification queue (reuse listing_reviews / delivery partner review).
4. Mobility engine extensions (goods, multi-stop, pricing models, quotes) on `delivery_jobs.py` -- no new stack.
5. Travel Radio (after owner decisions) on the existing voice pipeline (Sarvam, chunked speech, cache).
6. Radio billing on the existing subscriptions model (separate entitlement), gateway after approval.
7. AXE = extend Feature Registry + release gate + Admin AI incidents (no parallel system).
Release: merge + deploy only with owner approval; APK from the merged commit.
