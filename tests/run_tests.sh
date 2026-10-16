#!/bin/bash
# Tests for statusline.sh and install.sh.
#
# Everything is deterministic: TZ=UTC and a frozen clock (LUNCH_LIMITS_NOW).
# The install tests run against a throwaway HOME and never touch ~/.claude.
set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
FIX="$ROOT/tests/fixtures"
SL="$ROOT/statusline.sh"
INSTALL="$ROOT/install.sh"

export TZ=UTC
# Frozen "now" = Thu 2025-10-09 08:53:20 UTC
export LUNCH_LIMITS_NOW=1760000000

G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[31m'; Z=$'\033[0m'
DOT=$'\xc2\xb7'

PASS=0
FAIL=0

# check <fixture> <expected line>
check() {
  local fixture=$1 expected=$2 got status
  got=$("$SL" < "$FIX/$fixture")
  status=$?
  if [ "$status" -ne 0 ]; then
    FAIL=$((FAIL + 1))
    printf 'FAIL %-24s exited %d (must always be 0)\n' "$fixture" "$status"
    return
  fi
  if [ "$got" = "$expected" ]; then
    PASS=$((PASS + 1))
    printf 'ok   %-24s %s\n' "$fixture" "$(printf '%s' "$got" | cat -v)"
  else
    FAIL=$((FAIL + 1))
    printf 'FAIL %-24s\n  expected: %s\n  got:      %s\n' "$fixture" \
      "$(printf '%s' "$expected" | cat -v)" "$(printf '%s' "$got" | cat -v)"
  fi
}

# assert <description> <condition-result 0/1>
assert() {
  if [ "$2" -eq 0 ]; then
    PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"
  else
    FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$1"
  fi
}

echo "== statusline.sh =="

check both.json \
  "5h ${G}23%${Z} ${DOT} resets 3:40pm   week ${G}41%${Z} ${DOT} resets Mon 3am"

# 23.5 rounds to 24, 40.4 rounds to 40
check decimal.json \
  "5h ${G}24%${Z} ${DOT} resets 3:40pm   week ${G}40%${Z} ${DOT} resets Mon 3am"

# 0 is real data and must print as 0%, not as "--"
check zero.json \
  "5h ${G}0%${Z} ${DOT} resets 3:40pm   week ${G}0%${Z} ${DOT} resets Mon 3am"

check hundred.json \
  "5h ${R}100%${Z} ${DOT} resets 3:40pm   week ${R}100%${Z} ${DOT} resets Mon 3am"

check only_five_hour.json "5h ${G}12%${Z} ${DOT} resets 9:05am   week --"
check only_seven_day.json "5h --   week ${Y}67%${Z} ${DOT} resets Fri 12pm"

# fresh session: rate_limits only appears after the first reply
check no_rate_limits.json   "5h --   week --"
check rate_limits_null.json "5h --   week --"

# a window whose reset has already passed is stale, so it reads as missing
check reset_passed.json      "5h --   week ${G}41%${Z} ${DOT} resets Mon 3am"
check reset_passed_both.json "5h --   week --"

check malformed.json "5h --   week --"
check empty.json     "5h --   week --"

echo
echo "== color thresholds =="
check threshold_49.json \
  "5h ${G}49%${Z} ${DOT} resets 3:40pm   week ${G}49%${Z} ${DOT} resets Mon 3am"
check threshold_50.json \
  "5h ${Y}50%${Z} ${DOT} resets 3:40pm   week ${Y}50%${Z} ${DOT} resets Mon 3am"
check threshold_79.json \
  "5h ${Y}79%${Z} ${DOT} resets 3:40pm   week ${Y}79%${Z} ${DOT} resets Mon 3am"
check threshold_80.json \
  "5h ${R}80%${Z} ${DOT} resets 3:40pm   week ${R}80%${Z} ${DOT} resets Mon 3am"

echo
echo "== nothing else from the payload leaks =="
check full_payload.json \
  "5h ${G}23%${Z} ${DOT} resets 3:40pm   week ${G}41%${Z} ${DOT} resets Mon 3am"
FULL_OUT=$("$SL" < "$FIX/full_payload.json")
case $FULL_OUT in
  *LEAK*|*12.34*|*777*|*888*|*123456*) assert "no payload field leaks into the output" 1 ;;
  *) assert "no payload field leaks into the output" 0 ;;
esac

echo
echo "== robustness =="
printf 'garbage' | "$SL" >/dev/null 2>&1
assert "exits 0 on garbage input" $?
"$SL" < /dev/null >/dev/null 2>&1
assert "exits 0 on empty input" $?
LINES=$("$SL" < "$FIX/both.json" | wc -l | tr -d ' ')
[ "$LINES" = "1" ]; assert "prints exactly one line" $?

# jq missing -> a message, still exit 0
JQLESS=$(PATH=/nonexistent "$SL" < "$FIX/both.json" 2>/dev/null)
[ "$JQLESS" = "limits: jq not found" ]; assert "reports a missing jq" $?
PATH=/nonexistent "$SL" < "$FIX/both.json" >/dev/null 2>&1
assert "exits 0 when jq is missing" $?

echo
echo "== install.sh (throwaway HOME) =="
FAKE=$(mktemp -d "${TMPDIR:-/tmp}/lunch-limits-test.XXXXXX")
trap 'rm -rf "$FAKE"' EXIT 0
S="$FAKE/.claude/settings.json"

mkdir -p "$FAKE/.claude"
cat > "$S" <<'EOF'
{
  "theme": "dark",
  "permissions": {"allow": ["Bash(ls:*)"]}
}
EOF

run_install() { env HOME="$FAKE" CLAUDE_CONFIG_DIR="$FAKE/.claude" "$INSTALL" "$@"; }

OUT1=$(run_install 2>&1); assert "install exits 0" $?
[ "$(jq -r '.statusLine.type' "$S")" = "command" ]
assert "statusLine.type is command" $?
[ "$(jq -r '.statusLine.command' "$S")" = "$ROOT/statusline.sh" ]
assert "statusLine.command points at statusline.sh" $?
[ "$(jq -r '.theme' "$S")" = "dark" ]
assert "existing settings are kept" $?
[ "$(jq -r '.permissions.allow[0]' "$S")" = "Bash(ls:*)" ]
assert "nested existing settings are kept" $?
BAKS=$(ls "$FAKE/.claude" | grep -c 'settings.json.bak')
[ "$BAKS" -ge 1 ]; assert "a backup was made" $?

AFTER1=$(cat "$S")
OUT2=$(run_install 2>&1)
[ "$(cat "$S")" = "$AFTER1" ]; assert "re-running adds nothing" $?
case $OUT2 in *"already installed"*) assert "re-run says already installed" 0 ;;
  *) assert "re-run says already installed" 1 ;; esac
[ "$(ls "$FAKE/.claude" | grep -c 'settings.json.bak')" = "$BAKS" ]
assert "re-run makes no extra backup" $?

run_install --uninstall >/dev/null 2>&1; assert "uninstall exits 0" $?
[ "$(jq -r 'has("statusLine")' "$S")" = "false" ]
assert "uninstall removes the statusLine entry" $?
[ "$(jq -r '.theme' "$S")" = "dark" ]
assert "uninstall leaves other settings intact" $?
[ "$(jq -r '.permissions.allow[0]' "$S")" = "Bash(ls:*)" ]
assert "uninstall leaves nested settings intact" $?

# a foreign statusLine is left alone
jq '.statusLine = {"type":"command","command":"/usr/local/bin/other-line.sh"}' "$S" > "$S.new" && mv "$S.new" "$S"
OUT3=$(run_install 2>&1)
[ "$(jq -r '.statusLine.command' "$S")" = "/usr/local/bin/other-line.sh" ]
assert "a different statusLine is left alone" $?
case $OUT3 in *"to switch to lunch-limits"*) assert "it says how to switch" 0 ;;
  *) assert "it says how to switch" 1 ;; esac
run_install --uninstall >/dev/null 2>&1
[ "$(jq -r '.statusLine.command' "$S")" = "/usr/local/bin/other-line.sh" ]
assert "uninstall does not remove someone else's statusLine" $?

# a fresh HOME with no settings file at all
FRESH="$FAKE/fresh"
mkdir -p "$FRESH"
env HOME="$FRESH" CLAUDE_CONFIG_DIR="$FRESH/.claude" "$INSTALL" >/dev/null 2>&1
[ "$(jq -r '.statusLine.command' "$FRESH/.claude/settings.json")" = "$ROOT/statusline.sh" ]
assert "installs into a fresh HOME with no settings.json" $?
[ "$(jq -r 'keys | length' "$FRESH/.claude/settings.json")" = "1" ]
assert "a fresh settings.json contains only statusLine" $?

echo
echo "-----------------------------"
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
echo "all good"
