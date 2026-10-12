# Validation and remaining Mac checks

## Executed in this cloud session

The host is Debian Linux x86_64. The official Swift 6.2.3 Ubuntu toolchain was downloaded over verified TLS and its detached release signature verified against the official Swift release key (fingerprint `52BB7E3DE28A71BE22EC05FFEF80A866B47A981F`). The key has since expired; the release signature was created while it was valid. Signature verification was not disabled. SQLite development headers/libraries were obtained using APT's authenticated Debian package metadata and unpacked into `/workspace/toolchains/sysroot`, without a root installation.

- Portable core library and Linux command-line fallback compiled and linked.
- XCTest: **11 tests passed, zero failures**, covering app switching, idle/disabled/excluded intervals, sleep gaps, demo/live recording isolation, midnight overlap, weekly totals, SQLite reopen/upsert, retention/deletion, persistent samples/events, metadata parsing and CSV escaping.
- The additional Swift Testing runner reports zero tests because this suite uses XCTest; the XCTest count above is the meaningful result.
- All macOS app source files passed Swift's syntax parser with the macOS target selected. This does **not** resolve AppKit/SwiftUI types or prove a macOS build.
- Shell scripts passed `bash -n`. The bundle script correctly refuses to build on Linux.
- Xcode project structure, scheme XML and Info.plist were checked locally. Xcode itself is unavailable.

No macOS application was launched, no GUI automation ran and no visual review of a rendered application was performed. The macOS CI file has not been dispatched in this session. No runnable `.app` or notarized distribution is claimed.

## Manual verification on macOS — pending

1. Build the MacPulse scheme with Xcode and run both `swift test` and native Xcode tests. Package with `scripts/build-app.sh`; verify the bundle opens from Applications and displays its icon.
2. In initial Demo mode, visit every dashboard page, change date/application filters, edit categories, export CSV, change appearance and inspect layout at minimum window size. Confirm the demo banner remains visible and no recording occurs.
3. Turn off Demo, enable monitoring and switch between two apps. Verify elapsed foreground time, app icons and day totals. Pause recording; verify totals stop growing. Re-enable and verify the paused interval is not backfilled.
4. Leave the Mac idle for more than 60 seconds, then resume. Sleep/wake and lock/unlock it. Confirm idle/sleep gaps are excluded and events appear only during enabled live recording. Check behavior across midnight.
5. Quit and relaunch; recorded activity, categories, Codex metadata and recent minute samples should survive. Check retention and delete history with confirmation; relaunch to confirm deletion. Demo data should remain separate.
6. On a notched MacBook, hover each side indicator, leave quickly, click to expand, switch all three tabs, click outside, press Escape and open the dashboard. Verify rounded lower corners, no hardware-notch overlap with visible text and no menu-bar obstruction.
7. Connect/disconnect an external monitor, change scaling, enter fullscreen apps, switch Spaces and move the menu bar. Confirm positioning updates and the panel does not steal key focus. On a non-notched screen, test menu bar fallback alignment and edge clamping.
8. Enable Reduce Motion and turn animations off; verify resizing/transitions respect both. Check focus behavior during rapid hovering/clicking and long app/project names at minimum sizes.
9. Check CPU and network changes under load against Activity Monitor, battery charge while plugged/unplugged and storage against Finder. Validate unavailable values on desktop Macs; verify there are no fabricated sensor readings.
10. Import a selected Codex sessions folder in live mode, including partial/malformed lines. Verify only project basename, dates and aggregate token counts persist. Confirm no auth files are read, no session contents are retained, and subscription allowance remains unavailable.
11. Enable login registration from the installed bundle, approve if requested and verify at next login. Disable it and verify removal. Profile CPU/memory over an hour, check observer/timer cleanup when quitting and confirm no unexpected network traffic.

Visual refinement in this session was a source review of spacing, minimum sizes, native typography, contrast choices and animation settings. The rendered interface and behavior require the checks above.
