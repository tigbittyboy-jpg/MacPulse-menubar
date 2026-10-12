#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TOOLS=/workspace/toolchains
SWIFT="$TOOLS/swift-6.2.3-RELEASE-ubuntu24.04/usr/bin/swift"
if [[ ! -x "$SWIFT" || ! -f "$TOOLS/sysroot/usr/include/sqlite3.h" ]]; then
  echo 'Run scripts/bootstrap-linux.sh to prepare the portable Swift test tools.' >&2
  exit 1
fi
export CLANG_MODULE_CACHE_PATH="$TOOLS/cache/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$TOOLS/cache/swift"
export XDG_CACHE_HOME="$TOOLS/cache"
"$SWIFT" test --cache-path "$TOOLS/cache/swiftpm" --config-path "$TOOLS/cache/config" \
  --security-path "$TOOLS/cache/security" --jobs 4 \
  -Xcc "-I$TOOLS/sysroot/usr/include" \
  -Xlinker "-L$TOOLS/sysroot/usr/lib/x86_64-linux-gnu"
