#!/bin/bash
# lunch-limits -- Claude Code status line showing plan rate limit usage.
#
# Reads the status line JSON payload on stdin and prints one line, e.g.
#   5h 23% · resets 3:40pm   week 41% · resets Mon 3am
#
# Only rate_limits.five_hour and rate_limits.seven_day are read. No network,
# no files, no credentials. Always prints a line and always exits 0.

SEP=$'\xc2\xb7'          # ·
ESC=$'\033'
RESET="${ESC}[0m"
GREEN="${ESC}[32m"
YELLOW="${ESC}[33m"
RED="${ESC}[31m"

if ! command -v jq >/dev/null 2>&1; then
  printf 'limits: jq not found\n'
  exit 0
fi

# BSD date takes -r <epoch>; GNU date takes -d @<epoch>.
if date -r 1 +%s >/dev/null 2>&1; then
  DATE_MODE=bsd
else
  DATE_MODE=gnu
fi

JQ_PROG='
def asnum:
  if type == "number" then .
  elif type == "string" then (tonumber? // null)
  else null end;
def win:
  if type == "object" then
    ((.used_percentage | asnum) as $p
     | (.resets_at | asnum) as $r
     | if $p == null or $r == null then "-\t-"
       else "\(($p | if . < 0 then 0 elif . > 100 then 100 else . end) + 0.5 | floor)\t\($r | floor)"
       end)
  else "-\t-" end;
(fromjson? // null) as $payload
| (if ($payload | type) == "object" then $payload.rate_limits else null end) as $rl
| (if ($rl | type) == "object" then $rl else {} end) as $rl
| (($rl.five_hour | win) + "\t" + ($rl.seven_day | win))
'

PARSED=$(jq -Rsr "$JQ_PROG" 2>/dev/null) || PARSED=""
[ -n "$PARSED" ] || PARSED=$'-\t-\t-\t-'

# Split the four tab-separated fields without subshells.
rest=$PARSED
H_PCT=${rest%%$'\t'*}; rest=${rest#*$'\t'}
H_AT=${rest%%$'\t'*};  rest=${rest#*$'\t'}
W_PCT=${rest%%$'\t'*}; rest=${rest#*$'\t'}
W_AT=$rest

# LUNCH_LIMITS_NOW is a test seam so fixtures can assert exact output.
NOW=${LUNCH_LIMITS_NOW:-$(date +%s)}
case $NOW in ''|*[!0-9]*) NOW=$(date +%s) ;; esac

# color_for <percent> -> ANSI color
color_for() {
  if [ "$1" -lt 50 ]; then
    printf '%s' "$GREEN"
  elif [ "$1" -lt 80 ]; then
    printf '%s' "$YELLOW"
  else
    printf '%s' "$RED"
  fi
}

# fmt_time <epoch> -> "3:40pm" or "Mon 3am" when more than 24h out
fmt_time() {
  local e=$1 raw h m ap wd rest
  if [ "$DATE_MODE" = bsd ]; then
    raw=$(date -r "$e" '+%I:%M:%p:%a' 2>/dev/null)
  else
    raw=$(date -d "@$e" '+%I:%M:%p:%a' 2>/dev/null)
  fi
  [ -n "$raw" ] || return 1

  h=${raw%%:*};   rest=${raw#*:}
  m=${rest%%:*};  rest=${rest#*:}
  ap=${rest%%:*}; wd=${rest#*:}

  h=${h#0}
  [ -n "$h" ] || h=12
  case $ap in
    AM|am) ap=am ;;
    PM|pm) ap=pm ;;
  esac

  local t
  if [ "$m" = "00" ]; then
    t="${h}${ap}"
  else
    t="${h}:${m}${ap}"
  fi
  if [ $((e - NOW)) -gt 86400 ]; then
    t="${wd} ${t}"
  fi
  printf '%s' "$t"
}

# segment <label> <percent> <resets_at>
segment() {
  local label=$1 pct=$2 at=$3

  case $pct in
    ''|*[!0-9]*) printf '%s --' "$label"; return ;;
  esac
  case $at in
    ''|*[!0-9]*) printf '%s --' "$label"; return ;;
  esac
  # A window whose reset has already passed is stale -- treat it as missing.
  if [ "$at" -le "$NOW" ]; then
    printf '%s --' "$label"
    return
  fi

  local col when
  col=$(color_for "$pct")
  if when=$(fmt_time "$at"); then
    printf '%s %s%s%%%s %s resets %s' "$label" "$col" "$pct" "$RESET" "$SEP" "$when"
  else
    printf '%s %s%s%%%s' "$label" "$col" "$pct" "$RESET"
  fi
}

printf '%s   %s\n' "$(segment 5h "$H_PCT" "$H_AT")" "$(segment week "$W_PCT" "$W_AT")"
exit 0
