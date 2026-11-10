# ASKODOX — test baseline (Brain Phase Zero audit, 2026-11-10)

## Backend (run in the audit session)
- Full suite on branch `claude/askodox-phase1-polish-1110` (PR #299): **1504 passed, 0 failed** (pytest, 2 min 55 s).
- 178 test files. Skips: ffmpeg-dependent tests, a browser test, one app-sources test. No xfail.
- **Pre-existing order-dependent failure (not caused by new work):** running only the files that mention result
  sections makes 3 tests in `test_result_contract_combinations.py` fail (`test_01_local_only`, `test_15_...`,
  `test_diagnostics_...`), on `main` as well. They pass in the full run and alone -> shared state between test
  files. To be fixed before Brain tests are added.
- **Gap: no GitHub workflow runs the full backend suite.** Only subsets run (feature registry, result contract,
  smokes). The full run happens only when someone runs it by hand.

## Flutter (from CI; the audit session has no Flutter SDK)
- 192 test files, about 1,165 tests; `flutter analyze` is fatal on infos in `android-apk.yml`.
- On PR #299 head `cff7299`: askodox-ci, build-apk, registry, combinations, docker-smoke, multimodal: green.
- Env-gated skips (render / video proof) and one Phase-1 skip.

## Emulator checks
- `sms-consent-e2e` and `otp-autofill-e2e` (full-app, 3 shards) run only when Kotlin / auth paths change.
- **Known flaky:** "no Android consent prompt" / "code not delivered" fail at random and pass on re-run
  (seen 2026-11-09 and 2026-11-10; different shards each time). A re-run policy is in use; the cause is not fixed.

## Real phone
- Phone verified: OTP SMS consent path, payment voice alert with the app closed (APK 1374), UPI QR photo reader
  (APK 1379), location naming. Everything else is CODE READY only.
- Work Mode sound, the Profile changes, the wrong-answer button: not phone verified (APK test-1449 installed by the owner).

## Answer quality
- There is NO baseline for answer quality: no fixed question set, no scores. `conversation-trace.yml` replays a
  few conversations against staging and prints the turns, but nothing is graded.

## Baseline rule for the Brain work
Any Brain PR must show: full backend suite count (>= 1504, 0 failed), Flutter CI green, and -- once it exists --
the benchmark comparison against the current brain. A skipped or failing required test is reported as such.
