#!/usr/bin/env bash
# Cloud Agent bootstrap for Thornswood. Idempotent: it may run again on a
# cached or partly-prepared machine, so every step checks before it acts.
#
# The Windows half of this repo (the WPF launcher, the .NET Framework csc, the
# engine submodule's Visual Studio build, and the Windows-path .ps1 harnesses)
# cannot run here. What this prepares is everything that does: node for the
# game scripts, the site and the voice service and their JavaScript harnesses;
# PowerShell 7 so every script parses and the cross-platform harnesses run;
# and Python with the bot's own libraries for the Discord bot and its tests.
set -euo pipefail

cd "$(dirname "$0")/.."

# PowerShell 7, from Microsoft's package repo. Added only once; skipped whole
# on a machine that already has pwsh.
if ! command -v pwsh >/dev/null 2>&1; then
  if [ ! -f /etc/apt/sources.list.d/microsoft-prod.list ]; then
    tmp="$(mktemp -d)"
    curl -sSL -o "$tmp/packages-microsoft-prod.deb" \
      "https://packages.microsoft.com/config/ubuntu/24.04/packages-microsoft-prod.deb"
    sudo dpkg -i "$tmp/packages-microsoft-prod.deb"
    rm -rf "$tmp"
  fi
fi

sudo apt-get update -qq
sudo apt-get install -y -qq powershell python3-venv python-is-python3

# The Discord bot and its harnesses import discord.py for real, so they need
# the exact versions requirements.txt pins, the same file Install-Bot.ps1 uses
# on the VPS. They go in a repo-local venv (.venv, kept out of git) so nothing
# touches the machine's own Python.
python3 -m venv .venv
.venv/bin/python -m pip install --quiet --disable-pip-version-check -r bot/requirements.txt

echo "Thornswood ready: $(node --version), $(pwsh --version), $(python3 --version)"
