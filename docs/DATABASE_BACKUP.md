# Database backup and restore (owner only)

Production keeps its SQLite database on the Railway volume
`podx-ai-connect-volume` (`/data`). The Hobby plan allows no Railway volume
backups, so ASKODOX has its own owner-only export.

## Take a backup (browser, no terminal)
1. Open `https://admin.askodox.com/admin/backup`.
2. Enter the owner admin key (`ADMIN_SEED_KEY`) and a NEW backup passphrase
   (16+ characters) twice. Save the passphrase in a password manager first:
   it is never stored anywhere, and without it the backup cannot be opened.
3. Press **Create verified backup**. The server:
   - copies the database through SQLite's online backup API from a
     READ-ONLY connection (the live database is never written);
   - checks the copy (`PRAGMA integrity_check`, per-table row counts);
   - encrypts it (AES-256-GCM, key from scrypt(passphrase), authenticated
     4 MiB chunks -- tampering or truncation is detected);
   - decrypts it again into a SEPARATE temporary database and requires
     integrity `ok`, identical row counts and an identical SHA-256;
   - deletes every plaintext copy; only the encrypted file remains, in a
     private temp directory, for 30 minutes.
4. The page shows the manifest (table names + row counts, hashes, restore
   test result -- never row contents). Press **Download** once (the link
   then stops working), compare the file size and `encrypted_sha256`, and
   store the file in a private place (e.g. your Google Drive).

Guards: owner key only (staff tokens / sessions are refused, even with every
permission); 3 exports per hour; every export / download is in the audit log
(hashes and counts only); request logs carry only method / path / status.

## Restore test / restore
Never restore over the live file directly.
1. Decrypt into a new file and verify it:
   `ASKODOX_BACKUP_PASSPHRASE=... python -I backend/tools/askodox_backup_restore.py askodox-db-<id>.sqlite.enc restored.db --expect-sha256 <database_sha256>`
   It prints table names + row counts and `PASS` only when integrity is `ok`
   and the hash matches; it refuses to overwrite an existing file.
2. To put it into production (owner approval required): stop traffic /
   scale the service to 0, copy `restored.db` onto the volume next to the
   live database, keep the old file renamed (`.before-restore`), switch
   `PODX_DATABASE_PATH` (or rename) to the restored file, start the
   service, check `/health`. Keep the old file until the restore is
   confirmed.

## Before a release
Take a backup as above, record `backup_id`, `encrypted_sha256`,
`database_sha256` and the row total in the release notes, then merge.
