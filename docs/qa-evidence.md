# QA evidence (automated vs phone)

| Date | Commit | Backend | Flutter CI | APK | Phone |
|---|---|---|---|---|---|
| 2026-10-10 | 77e5d16 | 1045 passed | pass | 1319 (sha256 e5011ff0…4e3e) | NOT TESTED |
| 2026-10-12 | 53ce72d | 1049 passed | pass (+ APK CI, registry, result-contract) | 1320 | NOT TESTED |

Automated tests use fakes for providers (Sarvam, Brave, Maps, Gemini): they never prove a live integration works.
| 2026-10-12 | 1db4f74 (main) | 1050 passed | Flutter CI, APK CI, registry, result-contract, smokes: pass | 1321 (sha256 2ad83867…459a, 71,991,930 B) | NOT TESTED |

Production probe 2026-10-12: /health 200 healthy (1db4f74), /readiness 200 ready, /api/catalog/templates 200, /api/catalog/filters/pickles 200 (no listings yet -> empty values, never invented), /api/products/search?attr= 200.
