# QA evidence (automated vs phone)

| Date | Commit | Backend | Flutter CI | APK | Phone |
|---|---|---|---|---|---|
| 2026-10-10 | 77e5d16 | 1045 passed | pass | 1319 (sha256 e5011ff0…4e3e) | NOT TESTED |
| 2026-10-12 | 53ce72d | 1049 passed | pass (+ APK CI, registry, result-contract) | 1320 | NOT TESTED |

Automated tests use fakes for providers (Sarvam, Brave, Maps, Gemini): they never prove a live integration works.
