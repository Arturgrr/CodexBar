#!/usr/bin/env bash
# Build an ad-hoc signed CodexBar.app from this checkout, replace the installed copy, relaunch, and link the CLI.
#
# Ad-hoc builds ship without a Sparkle feed, so the installed app never auto-updates over the fork.
# Usage: ./Scripts/fork_install.sh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"
CLI_LINK="${CLI_LINK:-$HOME/.local/bin/codexbar}"
INSTALLED_APP="${INSTALL_DIR}/CodexBar.app"
BUILT_APP="${ROOT_DIR}/CodexBar.app"

log()  { printf '%s\n' "$*"; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# Packaging needs full Xcode (widget xcodebuild, SwiftUI macros); use it when xcode-select points at the CLT.
if [[ -z "${DEVELOPER_DIR:-}" && "$(xcode-select -p 2>/dev/null)" == /Library/Developer/CommandLineTools* \
  && -d /Applications/Xcode.app ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

if command -v brew >/dev/null 2>&1 && brew list --cask codexbar >/dev/null 2>&1; then
  fail "the Homebrew cask is still installed; run 'brew uninstall --cask codexbar' first (settings in ~/.config/codexbar are kept)"
fi

log "==> Packaging ${BUILT_APP}"
CODEXBAR_SIGNING=adhoc "${ROOT_DIR}/Scripts/package_app.sh" release

log "==> Stopping running CodexBar"
pkill -x CodexBar || pkill -f CodexBar.app || true
for _ in {1..40}; do
  pgrep -x CodexBar >/dev/null || break
  sleep 0.25
done
pgrep -x CodexBar >/dev/null && fail "CodexBar is still running"

if [[ -d "$INSTALLED_APP" ]]; then
  installed_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${INSTALLED_APP}/Contents/Info.plist" 2>/dev/null || true)
  [[ "$installed_id" == com.steipete.codexbar* ]] || fail "${INSTALLED_APP} is not a CodexBar bundle (${installed_id:-unknown})"
  backup="${TMPDIR:-/tmp}/CodexBar.app.previous"
  rm -rf "$backup"
  mv "$INSTALLED_APP" "$backup"
  log "==> Previous app moved to ${backup}"
fi

log "==> Installing ${INSTALLED_APP}"
ditto "$BUILT_APP" "$INSTALLED_APP"

mkdir -p "$(dirname "$CLI_LINK")"
ln -sf "${INSTALLED_APP}/Contents/Helpers/CodexBarCLI" "$CLI_LINK"
log "==> CLI linked at ${CLI_LINK}"

open -n "$INSTALLED_APP"
log "==> Launched $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${INSTALLED_APP}/Contents/Info.plist") from $(git -C "$ROOT_DIR" rev-parse --short HEAD)"
