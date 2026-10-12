#!/bin/bash
# Portable core validation only; AppKit and SwiftUI still require macOS.
set -euo pipefail
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || { echo 'This helper requires x86_64 Linux.' >&2; exit 1; }
TOOLS=/workspace/toolchains
mkdir -p "$TOOLS/gnupg" "$TOOLS/cache" "$TOOLS/apt/lists/partial" "$TOOLS/apt/cache/archives/partial" "$TOOLS/apt/empty"
chmod 700 "$TOOLS/gnupg"
SWIFT_DIR="$TOOLS/swift-6.2.3-RELEASE-ubuntu24.04"
if [[ ! -x "$SWIFT_DIR/usr/bin/swift" ]]; then
  BASE=https://download.swift.org/swift-6.2.3-release/ubuntu2404/swift-6.2.3-RELEASE/swift-6.2.3-RELEASE-ubuntu24.04.tar.gz
  curl -fL --retry 2 "$BASE" -o "$TOOLS/swift.tar.gz"
  curl -fL --retry 2 "$BASE.sig" -o "$TOOLS/swift.tar.gz.sig"
  curl -fL --retry 2 https://raw.githubusercontent.com/swiftlang/swift-org-website/main/keys/all-keys.asc -o "$TOOLS/swift-keys.asc"
  gpg --homedir "$TOOLS/gnupg" --import "$TOOLS/swift-keys.asc"
  gpg --homedir "$TOOLS/gnupg" --status-fd 1 --verify "$TOOLS/swift.tar.gz.sig" "$TOOLS/swift.tar.gz" > "$TOOLS/verified-signature.log"
  # Require the official Swift 6 release signing fingerprint, even when other keys are imported.
  rg -q '^\[GNUPG:\] VALIDSIG 52BB7E3DE28A71BE22EC05FFEF80A866B47A981F ' "$TOOLS/verified-signature.log"
  tar -xzf "$TOOLS/swift.tar.gz" -C "$TOOLS"
fi
if [[ ! -f "$TOOLS/sysroot/usr/include/sqlite3.h" ]]; then
  printf '%s\n' 'deb [signed-by=/usr/share/keyrings/debian-archive-keyring.gpg] https://deb.debian.org/debian trixie main' > "$TOOLS/apt/sources.list"
  APT_OPTIONS=(-o "Dir::State::lists=$TOOLS/apt/lists" -o "Dir::Cache=$TOOLS/apt/cache" -o Dir::Etc::main=/dev/null -o "Dir::Etc::parts=$TOOLS/apt/empty" -o "Dir::Etc::sourcelist=$TOOLS/apt/sources.list" -o "Dir::Etc::sourceparts=$TOOLS/apt/empty")
  apt-get "${APT_OPTIONS[@]}" -o APT::Update::Error-Mode=any update
  (cd "$TOOLS" && apt-get "${APT_OPTIONS[@]}" download libsqlite3-dev)
  for archive in "$TOOLS"/libsqlite3-dev_*_amd64.deb; do dpkg-deb -x "$archive" "$TOOLS/sysroot"; done
fi
"$SWIFT_DIR/usr/bin/swift" --version
