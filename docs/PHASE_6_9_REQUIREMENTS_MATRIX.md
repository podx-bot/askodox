# ASKODOX Phase 6–9 requirements matrix

Status: IN PROGRESS

This matrix reflects the current verified workspace state as of 2026-09-18. It is intentionally conservative: a requirement is only marked as implemented when it is both present in code and backed by a passing verification command.

| Requirement | Implemented location | Test | Result |
| --- | --- | --- | --- |
| Known user location persists without re-asking | [backend/app/services/universal_ai_assistant_service.py](../backend/app/services/universal_ai_assistant_service.py) | [backend/tests/test_universal_ai_assistant_location.py](../backend/tests/test_universal_ai_assistant_location.py) | PASS |
| WhatsApp location shares are redirected away from business flows | [backend/app/services/whatsapp_support_only_gate.py](../backend/app/services/whatsapp_support_only_gate.py) | [backend/tests/test_whatsapp_support_only_gate.py](../backend/tests/test_whatsapp_support_only_gate.py) | PASS |
| General WhatsApp support-only gate remains intact | [backend/app/services/whatsapp_support_only_gate.py](../backend/app/services/whatsapp_support_only_gate.py) | [backend/tests/test_whatsapp_support_only_gate.py](../backend/tests/test_whatsapp_support_only_gate.py) | PASS |
| No-match fallback and affiliate-aware recovery path | [lib/features/deal_brain/domain/no_match_recovery.dart](../lib/features/deal_brain/domain/no_match_recovery.dart) | [test/no_match_recovery_test.dart](../test/no_match_recovery_test.dart), [test/deal_matcher_recovery_test.dart](../test/deal_matcher_recovery_test.dart) | PASS |
| Local-first + online/affiliate fallback logic in app domain | [lib/features/deal_brain/domain/no_match_recovery.dart](../lib/features/deal_brain/domain/no_match_recovery.dart) | [test/no_match_recovery_test.dart](../test/no_match_recovery_test.dart) | PASS |
| Dynamic Party A / Party B acceptance gate | [lib/features/deals/domain/sandbox_investor_flow_coordinator.dart](../lib/features/deals/domain/sandbox_investor_flow_coordinator.dart) | [test/sandbox_party_gate_test.dart](../test/sandbox_party_gate_test.dart) | PASS |
| Seller/provider trust and compliance fields | [lib/features/seller](../lib/features/seller) | project tests for seller search and profile flows | partial/feature-branch based; not yet phase-verified as a cohesive Phase 6–9 runtime |
| Service decision assistant | No verified Phase 6 runtime branch or merged implementation found in the current workspace | No Phase 6-specific CI/PR evidence | NOT VERIFIED |
| Buyer decision assistant | No verified Phase 7 runtime branch or merged implementation found in the current workspace | No Phase 7-specific CI/PR evidence | NOT VERIFIED |
| Party A ↔ AI ↔ Party B orchestration | No verified Phase 8 runtime branch or merged implementation found in the current workspace | No Phase 8-specific CI/PR evidence | NOT VERIFIED |
| Universal AI connect integration | No verified Phase 9 runtime branch or merged implementation found in the current workspace | No Phase 9-specific CI/PR evidence | NOT VERIFIED |
| Full Phase 0–9 regression gate | Current work is on a feature branch and verified backend tests are green, but no phase-6 to phase-9 merged integration run is present | backend pytest, Flutter no-match tests | PARTIAL: green for targeted checks, not green for full Phase 0–9 completion |

## Verified evidence

Backend verification command:

```powershell
cd "c:/Users/Flex 16/OneDrive/Documents/GitHub/askodox/backend"; & "C:/Users/Flex 16/AppData/Local/Programs/Python/Python313/python.exe" -m pytest -q
```

Result: 19 passed in 3.32s

Flutter verification command:

```powershell
cd "c:/Users/Flex 16/OneDrive/Documents/GitHub/askodox"; flutter test test/no_match_recovery_test.dart test/deal_matcher_recovery_test.dart --reporter expanded
```

Result: 8 tests passed

## Current status

The repository is verified for the focused regressions above, but it is not yet verified as a complete Phase 6–9 production-ready release. The current branch is `fix/location-context-and-whatsapp-gate`, not a phase-specific `phase-6`, `phase-7`, `phase-8`, or `phase-9` branch. There is no evidence of merged PRs or green CI for the full master execution workflow described in the Phase 6–9 command.

Therefore the honest status remains: IN PROGRESS.
