# ASKODOX release and rollback procedure

Applies to every merge into `main` (production backend `podx-ai-connect`,
Railway project "lavish-perfection", environment `production`).

## What a merge changes
- Railway builds `main` and replaces the running production deployment.
- The Android Live Build builds, signs and verifies an APK and uploads it as
  the private workflow artifact `askodox-phone-test-<build>`. It does NOT
  touch the in-app update channel (`askodox-latest`); installed phones see no
  update until the owner dispatches the workflow on `main` with
  `publish_update_channel=true` after real-phone acceptance.

## Before merging
1. CI green on the PR's latest commit; PR mergeable.
2. Note the current production deployment id (Railway, service
   `podx-ai-connect`, environment `production`) -- the rollback target.
3. Database backup of the production volume (`podx-ai-connect-volume`,
   mounted at `/data`, SQLite). Railway volume backups need a plan that
   allows them (Hobby allows none), so use the owner-only encrypted export
   at `/admin/backup` (docs/DATABASE_BACKUP.md): it must report
   `restore_test.verified: true`. Record `backup_id`, `encrypted_sha256`,
   `database_sha256` and the row total.
4. Migrations must be additive only (`CREATE TABLE IF NOT EXISTS`, new
   columns with defaults). Then old code keeps working on the new database
   and a code rollback needs no data restore.

## Rollback (backend)
1. Railway -> `podx-ai-connect` -> production -> Deployments -> the
   deployment noted in step 2 -> Rollback (or Redeploy). Takes ~1-2 min.
2. Check `/health` answers 200 with the old commit, and the logs show
   "Application startup complete".
3. Then revert the merge on `main` (a revert commit, never a force push) so
   the next deploy does not bring the change back.
4. Restore the database from the backup (docs/DATABASE_BACKUP.md) ONLY if data was corrupted;
   additive tables written by the new code are ignored by the old code.

## Rollback (app)
- Nothing reached phones unless the update channel was published. If it
  was: publish the previous good build again with a HIGHER build number
  (Android refuses lower versionCodes); never re-point the channel at an
  older versionCode.
