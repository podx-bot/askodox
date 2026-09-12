# ASKODOX Continuity Lock

Status: LOCKED
Date: 2026-09-12

## Single source of development truth
- The only active development repository is `podx-bot/askodox`.
- Continue future ASKODOX development from the latest verified state in this repository.
- Do not switch development to PODX AI CONNECT, V2, Daxodex, or other historical repositories.
- Historical repositories may be used only as reference or as a source for one-time migration of missing code/features into ASKODOX.
- Do not delete historical repositories until required code/features have been audited and safely consolidated.

## Continuity rule for every future chat/session
Before implementing, fixing, reporting status, or resuming work:
1. Read `docs/ASKODOX_MASTER_DEVELOPMENT_STATE.md`.
2. Read this continuity lock.
3. Check recent GitHub commits and CI/results in `podx-bot/askodox`.
4. Continue from the latest verified checkpoint instead of rebuilding or restarting completed work.
5. Check prior locked product decisions before changing architecture, UI, matching, flows, naming, or tests.

## Decision persistence rule
- Every meaningful owner requirement, correction, complaint, rejection, approval, architecture decision, and verified completion must be preserved in the GitHub master state or an explicitly linked locked document.
- Do not depend on chat history alone.
- Do not ask the owner to repeat a decision that is already present in the project source of truth.
- When a new instruction conflicts with an earlier lock, identify the conflict and preserve the newest explicit owner correction as the new source of truth.
- After each meaningful verified development block, record the commit/checkpoint and next target so a new chat can resume immediately.

## Status reporting rule
- Never report active work, a commit, CI success, release, APK readiness, or SPRINT COMPLETE unless it is actually verified from the active ASKODOX repository or its verified build/test evidence.
- `IN PROGRESS` means there is an identified unfinished target; it does not imply background coding is occurring when no verified execution is happening.
- Mark a feature GREEN only after implementation, integration, testing, and verification.

## Owner intent
The owner should not need to re-explain the project on every new chat. The system must retrieve and review the saved ASKODOX project state first, then continue from that state with one clear repository and one continuous history.
