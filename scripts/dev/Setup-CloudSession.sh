#!/bin/bash
# Setup-CloudSession.sh
#
# What a Claude Code cloud session needs from this repository that the cloud
# image does not have: today, the bot's libraries in python3.12, so the bot
# harnesses (tests/test-staff-commands.js, tests/test-help-report.js) run in
# a cloud thread the way they run on One and in the nightly (#3055).
#
# WHY IT IS RUN THIS WAY
#
# A cloud thread runs Claude Code from /home/user with the repositories added
# beside it and only the user's own settings read (--setting-sources user), so
# a SessionStart hook in this repository's .claude/settings.json never fires
# there (measured 21 Oct 2026). The cloud environment's setup script does run,
# once, when the environment's image is built, after the repositories are
# cloned and before any session; each session then starts from that image with
# the clone moved up to main. So the setup script runs this with --register,
# which installs now (kept in the image) and adds this script to the user's
# Claude settings as a SessionStart hook, which runs it again at every session
# start against the clone as it is then. A pin that moved since the image was
# built is installed there, and an unchanged one costs pip about a second.
#
# WHAT IT INSTALLS
#
# bot/requirements.txt exactly: every library pinned by version and sha256,
# wheels only, as Install-Bot.ps1 installs it on the VPS. Into python3.12,
# the Python the bot runs on (Install-Bot.ps1, bot/_pyguard.py): the image's
# python3 is 3.13, where those pins do not install. Into the user's own
# packages, because the system's python3.12 refuses a plain pip install
# (PEP 668). tests/bot-python.js finds it there.
#
# WHERE IT ACTS
#
# Only in a cloud session or a cloud image build. As the hook it does nothing
# unless CLAUDE_CODE_REMOTE is true, which Claude Code sets only in its cloud
# sessions. --register refuses on anything but Linux, so One, a developer's
# Windows PC and the Windows runners never get the hook. Nothing on those
# machines runs this script.
#
# Usage:
#   bash scripts/dev/Setup-CloudSession.sh --register   the setup script's line
#   bash scripts/dev/Setup-CloudSession.sh              what the hook runs
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
self="$repo/scripts/dev/Setup-CloudSession.sh"
register=0
case "${1:-}" in
  '') ;;
  --register) register=1 ;;
  *) echo "Setup-CloudSession.sh: unknown option $1 (the only one is --register)" >&2; exit 2 ;;
esac

if [ "$register" = 1 ]; then
  if [ "$(uname -s)" != Linux ]; then
    echo "Setup-CloudSession.sh --register is for the cloud environment's setup script, and this is not Linux ($(uname -s)); nothing was changed." >&2
    exit 2
  fi
  # The hook, in the user's own Claude settings (the only settings a cloud
  # thread reads). Every other key in the file is kept as it was, and a second
  # run adds nothing. The command checks the script is there first: an
  # environment whose image holds the clone but whose session does not has
  # nothing to install.
  settings="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
  mkdir -p "$(dirname "$settings")"
  command="test ! -f '$self' || bash '$self'"
  python3 -I - "$settings" "$command" <<'PY'
import json, os, sys
path, command = sys.argv[1], sys.argv[2]
data = {}
if os.path.exists(path):
    with open(path, encoding='utf-8') as f:
        text = f.read()
    if text.strip():
        data = json.loads(text)
groups = data.setdefault('hooks', {}).setdefault('SessionStart', [])
have = any(h.get('command') == command for g in groups for h in g.get('hooks', []))
if not have:
    groups.append({'hooks': [{'type': 'command', 'command': command}]})
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(data, f, indent=2)
        f.write('\n')
print(('already in ' if have else 'added to ') + path + ': the SessionStart hook ' + command)
PY
elif [ "${CLAUDE_CODE_REMOTE:-}" != true ]; then
  exit 0
fi

if ! command -v python3.12 >/dev/null; then
  echo "Setup-CloudSession.sh: no python3.12 here, so the bot's libraries were not installed and the bot harnesses will say so." >&2
  exit 1
fi
# pip's own output only when it fails, so a session that starts with
# everything in place says one line.
if ! out="$(python3.12 -m pip install --user --break-system-packages --require-hashes --only-binary :all: \
    --disable-pip-version-check --root-user-action=ignore --no-input --quiet -r "$repo/bot/requirements.txt" 2>&1)"; then
  printf '%s\n' "$out" >&2
  echo "Setup-CloudSession.sh: pip could not install bot/requirements.txt into python3.12 (above), so the bot harnesses will say no Python loads the bot." >&2
  exit 1
fi
echo "The bot's libraries are in python3.12, at the versions and hashes in bot/requirements.txt."
