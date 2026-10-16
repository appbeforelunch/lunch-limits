#!/bin/bash
# Install or remove the lunch-limits status line in ~/.claude/settings.json.
#
#   ./install.sh              install
#   ./install.sh --uninstall  remove only our statusLine entry
#
# Other settings are never touched, and the file is backed up before writing.
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
CMD="$HERE/statusline.sh"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SETTINGS="$CLAUDE_DIR/settings.json"

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is required (brew install jq)" >&2
  exit 1
fi

MODE=install
case "${1:-}" in
  --uninstall|-u) MODE=uninstall ;;
  --help|-h) sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  '') ;;
  *) echo "error: unknown option $1 (try --help)" >&2; exit 1 ;;
esac

backup() {
  local b="$SETTINGS.bak.$(date +%Y%m%d%H%M%S)"
  cp "$SETTINGS" "$b" || exit 1
  echo "backed up $SETTINGS -> $b"
}

# Read the current statusLine command, or empty if there is none.
current() {
  [ -f "$SETTINGS" ] || return 0
  jq -r 'if (.statusLine.command | type) == "string" then .statusLine.command else "" end' \
     "$SETTINGS" 2>/dev/null
}

write() {
  # all args are passed through to jq (filter last), input is the settings file
  local tmp="$SETTINGS.tmp.$$"
  if [ -f "$SETTINGS" ]; then
    jq "$@" "$SETTINGS" > "$tmp" || {
      rm -f "$tmp"
      echo "error: $SETTINGS is not valid JSON, refusing to write" >&2
      exit 1
    }
  else
    echo '{}' | jq "$@" > "$tmp" || { rm -f "$tmp"; exit 1; }
  fi
  mv "$tmp" "$SETTINGS"
}

EXISTING=$(current)

if [ "$MODE" = uninstall ]; then
  if [ ! -f "$SETTINGS" ]; then
    echo "nothing to do: $SETTINGS does not exist"
    exit 0
  fi
  if [ "$EXISTING" != "$CMD" ]; then
    if [ -z "$EXISTING" ]; then
      echo "nothing to do: no statusLine entry in $SETTINGS"
    else
      echo "left alone: statusLine points at something else:"
      echo "  $EXISTING"
    fi
    exit 0
  fi
  backup
  write 'del(.statusLine)'
  echo "removed the lunch-limits statusLine from $SETTINGS"
  exit 0
fi

if [ ! -x "$CMD" ]; then
  echo "error: $CMD is missing or not executable" >&2
  exit 1
fi

if [ "$EXISTING" = "$CMD" ]; then
  echo "already installed: $SETTINGS"
  exit 0
fi

if [ -n "$EXISTING" ]; then
  echo "a different statusLine is already configured, leaving it alone:"
  echo "  $EXISTING"
  echo
  echo "to switch to lunch-limits, set statusLine.command in $SETTINGS to:"
  echo "  $CMD"
  echo "or remove the existing entry and re-run ./install.sh"
  exit 0
fi

mkdir -p "$CLAUDE_DIR"
[ -f "$SETTINGS" ] && backup
write --arg cmd "$CMD" '.statusLine = {"type": "command", "command": $cmd}'
echo "installed the lunch-limits statusLine in $SETTINGS"
echo "it appears after the first reply of a session."
