# ASKODOX — database audit (Brain Phase Zero audit, 2026-11-10)

## Facts
- **Engine: SQLite only.** No Postgres, SQLAlchemy or Alembic in `requirements.txt`. Path from
  `PODX_DATABASE_PATH` under the Railway volume (`core/settings.py`).
- **284 distinct tables** across 119 files. Largest families: `pos_*` 51, `pf_*` 17, `universal_*` 13,
  `growth_*` 11, `video_*` 8, `partner_*` 7.
- **Migrations:** `CREATE TABLE IF NOT EXISTS` + "add column if missing" lists (e.g. `pos_store.MIGRATIONS`). Not
  versioned; no down-migrations.
- **Integrity:** 0 foreign keys, 135 indexes, no `PRAGMA foreign_keys` / WAL setting found.
- **Staff-editable data** lives in schema resources (`platform_schema.py`) stored as JSON rows with status,
  history and permissions -- this is the project's own convention for configurable knowledge.
- **Events:** `pf_events` (typed vocabulary in `platform_repository.EVENTS`), rolled up after
  `ASKODOX_EVENT_RETENTION_DAYS` (default 90).
- **Backup:** owner-only, on demand, encrypted, test-restored, link expires in 30 minutes. NOT scheduled.
- **Files** (videos, staff uploads) sit beside the DB on the same volume.

## Risks
1. One volume holds the only copy of the data, with no scheduled backup.
2. One process only: SQLite + in-memory OTPs / rate limits / caches cannot run on two servers.
3. No foreign keys: orphan rows are possible; account deletion finds user tables by column-name matching.

## How the Brain spec's 14 tables map to this project

The spec assumes Postgres, JSONB and foreign keys. Adapted to what exists:

| Spec entity | Decision | Where |
|---|---|---|
| brain_sessions | NOT added -- a conversation already exists (app snapshots + `/api/me/conversations`); no duplicate | — |
| brain_execution_logs + brain_module_results + token_usage_metrics | ONE new table `brain_runs` (turn id, mode, modules used, model, tokens in / out, latency, cost estimate, flags). No message text, no reasoning, no user identity beyond a hash | new |
| psychology_knowledge + psychology_evidence | ONE schema resource `psychology_knowledge` (staff-editable, status DRAFT / REVIEWED / LIVE, evidence grade A-D, references as a field) | schema resource |
| user_feedback | exists: `answer_corrections` (PR #299) + `feedback_reports` | reuse |
| response_evaluations + regression_test_results | ONE new table `brain_eval_results` (case id, prompt / model version, scores, pass / fail) | new |
| model_registry + model_routing_rules | ONE schema resource `model_registry` | schema resource |
| prompt_versions | ONE new table `brain_prompt_versions` (name, version, hash, text, status, created by) | new |
| knowledge_update_logs | covered by schema-resource history (every edit is already logged) | reuse |
| safety_events | `pf_events` with new event types (`safety_flag`), counts only | reuse |

Rules kept from the spec: no hidden reasoning stored; no inferred psychological profile stored; additive
changes only (new tables / new nullable columns), so rollback = stop using them (SQLite has no cheap down-migration).

## Recommended before the Brain grows the data
- Scheduled encrypted backup to an off-volume location (needs an owner decision on where: e.g. a storage bucket).
- `PRAGMA journal_mode=WAL` evaluation on staging (helps readers while a writer is active).
- Postgres is NOT recommended now: 119 files open SQLite directly; migration is a project of its own and is not
  needed for the Brain.
