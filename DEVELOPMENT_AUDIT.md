# MacPulse development audit

Baseline checkpoint: `checkpoint/pre-production-upgrade` at `f2898e10ff784b833648ffa3295438d03112a7c4`. Working tree was clean; no source or user data was discarded. The user reports that the Mac app launches and its notch animations work. This Linux session independently verified 11 passing XCTest tests; it cannot verify that reported GUI behavior.

## Existing architecture

- Entry: `MacPulseApp` and `AppDelegate`; manually managed dashboard NSWindow and menu-bar status item.
- Views: seven dashboard pages, reusable cards/rings/charts, native Form settings and three-tab notch.
- Window management: `NotchController`, nonactivating NSPanel, NSScreen safe-area geometry, display observer, hover task and outside-click monitors.
- Monitoring: NSWorkspace notifications + five-second polling; Mach CPU/VM, IOKit power sources, volume resource values and interface counters.
- Core: portable activity clock, interval models/analytics, SQLite wrapper and local Codex JSONL parser.
- Persistence: existing SQLite activity/metadata/samples/events tables, WAL, per-record JSON payloads; UserDefaults preferences. No versioned migrations or explicit computer-session records.
- Codex: opt-in folder import; session/project/token metadata only. No authenticated subscription usage source.
- Build: macOS 14 minimum, Swift 5 language mode, Xcode app/static core framework/hostless tests, SPM core + executable, macOS CI and local ad hoc bundle script. Apple Silicon preferred; no exclusive architecture pin.

## Preserved capabilities

Bundle identity `com.macpulse.app`, database location, existing tables and decodable payloads, preference keys, demo/live separation, menu bar fallback, current notch safe-area positioning and spring animation settings. Existing source organization is retained. Generated helpers, CI, plist and tests were inspected alongside all application modules.

## Gaps and defects

- Sparse overview; no insights, coverage-aware comparison or real computer-session summaries.
- Idle polling queried null events rather than the documented any-input sentinel; this is corrected in the upgrade.
- Activity uses wall time; entire intervals are dropped when idle threshold is crossed; exclusions incorrectly discard the preceding application's final interval.
- No persisted session boundaries or idle/sleep intervals. Session duration is reconstructed only for the current launch.
- Missing historical dates are shown as zero; smooth chart interpolation implies continuity across missing samples.
- One bad JSON row aborts an entire database load; pruning is not transactional; no schema-version gate.
- Codex import replaces history and lacks model/cached-token analytics, import diagnostics and project exclusions.
- CPU counters do not tolerate wrap/reset well; network rates combine counters across changing interfaces; battery/storage queried on every tick.
- Preference changes reset tracking indiscriminately; hidden dashboard and notch views observe the global sampling model.
- System appearance uses a dark background even when the system is light; application icons repeatedly resolve through NSWorkspace.
- No supported universal Now Playing integration. No trustworthy subscription source; no real alerts/projection can be enabled.

## Planned incremental changes

1. Add source-state types, monotonic interval accounting, explicit computer sessions, idle/sleep intervals and compatible versioned SQLite additions.
2. Add coverage-aware local-time analytics, category stacks, comparisons, personal records, session detail and CSV/JSON export.
3. Enrich metadata-only Codex parsing/import, project/model rankings and daily trends. Preserve honest subscription unavailability.
4. Add richer system details and bounded sampling histories; cache slow queries; use per-interface counter deltas and tested portable CPU math.
5. Enrich dashboard and notch, add Insights, date/category/app filters and useful persistent customization. Preserve window geometry and animation behavior.
6. Expand deterministic regression tests, synchronize Xcode references, run Linux tests and macOS syntax validation, attempt native packaging, document exact unverified acceptance criteria.

## Existing remote build evidence

The public baseline Actions run `38207459091` for `f2898e1` reports success for Swift-package core tests, failure for Native Xcode tests (exit 65), and skipped bundle packaging. That Xcode failure predates this upgrade. The unauthenticated log endpoint is unavailable, so its exact cause is not established. The project lacked explicit `ENABLE_TESTABILITY` in Debug; this has been added for its hostless `@testable` unit tests. The updated workflow publishes compiler-error annotations and preserves pipeline exit status to diagnose new native runs.

## Compatibility risks and validation limits

New optional fields must decode old JSON payloads. Migrations must preserve old tables and fail safely on future schemas. New tables must not invent historical sessions for old intervals. Unknown historical coverage must remain unknown. macOS monitoring and AppKit/SwiftUI type checking, fullscreen/menu-bar behavior, visual inspection, login registration and performance profiling require a Mac. Native build and bundle creation are blocked on this Linux host; this is recorded rather than treating a syntax parse as a native build. Official usage integration and universal media information remain independently unavailable, so neither blocks local analytics implementation.

## Upgrade outcome

The working application identity, original preference keys and old SQLite tables were preserved. Additive schema 2 migration and old optional payload compatibility are covered by tests. The final source at `2b0fc9f` passed Linux's 34 core tests and macOS CI's native build/test/package plus two GUI tests in run `38216741402`. The baseline Xcode failure, SwiftUI solver timeouts and GUI accessibility lookup failures were repaired and regression-checked. Screenshot attachments exist, but no rendered visual review, physical notch test, sustained profiling, login approval or real authenticated allowance read is claimed. See docs/VALIDATION.md for remaining acceptance checks.
