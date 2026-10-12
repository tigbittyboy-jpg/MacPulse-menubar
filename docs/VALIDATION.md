# Upgrade validation

## Local checks

The cloud host is Debian Linux x86_64. The official Swift 6.2.3 toolchain was verified against the Swift release signature; SQLite headers/libraries were obtained through authenticated Debian APT metadata. No package/TLS/signature verification was disabled.

The upgraded portable suite executed **34 XCTest tests, zero failures**. It exercises foreground switching and exclusions, clipped idle boundaries/resumption, monotonic clock discontinuities, demo/live isolation, daily/week ranking, DST days, unknown historical coverage, session recovery without downtime backfill, atomic rollback, additive legacy migration, future-schema refusal, corrupt-row isolation, old optional payloads, CPU/network counter resets, local model/cached-token parsing, export/source labels, saved-setting defaults, official multi-bucket rate parsing, independent backend usage permission, stale/reset handling, account-isolated projection/alert deduplication and a deterministic app-server handshake/timeout.

The Swift Testing runner's separate zero-test message is not the suite outcome; the XCTest suite above is the meaningful result. The macOS files also passed a syntax parse locally. Xcode source references, object references, scheme XML and Info.plist were validated; shell/Python helpers were checked. Linux itself cannot build AppKit/SwiftUI binaries or run GUI tests.

## Native macOS CI evidence

Baseline `f2898e1` run [38207459091](https://github.com/tigbittyboy-jpg/MacPulse-menubar/actions/runs/38207459091) had passing Swift-package tests but a failing native Xcode step before this upgrade. Debug testability was made explicit. Initial upgrade runs exposed SwiftUI type-checker timeouts, which were fixed by splitting the Codex page and its session row into smaller expressions.

At `6a97b79`, run [38213677951](https://github.com/tigbittyboy-jpg/MacPulse-menubar/actions/runs/38213677951) passed the Swift-package tests, native Xcode tests, Release packaging, archive and upload. Its mode UI test exposed a checkbox lookup problem, then explicit identifiers/control styling repaired that test.

At `e7cfaad`, run [38214375025](https://github.com/tigbittyboy-jpg/MacPulse-menubar/actions/runs/38214375025) passed **both the macOS build/test/package job and the separate UI job**. The UI target executes two tests: eight-page navigation with screenshots, and demo/live recording-control interactions. A later navigation test was strengthened to target the real page heading rather than a matching sidebar string; the macOS accessibility label/value distinction is addressed with an explicit VoiceOver label and unique identifier.

At `8c14226`, run [38215887842](https://github.com/tigbittyboy-jpg/MacPulse-menubar/actions/runs/38215887842) passed native build/test/package and both UI tests after strengthening the actual page-heading assertion and correcting all-input idle polling. The subsequent account-scope regression checks passed locally; its final native run is recorded below when complete. Failed, repaired and pending outcomes are kept distinct.

## Artifact and build locations

A successful packaging job creates `build/MacPulse.app` on the macOS runner, verifies its ad hoc signature and archives it as `build/MacPulse-macOS.zip`. Download the **MacPulse-validation** artifact for the intended successful run; it contains build logs and the nested app ZIP. The **MacPulse-UI-results** artifact includes the UI log and `UITests.xcresult`, with kept screenshots. These are CI-produced artifacts, not an application built inside this Linux workspace.

The same local Mac command `./scripts/build-app.sh` produces `<checkout>/build/MacPulse.app`. No notarization/public distribution signing is claimed. No rendered screenshots were inspected by the assistant in this cloud session; automated screenshot capture and a human visual review are different checks.

## Manual acceptance checks still pending

- Physical notched MacBook alignment, hover/click behavior during rapid interaction, monitor scaling/hot-plug, fullscreen/Spaces, menu-bar auto-hide, nonactivation/focus and keyboard dismissal. CI machines do not establish physical notch behavior.
- Rendered screenshot review across all eight pages at minimum size, chart hover/selection/zoom, long app/project names, light/dark/system appearance, source badges, Reduce Motion and density.
- Foreground tracking against known elapsed time on the user's Mac, lock/idle/resumption, sleep/wake, process termination, retention and quit/relaunch preservation. Interval/persistence arithmetic is covered by core tests; real OS event accuracy still needs verification.
- Real CPU/memory/battery/storage/network/process values compared with macOS tools, interface changes, desktops without batteries and pressure events; background CPU/memory/power profiling over sustained use.
- Launch-at-login registration/approval from the installed bundle. No privacy prompt is requested by ordinary activity collection.
- Actual signed-in official Codex CLI handshake and authenticated usage readings, account variations, service errors, optional notification permission and delivered alerts. Tests use deterministic child-process fixtures rather than a real account. Local metadata folder import and version compatibility on the user's installation still need checking.

## Explicit limits

Now Playing/provider-specific integration, GPU/temperature/battery-health sensors, universal OS Screen Time history, per-project foreground attribution, precise per-app activation counts, custom category creation, live filesystem watching, auto-update and distribution notarization are not implemented. Unsupported metrics remain unavailable. Daily aggregates are derived from retained intervals rather than stored redundantly. Session detail timelines show the starting day; Screen Time offers each calendar date. Network interface totals can overlap VPN/bridge traffic, and process CPU is a lifetime average rather than an instantaneous sample.
