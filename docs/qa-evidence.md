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
| 2026-10-13 | 91c7cc0 (main, PR #187) | 1090 passed | Flutter CI, APK CI, registry, result-contract, smokes, live-build verify: pass | 1324 (sha256 dc28f293…e8ae, 72,336,474 B) | NOT TESTED |

Production probe 2026-10-13 (after #187): /health healthy (91c7cc0), /readiness ready, /admin/cc/radio + /admin/cc/push/readiness 401 without sign-in, /api/plans/catalogue unchanged (Plus / Pro not available).
| 2026-10-14 | d39bdab (main, PR #189) | 1095 passed | Flutter CI, APK CI (with Firebase plugins), registry, result-contract, smokes, live-build verify: pass | 1325 (sha256 e957ec40…0489, 72,556,545 B) | NOT TESTED |

Production probe 2026-10-14 (after #189): /health healthy (d39bdab), /readiness ready, /api/billing/purchases/mine + /admin/cc/billing/status 401 without sign-in. Live FCM / live gateway tests: BLOCKED (no Firebase project values, no gateway account).
| 2026-10-15 | 61f771b (main, PR #191) | 1101 passed | Flutter CI, APK CI, registry, result-contract, smokes, live-build verify: pass | 1326 (sha256 ce958249…9fc1, 72,572,929 B) | NOT TESTED |

Production probe 2026-10-15 (after #191): /health healthy (61f771b); /health/integrations Razorpay = TEST_MODE_READY (key_kind test, read-only key check OK, checkout_ready true, webhook signing not set); /api/billing/options, /purchases/mine, /admin/cc/billing/status 401 without sign-in; forged pay links 404. Real Razorpay test payment on a phone: PENDING (owner).
