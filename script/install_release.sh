#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 || ! -f "$1" ]]; then
  echo "usage: $0 <CodexQ-version-architecture.zip>" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXPECTED_VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/Sources/CodexQ/Resources/Version.txt")"
ARCH="$(uname -m)"
ARCHIVE="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
SYSTEM_APP="/Applications/CodexQ.app"
USER_APP="$HOME/Applications/CodexQ.app"

if [[ -e "$SYSTEM_APP" && -e "$USER_APP" ]]; then
  echo "CodexQ is installed in both Applications folders; resolve the duplicate first." >&2
  exit 1
fi

if [[ -e "$USER_APP" ]]; then
  TARGET="$USER_APP"
else
  TARGET="$SYSTEM_APP"
fi

if [[ -L "$TARGET" ]]; then
  echo "Refusing to replace a symbolic link: $TARGET" >&2
  exit 1
fi

INSTALL_DIR="$(dirname "$TARGET")"
if [[ ! -w "$INSTALL_DIR" ]]; then
  echo "Applications folder is not writable: $INSTALL_DIR" >&2
  exit 1
fi

STAGING="$(mktemp -d "$INSTALL_DIR/.codexq-install.XXXXXX")"
NEW_APP="$STAGING/CodexQ.app"
OLD_APP="$STAGING/Previous-CodexQ.app"
MOVED_OLD=0
INSTALLED_NEW=0
COMPLETED=0

bundle_value() {
  /usr/libexec/PlistBuddy -c "Print :$2" "$1/Contents/Info.plist"
}

cleanup() {
  if [[ "$COMPLETED" -eq 0 ]]; then
    if [[ "$INSTALLED_NEW" -eq 1 ]]; then
      if ! mv "$TARGET" "$STAGING/Failed-CodexQ.app"; then
        echo "Could not move the failed app; previous app is preserved at $OLD_APP." >&2
        return
      fi
    fi
    if [[ "$MOVED_OLD" -eq 1 ]]; then
      if ! mv "$OLD_APP" "$TARGET"; then
        echo "Could not restore the previous app; it is preserved at $OLD_APP." >&2
        return
      fi
      /usr/bin/open -n "$TARGET" || true
      echo "Installation failed; restored the previous CodexQ.app." >&2
    fi
  fi
  rm -rf "$STAGING"
}
trap cleanup EXIT

/usr/bin/ditto -x -k "$ARCHIVE" "$STAGING"
if [[ ! -d "$NEW_APP" || -L "$NEW_APP" ]]; then
  echo "Archive does not contain a regular CodexQ.app bundle." >&2
  exit 1
fi
if [[ "$(bundle_value "$NEW_APP" CFBundleIdentifier)" != "com.jun.codexq" \
   || "$(bundle_value "$NEW_APP" CFBundleShortVersionString)" != "$EXPECTED_VERSION" \
   || "$(/usr/bin/lipo -archs "$NEW_APP/Contents/MacOS/CodexQ")" != "$ARCH" ]]; then
  echo "Archive bundle identity, version, or architecture does not match this Mac." >&2
  exit 1
fi
/usr/bin/codesign --verify --deep --strict "$NEW_APP"

if [[ -e "$TARGET" ]]; then
  if [[ ! -d "$TARGET" || "$(bundle_value "$TARGET" CFBundleIdentifier)" != "com.jun.codexq" ]]; then
    echo "Existing Applications item is not CodexQ: $TARGET" >&2
    exit 1
  fi
fi

# Stop both installed and development copies so only the new installed app remains running.
pkill -x CodexQ 2>/dev/null || true
for _ in {1..50}; do
  if ! pgrep -x CodexQ >/dev/null; then break; fi
  sleep 0.1
done
if pgrep -x CodexQ >/dev/null; then
  echo "CodexQ did not quit; installation stopped before replacing the app." >&2
  exit 1
fi

if [[ -e "$TARGET" ]]; then
  mv "$TARGET" "$OLD_APP"
  MOVED_OLD=1
fi
mv "$NEW_APP" "$TARGET"
INSTALLED_NEW=1
/usr/bin/open -n "$TARGET"

for _ in {1..50}; do
  if pgrep -f -x "$TARGET/Contents/MacOS/CodexQ" >/dev/null; then
    sleep 1
    if pgrep -f -x "$TARGET/Contents/MacOS/CodexQ" >/dev/null; then
      COMPLETED=1
      echo "Installed and started CodexQ $EXPECTED_VERSION at $TARGET"
      exit 0
    fi
  fi
  sleep 0.1
done
echo "The installed app did not start." >&2
exit 1
