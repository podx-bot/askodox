# QA evidence (automated vs phone)

| Date | Commit | Backend | Flutter CI | APK | Phone |
|---|---|---|---|---|---|
| 2026-10-10 | 77e5d16 | 1045 passed | pass | 1319 (sha256 e5011ff0…4e3e) | NOT TESTED |
| 2026-10-12 | 53ce72d | 1049 passed | pass (+ APK CI, registry, result-contract) | 1320 | NOT TESTED |

Automated tests use fakes for providers (Sarvam, Brave, Maps, Gemini): they never prove a live integration works.
| 2026-10-12 | 1db4f74 (main) | 1050 passed | Flutter CI, APK CI, registry, result-contract, smokes: pass | 1321 (sha256 2ad83867…459a, 71,991,930 B) | NOT TESTED |

Production probe 2026-10-12: /health 200 healthy (1db4f74), /readiness 200 ready, /api/catalog/templates 200, /api/catalog/filters/pickles 200 (no listings yet -> empty values, never invented), /api/products/search?attr= 200.
| 2026-10-13 | 70e0255 (main, PR #183) | 1078 passed | Flutter CI, APK CI, registry, result-contract, smokes: pass | 1322 (sha256 4ac4e85a…4d26, 72,336,286 B) | NOT TESTED |

Production probe 2026-10-13: /health 200 healthy (70e0255), /readiness ready, /api/plans 200 (no add-on listed), /api/radio/status 401 and /admin/cc/axe/brief + /admin/cc/radio 401 without sign-in, catalogue endpoints 200.
| 2026-10-13 | 1740959 (main, PR #185) | 1086 passed | Flutter CI, APK CI, registry, result-contract, docker smoke: pass | 1323 (sha256 e6b77aa2…61df, 72,320,090 B) | NOT TESTED |

Production probe 2026-10-13 (after #185): /health healthy (1740959), /readiness ready, /api/plans/catalogue 200 (free available; plus / pro not available), /api/plans lists Free only, radio / AXE admin routes 401 without sign-in.
