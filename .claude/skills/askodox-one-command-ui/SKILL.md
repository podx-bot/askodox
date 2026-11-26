---
name: askodox-one-command-ui
description: Use when the ASKODOX owner asks to change something across the WHOLE app with one command (a button, chip, mic, banner or switch on every page) instead of page by page -- add or flip a switch in one place, never edit pages one by one.
---

# ASKODOX app-wide change in one command

Owner 2026-11-26: "change the whole app with one command, not page by page." Every app-wide piece of the screen is
switched in ONE file: `lib/core/ui/ui_switches.dart`. Pages only READ a switch; no page decides for itself.

## Rules (keep these, they stop a fixed problem from coming back)
1. The owner's choice is applied once in `main()` through `askodoxApplyOwnerUi()`. To change the whole app, change
   that ONE function. Widget-test defaults stay as the tests expect (the real app sets the owner's values).
2. A NEW app-wide element (a button, chip, banner, mic) gets a `bool askodox...On` switch in `ui_switches.dart` and is
   mounted ONCE in a central place (`lib/app.dart` overlay / `app_shell.dart` / `step_kit.dart` / a shared widget) --
   never copied into pages. If you find yourself editing 3+ pages for one element, stop and move it to the centre.
3. Existing switches: `askodoxPageMicsOn` (mics inside pages), `askodoxGuideSwitchOn` (guide chip + intro +
   self-starting walkthrough), `askodoxAskEverywhereOn` (ONE Ask button on every page outside the bottom bar).
4. A hidden element is HIDDEN, not deleted: keep its widget key, route and registry entry
   (`docs/approved_features.json`) so the Feature Registry gate stays green; hiding goes through the switch.
5. Every switch gets a widget test with the switch ON and OFF (see `test/features/guide/ask_everywhere_test.dart`).
   Tests that flip a switch must reset it in `tearDown`.
6. Private pages (sign-in, payments) and the open keyboard never get a floating element
   (`askodoxGuideIsPrivate`, keyboard inset check as in `askodoxAskShownOn`).
7. Follow `docs/UNIVERSAL_DEVELOPMENT_RULE.md`: no per-page or per-category special cases; the PR reports where the
   one switch is and which pages read it.

## Steps
1. Read `ui_switches.dart` and the file that mounts the element (grep the switch name).
2. Add / change the switch; apply the owner's value in `askodoxApplyOwnerUi()`.
3. Mount or hide centrally; grep that no page builds the element itself.
4. Add the ON / OFF test; add or keep the registry entry; open the PR; wait for CI green (`flutter analyze` is
   fatal on infos); then the owner's "1" = merge.
