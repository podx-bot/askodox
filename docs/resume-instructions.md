# Resume instructions

Claude cannot restart itself when a usage limit resets. To continue, open a new Claude session with access to
`podx-bot/askodox` and send exactly:

> Continue ASKODOX from docs/implementation-status.md on branch claude/navigator-ux-p0 (PR #182). Do the next
> pending step, keep tests strict, update docs/implementation-status.md and docs/qa-evidence.md, do not merge or deploy.

Checks before working: `git fetch origin && git checkout claude/navigator-ux-p0 && git pull`;
backend tests `cd backend && pip install -r requirements.txt pytest && python -m pytest -q tests`;
Flutter tests run in GitHub Actions (`Flutter CI`) on push; private APK = `Android Live Build` (workflow_dispatch,
publish_release=false, publish_update_channel=false) then `.github/phone-test-link.json` for a direct link.
