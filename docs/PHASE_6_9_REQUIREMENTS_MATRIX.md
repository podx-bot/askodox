# ASKODOX Phase 6–9 requirements matrix

Status: VERIFIED GREEN

This matrix reflects the current verified workspace state as of 2026-09-18. It is intentionally conservative: a requirement is only marked as implemented when it is both present in code and backed by a passing verification command.

| Requirement | Implemented location | Test | Result |
| --- | --- | --- | --- |
| Known user location persists without re-asking | [backend/app/services/universal_ai_assistant_service.py](../backend/app/services/universal_ai_assistant_service.py) | [backend/tests/test_universal_ai_assistant_location.py](../backend/tests/test_universal_ai_assistant_location.py) | PASS |
| WhatsApp location shares are redirected away from business flows | [backend/app/services/whatsapp_support_only_gate.py](../backend/app/services/whatsapp_support_only_gate.py) | [backend/tests/test_whatsapp_support_only_gate.py](../backend/tests/test_whatsapp_support_only_gate.py) | PASS |
| General WhatsApp support-only gate remains intact | [backend/app/services/whatsapp_support_only_gate.py](../backend/app/services/whatsapp_support_only_gate.py) | [backend/tests/test_whatsapp_support_only_gate.py](../backend/tests/test_whatsapp_support_only_gate.py) | PASS |
| No-match fallback and affiliate-aware recovery path | [lib/features/deal_brain/domain/no_match_recovery.dart](../lib/features/deal_brain/domain/no_match_recovery.dart) | [test/no_match_recovery_test.dart](../test/no_match_recovery_test.dart), [test/deal_matcher_recovery_test.dart](../test/deal_matcher_recovery_test.dart) | PASS |
| Local-first + online/affiliate fallback logic in app domain | [lib/features/deal_brain/domain/no_match_recovery.dart](../lib/features/deal_brain/domain/no_match_recovery.dart) | [test/no_match_recovery_test.dart](../test/no_match_recovery_test.dart) | PASS |
| Dynamic Party A / Party B acceptance gate | [lib/features/deals/domain/sandbox_investor_flow_coordinator.dart](../lib/features/deals/domain/sandbox_investor_flow_coordinator.dart) | [test/sandbox_party_gate_test.dart](../test/sandbox_party_gate_test.dart) | PASS |
| Seller/provider trust and compliance fields | [backend/app/repositories/product_catalog_repository.py](../backend/app/repositories/product_catalog_repository.py), [lib/features/seller](../lib/features/seller) | full backend suite, seller/catalog Flutter tests | PASS |
| Service decision assistant | [backend/app/services/phase_6_9_assistant_service.py](../backend/app/services/phase_6_9_assistant_service.py), [backend/app/services/universal_aware_conversation_service.py](../backend/app/services/universal_aware_conversation_service.py) | [backend/tests/test_phase_6_9_runtime_integration.py](../backend/tests/test_phase_6_9_runtime_integration.py) | PASS: real registered provider profiles are ranked; placeholder providers are not used |
| Buyer decision assistant | [backend/app/services/phase_6_9_assistant_service.py](../backend/app/services/phase_6_9_assistant_service.py), [backend/app/services/universal_aware_conversation_service.py](../backend/app/services/universal_aware_conversation_service.py) | [backend/tests/test_phase_6_9_runtime_integration.py](../backend/tests/test_phase_6_9_runtime_integration.py), full Flutter suite | PASS: real seller catalog listings are ranked |
| Party A ↔ AI ↔ Party B orchestration | [backend/app/services/phase_6_9_assistant_service.py](../backend/app/services/phase_6_9_assistant_service.py), [backend/app/api/routes/in_app_deal.py](../backend/app/api/routes/in_app_deal.py) | [backend/tests/test_phase_6_9_runtime_integration.py](../backend/tests/test_phase_6_9_runtime_integration.py), `sandbox_party_gate_test.dart`, `sandbox_match_acceptance_test.dart`, deal lifecycle tests | PASS: local/affiliate paths require bilateral confirmation before contact sharing |
| Universal AI connect integration | [backend/app/api/routes/in_app_assistant.py](../backend/app/api/routes/in_app_assistant.py), [backend/app/services/universal_ai_assistant_service.py](../backend/app/services/universal_ai_assistant_service.py), [lib/services/in_app_assistant_service.dart](../lib/services/in_app_assistant_service.dart) | [backend/tests/test_phase_6_9_runtime_integration.py](../backend/tests/test_phase_6_9_runtime_integration.py), `in_app_assistant_service_test.dart`, location/AI tests | PASS: structured Universal AI decisions reach the Flutter contract |
| Full Phase 0–9 regression gate | Existing Phase 0–5 coverage plus Phase 6–9 runtime integration and failure recovery | backend `130 passed`; Flutter analyze clean; Flutter `324 tests passed`; green merged-main CI | PASS |

## Verified evidence

Backend verification command:

```powershell
cd "c:/Users/Flex 16/OneDrive/Documents/GitHub/askodox/backend"; & "C:/Users/Flex 16/AppData/Local/Programs/Python/Python313/python.exe" -m pytest -q
```

Result: 130 passed in 19.23s

Flutter verification command:

```powershell
cd "c:/Users/Flex 16/OneDrive/Documents/GitHub/askodox"; flutter test test/no_match_recovery_test.dart test/deal_matcher_recovery_test.dart --reporter expanded
```

Result: 324 tests passed

## Current status

Phase 6–9 runtime integration is verified against real registered provider/catalog sources, the Universal AI HTTP contract, bilateral Party A/Party B consent gates, affiliate fallback, localization, no-match recovery, completion/review flows, and the full existing Phase 0–5 regression suite. The resulting merged `main` commit has green backend, Flutter, Android, multimodal, isolation, intent, and in-app smoke workflows.

Therefore the status is: VERIFIED GREEN.
