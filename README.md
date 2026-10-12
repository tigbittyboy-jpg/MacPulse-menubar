# MacPulse

A native macOS proof of concept that brings your activity and system pulse into a quiet, notch-connected control center. Built with SwiftUI, AppKit, Swift Charts and SQLite. No server, web UI, analytics upload or third-party app dependencies.

**Status:** source implementation and portable core tests are complete. This repository was developed on Linux: the macOS target has not been type-checked, launched or visually verified yet. There is no prebuilt `.app` in this checkout. Run the macOS build below or the included CI workflow before relying on the app.

## Build and launch on your Mac

Requirements: macOS 14+, Apple Silicon recommended, full Xcode 15+ with its macOS SDK selected. The project uses the SDK supplied by your installed Xcode rather than downloading or pinning an Apple SDK.

1. Open `MacPulse.xcodeproj` in Xcode.
2. Select the **MacPulse** scheme and **My Mac**, then press Run.
3. Explore the dashboard in **Demo mode**. Settings → turn off Demo mode to see live system metrics. Enable **Record application activity** to begin your local usage history.

To create a standalone bundle, run once from the repository directory:

```sh
./scripts/build-app.sh
```

Drag `build/MacPulse.app` to Applications and open it normally. The bundle includes a generated native icon and is signed locally with an ad hoc signature; distribution signing and notarization are not included. Launch at login is optional and may need approval in System Settings → General → Login Items. No Terminal or development server is needed after installation.

If Xcode command-line tools point at a standalone Command Line Tools installation, select full Xcode in Xcode → Settings → Locations → Command Line Tools, then retry.

## Interface

- **Notched display:** a black top-edge panel blends with the physical notch. Hover the subtle side indicator to reveal a compact summary; click the top strip or Expand to pin the control center. Overview, Codex and Activity tabs are available in the expanded state. Escape, an outside click or the close control collapses it.
- **Other displays:** click the waveform menu bar icon for a panel beneath the menu bar. The fallback follows the display containing the pointer. A connected notched display is preferred automatically.
- **Dashboard:** open it with the arrow in the panel or by clicking the Dock icon. Closing it leaves MacPulse running in the menu bar; use Command-Q to quit.
- **Settings:** mode, recording, hover delay, transitions, dashboard appearance, CPU visibility, launch at login, exclusions, retention, export and deletion. System Reduce Motion disables notch animations.

The dark graphite surfaces, blue/cyan/violet accents, monospaced counters, lower notch corners, chart grid and compact controls are original. The supplied screenshot informs the notch silhouette and widget arrangement, not the website or branding.

## Implemented capabilities

| Area | Live mode | Demonstration mode |
| --- | --- | --- |
| Screen time | Foreground application duration after opt-in; idle/sleep exclusion; day/week/month summaries | 6h 42m sample day, with seven days of activity |
| Applications | Icons, active time share, activity periods, last-active date; editable categories | Xcode, Logic Pro, Steam and Safari |
| System | CPU deltas; active/wired/compressed memory estimate; battery charge/state; home volume storage; interface transfer rates; uptime | CPU 18%, memory 46%, battery 82%, sample storage and rates |
| History | SQLite activity records, minute performance samples and launch/idle/sleep/wake events | In-memory sample activity, a sample wake event and chart series |
| Codex | Explicit local JSONL metadata import: project basename, dates, aggregate token counts and session span | 12 sessions across four projects, illustrative usage window |
| Subscription | “Subscription usage unavailable”; shortcut to official usage settings | Fictional usage percentage and reset countdown, clearly labeled |
| Data controls | CSV export, rolling 30/90/365-day retention, deletion of activity, samples and Codex metadata | Separate demo export filename; never written to the live database |

System metrics update every five seconds. Performance charts retain about ten minutes in memory; one sample per minute is persisted only while live recording is enabled. Activity periods coalesce while the same application remains active. Launch, sleep, wake and idle events are only stored during enabled live recording. Daily aggregates are computed from raw intervals, including splitting intervals at day boundaries; they are not stored as a second source of truth.

## Privacy and integrations

History is stored in `~/Library/Application Support/MacPulse/activity.sqlite` and local preferences in UserDefaults. No usage history is transmitted. Monitoring does not read window titles, keystrokes, browser history or screenshots. No Accessibility or Screen Recording permission is requested. Activity cannot be reconstructed from before monitoring started.

Codex import is explicit and folder-scoped. Choose `~/.codex/sessions` or a directory containing exported session JSONL. The parser recognizes `session_meta` and `event_msg/token_count` metadata, ignores unknown events, and tolerates partial lines. These local formats are version-dependent rather than a guaranteed public subscription API. Imports examine up to 500 JSONL files smaller than 16 MB each; messages are read as part of parsing but never retained or uploaded. Full project paths and authentication files are not stored. Reimport to refresh; no background session watcher is installed.

Token totals are local session metadata, **not ChatGPT subscription consumption or API billing**. Session span includes time between events and is **not measured active project work time**. Official usage settings may require you to sign in in your browser. Opening MacPulse itself requires no credentials.

## Tests

On macOS:

```sh
swift test --jobs 4
xcodebuild -project MacPulse.xcodeproj -scheme MacPulse \
  -destination 'platform=macOS' -derivedDataPath build/TestData \
  CODE_SIGNING_ALLOWED=NO test
```

`.github/workflows/macos.yml` runs core tests, native Xcode tests, bundle packaging and artifact upload on a macOS runner when pushed, submitted as a PR or manually dispatched. It has been authored but has not run during this Linux session.

On this prepared Linux cloud machine:

```sh
./scripts/test-linux.sh
```

The portable Swift core exercises SQLite reopen/upsert, retention/deletion, metadata persistence, demo/live isolation, idle/sleep-gap accounting, application switching, midnight splits, weekly totals, CSV escaping and notch state transitions. See [validation details and manual checks](docs/VALIDATION.md).

## Limits and next steps

- macOS build, GUI navigation, native API sampling, launch at login, fullscreen/Spaces behavior, focus behavior, screen hot-plugging, physical notch geometry and visual polish still need verification on a Mac. Syntax parsing is not a macOS build.
- This cloud machine cannot generate a runnable Apple `.app` without macOS, Xcode and Apple's SDK. Use the included Xcode project, local packaging script or CI workflow.
- No subscription API is integrated. Live usage windows, reset timers and 50/80/95% notifications are unavailable. No notification permission is requested. The demo window does not send alerts or imply actual plan limits.
- Memory is an estimate, not Activity Monitor's memory pressure metric. GPU utilization, temperatures, battery health and cycle counts are unavailable and are not fabricated. Network rates sum active non-loopback interfaces and can count overlapping VPN/bridge traffic.
- Foreground tracking uses five-second polling plus activation events and a 60-second idle threshold. The short idle grace period counts as active; gaps over 15 seconds are never backfilled. No OS Screen Time database integration is attempted.
- CSV contains activity intervals. Imported Codex metadata and system samples are retained/deleted locally but are not included in the activity CSV. Categories are editable; custom category creation is not included.
- There is no WidgetKit extension, screenshot capture, keystroke logger, privileged helper, auto-update system or remote service.
- For a release: complete the manual matrix, fix macOS compile/runtime findings, profile on Apple Silicon, add GUI tests, improve idle-boundary accuracy, add supported subscription integration if one becomes available, and sign/notarize for distribution.

## Source layout

`Sources/MacPulse/Application` handles lifecycle, preferences and coordination; `Notch` owns panel geometry and interactions; `Monitoring` owns macOS sampling and opt-in import; `Interface` contains the dashboard and components. `Sources/MacPulseCore` holds platform-independent models, analytics, tracking, parsing and SQLite storage. `Tests/MacPulseCoreTests` is shared by Swift Package Manager and Xcode.
