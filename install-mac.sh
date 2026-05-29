#!/usr/bin/env bash
#
#  Claude Desktop RTL  -  macOS IN-PLACE patcher  (ASCII-only)
#  ---------------------------------------------------------------------------
#  Patches the REAL /Applications/Claude.app in place (same app, your login,
#  Cowork intact) - matching the Windows experience. No second app.
#    * inject the RTL engine into app.asar + repack
#    * recompute the asar header SHA-256 and update ElectronAsarIntegrity in
#      every Info.plist (integrity stays ON)
#    * write the patched files back into the bundle via Finder (no sudo; works
#      around macOS App-Management protection), then ad-hoc re-sign
#  Backup + rollback + auto-update (LaunchAgent). No admin/sudo.
#
#  Run:   bash install-mac.sh                 (no chmod needed)
#         bash install-mac.sh --uninstall | --status | --auto
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_APP="/Applications/Claude.app"
RES="$SRC_APP/Contents/Resources"
ASAR="$RES/app.asar"
PAYLOAD="$SCRIPT_DIR/rtl-engine.js"
SUPPORT="$HOME/Library/Application Support/ClaudeRTL"
BK="$SUPPORT/backup"
STATE="$SUPPORT/state"
AGENT="$HOME/Library/LaunchAgents/com.claudertl.autoupdate.plist"
ASAR_PKG="@electron/asar@4.2.0"
AUTO=0
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"   # make node visible (incl. under LaunchAgent)

c_reset=$'\033[0m'; c_g=$'\033[32m'; c_y=$'\033[33m'; c_r=$'\033[31m'; c_c=$'\033[36m'
log()  { printf '%s\n' "$*"; }
ok()   { printf '%s[ok]%s %s\n' "$c_g" "$c_reset" "$*"; }
warn() { printf '%s[!]%s %s\n'  "$c_y" "$c_reset" "$*"; }
die()  { printf '%s[X]%s %s\n'  "$c_r" "$c_reset" "$*" >&2; exit 1; }
step() { printf '%s==>%s %s\n'  "$c_c" "$c_reset" "$*"; }

asar_cmd() { if command -v asar >/dev/null 2>&1; then asar "$@"; else npx --yes "$ASAR_PKG" "$@"; fi; }

asar_header_hash() {
  python3 - "$1" <<'PY'
import sys, struct, hashlib
with open(sys.argv[1], "rb") as f:
    f.seek(12); n = struct.unpack("<I", f.read(4))[0]
    print(hashlib.sha256(f.read(n)).hexdigest())
PY
}

# Write a file into a (TCC-protected) app bundle: try direct cp, then Finder (no sudo).
place_file() {
  local src="$1" dst="$2"
  if cp -f "$src" "$dst" 2>/dev/null; then return 0; fi
  local dir; dir="$(dirname "$dst")/"
  local name; name="$(basename "$dst")"
  osascript >/dev/null 2>&1 <<APPLE
tell application "Finder"
  try
    delete (POSIX file "${dst}" as alias)
  end try
  set newf to duplicate (POSIX file "${src}") to (POSIX file "${dir}" as alias) with replacing
  set name of newf to "${name}"
end tell
APPLE
  [ -f "$dst" ]
}

require() {
  [ -d "$SRC_APP" ] || die "Claude not found at $SRC_APP. Install it from https://claude.ai/download"
  [ -f "$PAYLOAD" ] || die "rtl-engine.js not found next to this script."
  command -v node     >/dev/null 2>&1 || die "Node.js is required (https://nodejs.org)."
  command -v python3  >/dev/null 2>&1 || die "python3 is required (ships with macOS)."
  command -v codesign >/dev/null 2>&1 || die "Xcode Command Line Tools required (xcode-select --install)."
}

is_patched()   { grep -qa 'CLAUDE RTL PATCH START' "$ASAR" 2>/dev/null; }
orig_version() { /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$SRC_APP/Contents/Info.plist" 2>/dev/null || echo '?'; }
list_plists()  { find "$SRC_APP/Contents" -name 'Info.plist' -type f; }

quit_claude() {
  osascript -e 'tell application "Claude" to quit' >/dev/null 2>&1 || true
  sleep 1
  pkill -f "Claude.app/Contents/MacOS/Claude" 2>/dev/null || true
  sleep 1
}

resign() {  # ad-hoc, inside-out
  local app="$1"
  find "$app" -type f \( -name '*.dylib' -o -name '*.node' -o -perm -111 \) 2>/dev/null | while IFS= read -r f; do
    file "$f" 2>/dev/null | grep -q 'Mach-O' && codesign --force --sign - "$f" >/dev/null 2>&1 || true
  done
  find "$app" -name '*.framework' 2>/dev/null | while IFS= read -r fw; do codesign --force --deep --sign - "$fw" >/dev/null 2>&1 || true; done
  find "$app" -name '*.app' -not -path "$app" 2>/dev/null | while IFS= read -r a; do codesign --force --deep --sign - "$a" >/dev/null 2>&1 || true; done
  codesign --force --deep --sign - "$app" >/dev/null 2>&1 || warn "Final re-sign reported a warning (usually fine for ad-hoc)."
}

install_agent() {
  mkdir -p "$SUPPORT" "$(dirname "$AGENT")"
  cat > "$AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.claudertl.autoupdate</string>
  <key>ProgramArguments</key>
  <array><string>/bin/bash</string><string>$SCRIPT_DIR/install-mac.sh</string><string>--auto</string></array>
  <key>RunAtLoad</key><true/>
  <key>StartInterval</key><integer>21600</integer>
  <key>StandardOutPath</key><string>$SUPPORT/autoupdate.log</string>
  <key>StandardErrorPath</key><string>$SUPPORT/autoupdate.log</string>
</dict></plist>
PLIST
  launchctl unload "$AGENT" 2>/dev/null || true
  launchctl load  "$AGENT" 2>/dev/null || true
}
remove_agent() { launchctl unload "$AGENT" 2>/dev/null || true; rm -f "$AGENT" 2>/dev/null || true; }

backup_originals() {   # only the pristine (unpatched) files
  mkdir -p "$BK"
  cp -f "$ASAR" "$BK/app.asar" 2>/dev/null || die "Could not read app.asar to back up."
  : > "$BK/plist_paths.txt"
  local p i=0
  while IFS= read -r p; do
    cp -f "$p" "$BK/plist_$i.plist" 2>/dev/null && printf '%s\n' "$p" >> "$BK/plist_paths.txt"
    i=$((i+1))
  done < <(list_plists)
}

install_rtl() {
  require
  if is_patched; then
    step "Already patched - restoring originals first to re-apply the latest engine..."
    if [ -f "$BK/app.asar" ]; then
      place_file "$BK/app.asar" "$ASAR" || true
      if [ -f "$BK/plist_paths.txt" ]; then
        local i=0 pp
        while IFS= read -r pp; do [ -f "$BK/plist_$i.plist" ] && place_file "$BK/plist_$i.plist" "$pp"; i=$((i + 1)); done < "$BK/plist_paths.txt"
      fi
    fi
  fi

  step "Quitting Claude..."
  quit_claude
  step "Backing up the original files (for rollback)..."
  backup_originals

  step "Extracting + injecting the RTL engine..."
  local old_hash new_hash tmp
  old_hash="$(asar_header_hash "$ASAR")"
  tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' RETURN
  asar_cmd extract "$ASAR" "$tmp/app"
  [ -d "$tmp/app/.vite" ] || die "Unexpected app layout (.vite missing) - Claude changed its structure."
  local injected=0 f merged
  while IFS= read -r f; do
    grep -q 'CLAUDE RTL PATCH START' "$f" 2>/dev/null && continue
    merged="$(mktemp)"; cat "$PAYLOAD" "$f" > "$merged" && mv "$merged" "$f"
    injected=$((injected + 1))
  done < <(find "$tmp/app/.vite" -name '*.js' -type f)
  [ "$injected" -gt 0 ] || die "No renderer JS files found to inject."
  ok "Injected into $injected file(s)."

  step "Repacking archive..."
  asar_cmd pack "$tmp/app" "$tmp/app.asar.new" --unpack "{*.node,spawn-helper}"
  new_hash="$(asar_header_hash "$tmp/app.asar.new")"

  step "Writing the patched archive into Claude.app..."
  place_file "$tmp/app.asar.new" "$ASAR" \
    || die "Could not write into Claude.app. Open System Settings > Privacy & Security > App Management, allow your terminal, then re-run."

  step "Updating integrity (keep validation ON)..."
  local p patched=0 tplist
  while IFS= read -r p; do
    if grep -q "$old_hash" "$p" 2>/dev/null; then
      tplist="$(mktemp)"; sed "s/$old_hash/$new_hash/g" "$p" > "$tplist"
      place_file "$tplist" "$p" && patched=$((patched + 1)); rm -f "$tplist"
    fi
  done < <(list_plists)
  ok "Updated ElectronAsarIntegrity in $patched plist(s)."

  step "Clearing quarantine + re-signing (ad-hoc)..."
  xattr -cr "$SRC_APP" 2>/dev/null || true
  resign "$SRC_APP"

  install_agent; orig_version > "$STATE"
  ok "Auto-update enabled (re-patches at login after a Claude update)."
  if [ "$AUTO" -eq 0 ]; then
    ok "Done! Open Claude normally - same app, your login, your chats, + RTL."
    open -a "Claude" || true
    log "  Toggle RTL with Ctrl+Alt+R."
    log "  If Claude won't open, run:  bash install-mac.sh --uninstall"
  fi
}

uninstall_rtl() {
  step "Restoring the original Claude.app + removing auto-update..."
  quit_claude
  remove_agent
  if [ -f "$BK/app.asar" ]; then
    place_file "$BK/app.asar" "$ASAR" || warn "Could not restore app.asar."
    if [ -f "$BK/plist_paths.txt" ]; then
      local i=0 p
      while IFS= read -r p; do
        [ -f "$BK/plist_$i.plist" ] && place_file "$BK/plist_$i.plist" "$p"
        i=$((i + 1))
      done < "$BK/plist_paths.txt"
    fi
    xattr -cr "$SRC_APP" 2>/dev/null || true
    resign "$SRC_APP"
    ok "Restored. (If anything looks off, reinstall from https://claude.ai/download.)"
  else
    warn "No backup found - reinstall Claude from https://claude.ai/download to restore."
  fi
  rm -rf "$SUPPORT" 2>/dev/null || true
}

status_rtl() {
  log "Original Claude : $(orig_version)  ($SRC_APP)"
  if is_patched; then ok "RTL patch       : ACTIVE"; else warn "RTL patch       : not applied"; fi
  if [ -f "$AGENT" ]; then ok "Auto-update     : enabled"; else warn "Auto-update     : off"; fi
}

case "${1:---install}" in
  --install|-i)   install_rtl ;;
  --uninstall|-u) uninstall_rtl ;;
  --status|-s)    status_rtl ;;
  --auto)         AUTO=1; if ! is_patched; then install_rtl; else log "Up to date."; fi ;;
  --help|-h)      log "Usage: bash install-mac.sh [--install | --uninstall | --status | --auto]" ;;
  *)              die "Unknown option '$1' (use --help)" ;;
esac
