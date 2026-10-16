# lunch-limits

A Claude Code status line that shows your plan usage, so you see the limit
coming before you hit it.

```
5h 23% · resets 3:40pm   week 41% · resets Mon 3am
```

## What it shows

- **5h** — your five-hour window: percent used, and when it resets.
- **week** — your seven-day window: percent used, and when it resets.

Details:

- Percents are whole numbers, rounded to the nearest.
- Reset times are your local clock time (`3am`, `3:40pm`). The weekday is added
  when the reset is more than 24 hours away (`Mon 3am`).
- The percent is colored: green under 50, yellow 50–79, red 80 and up.
- A window with no data prints `5h --` or `week --`. It never shows a made-up
  `0%`. A window whose reset time has already passed is stale, so it also
  reads as `--`.

It reads only `rate_limits.five_hour` and `rate_limits.seven_day` from the JSON
payload Claude Code sends on stdin — nothing else from that payload reaches the
output. No network calls, no files read, no credentials, no estimates or
projections. It always prints a line and always exits 0, so a bad payload can
never break your status line.

Works on a stock Mac (bash 3.2, BSD `date`) and on Linux (GNU `date`). Needs
`jq`; without it the line reads `limits: jq not found`.

## Install

```sh
./install.sh
```

This adds a `statusLine` entry to `~/.claude/settings.json`, backing the file up
first and leaving every other setting alone. Re-running it changes nothing. If
you already have a different status line configured, it is left in place and the
script tells you how to switch.

Then start a new Claude Code session. The line appears after the first reply.

To use it in this repo only, the checked-in `.claude/settings.json` already
points at `statusline.sh`.

## Uninstall

```sh
./install.sh --uninstall
```

Removes only this `statusLine` entry, after another backup. If your
`statusLine` points at something else, it is left untouched.

## What it can't show

- **Model-specific limits.** Some plans meter certain models separately — for
  example the weekly Fable limit on Max. Only the overall five-hour and
  seven-day windows are reported, so a model-specific limit can bite while this
  line still looks fine.
- **Nothing before the first reply.** `rate_limits` is absent until Claude Code
  has had one exchange with the API, so a fresh session reads `5h --   week --`.
- **Pro and Max plans only.** API-key and other billing arrangements don't
  report these windows.
- **Whole percents, as of the last reply.** The numbers come from the most
  recent API response, not live. Long turns move the real figure before the
  line catches up, and sub-percent changes are invisible.
- **Not everywhere.** Status lines don't render in `claude -p` or in the VS Code
  extension panel.

## Tests

```sh
./tests/run_tests.sh
```

Pipes 17 saved fixture payloads through `statusline.sh` and checks the exact
output, with `TZ=UTC` and a frozen clock so results don't depend on where or
when you run them. The `install.sh` tests use a throwaway `HOME` and never
touch your real `~/.claude`.
