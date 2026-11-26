#!/usr/bin/env bash
# PreToolUse hook (Bash): runs only for `git commit`. Exit 2 = block the commit.
# Fast checks only; the full suites still run in CI.
set -u
cmd=$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("tool_input",{}).get("command",""))' 2>/dev/null)
case "$cmd" in *"git commit"*) ;; *) exit 0 ;; esac

root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
cd "$root" || exit 0
staged=$(git diff --cached --name-only --diff-filter=ACM)
[ -z "$staged" ] && exit 0
fail=0

# 1. Never commit secrets / generated Firebase config.
bad=$(echo "$staged" | grep -E '(^|/)(\.env|google-services\.json|.*\.jks|.*\.keystore|key\.properties)$' | grep -v '\.env\.example$')
if [ -n "$bad" ]; then
  echo "BLOCKED: secret/generated files are staged:" >&2; echo "$bad" >&2; fail=1
fi

# 2. Python syntax of staged backend files.
for f in $(echo "$staged" | grep -E '^backend/.*\.py$'); do
  python3 -m py_compile "$f" 2>&1 >/dev/null || { echo "BLOCKED: syntax error in $f" >&2; fail=1; }
done

# 3. Matching backend test file for each staged backend module (if one exists).
tests=""
for f in $(echo "$staged" | grep -E '^backend/app/.*\.py$'); do
  t="backend/tests/test_$(basename "$f")"
  [ -f "$t" ] && tests="$tests $t"
done
if [ -n "$tests" ] && python3 -c 'import pytest' 2>/dev/null; then
  (cd backend && python3 -m pytest -x -q $(for t in $tests; do echo "${t#backend/}"; done) >/tmp/guard_pytest.log 2>&1) \
    || { echo "BLOCKED: tests failed (tail of log):" >&2; tail -15 /tmp/guard_pytest.log >&2; fail=1; }
fi

[ "$fail" -eq 1 ] && exit 2
exit 0
