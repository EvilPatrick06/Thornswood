#!/bin/bash
# Thornswood cloud environment setup. Runs once when a cloud session starts.
# Stops at the first failure so a broken install shows instead of hiding.
#
# This file is the text of the "Thornswood" cloud environment's Setup script
# (Project settings > Environment > Cloud environment > the gear beside
# Thornswood). The environment does not read it from here: the whole text is
# pasted there, so a change to this file reaches new sessions only when the
# new text is pasted in again. It is kept here to be reviewed and checked
# (tests/test-3055-cloud-session.js) with the scripts it runs.
#
# Every session of the environment runs it, the project chat too, and a
# session can have no repository attached (#3085). So everything above the
# last block needs nothing from a clone, and the last block, the one step that
# comes from the Thornswood clone, runs only when the clone is there.
set -euo pipefail

# PowerShell 7, for the repo's Check-*.ps1 scripts and the PowerShell harnesses.
if ! command -v pwsh >/dev/null; then
  curl -sSLo /tmp/pmp.deb https://packages.microsoft.com/config/ubuntu/24.04/packages-microsoft-prod.deb
  dpkg -i /tmp/pmp.deb
  rm -f /tmp/pmp.deb
  apt-get update
  apt-get install -y powershell
fi

# Lighthouse (speed, accessibility through axe, SEO, best practices) and
# linkinator (broken links), pinned.
npm install -g lighthouse@13.5.0 linkinator@8.1.0

# osv-scanner, for dependency advisories across npm, NuGet and Python (the
# weekly review's Security area). Google's own release binary, pinned by
# version and by the SHA-256 that release's osv-scanner_SHA256SUMS lists, so
# nothing is compiled and no Go toolchain or modules are downloaded.
# sha256sum -c fails the script on a mismatch. To move to a new version,
# change both lines from that release's osv-scanner_SHA256SUMS file.
OSV_VERSION=v2.6.0
OSV_SHA256=ca69b3d3cd08f889a49dc0a383122f71cc528b83803671df5fd874d97485b108
curl -fsSLo /tmp/osv-scanner "https://github.com/google/osv-scanner/releases/download/${OSV_VERSION}/osv-scanner_linux_amd64"
echo "${OSV_SHA256}  /tmp/osv-scanner" | sha256sum -c -
install -m 0755 /tmp/osv-scanner /usr/local/bin/osv-scanner
rm -f /tmp/osv-scanner

# One fixed path to the browser the image ships, for Lighthouse (CHROME_PATH).
# The image's folder name carries Chromium's build number, so it is looked up.
ln -sf "$(ls -d /opt/pw-browsers/chromium-*/chrome-linux/chrome | sort -V | tail -1)" /usr/local/bin/chromium

pwsh -v
chromium --version
lighthouse --version
linkinator --version
osv-scanner --version

# The bot's libraries in python3.12 (bot/requirements.txt, by hash), and a
# SessionStart hook in the user's Claude settings that keeps them at the
# clone's pins at every session start (#3055). From the Thornswood clone,
# which is made before this script runs in a session that has the repository.
# A session with no repository attached has no clone and no bot to test, so
# it has nothing to install (#3085). A clone without the script fails here.
clone=/home/user/Thornswood
if [ -d "$clone/.git" ]; then
  bash "$clone/scripts/dev/Setup-CloudSession.sh" --register
else
  echo "No Thornswood clone in this session ($clone), so the bot's libraries are not set up here."
fi
