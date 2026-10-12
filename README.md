# MacPulse 0.2

A native macOS utility for a quiet notch control center, local computer activity, historical insights, system metrics and Codex analytics. SwiftUI, AppKit, Swift Charts and SQLite; no web UI or development server.

This upgrade preserves `com.macpulse.app`, the existing notch controller, saved preference keys and the original SQLite history. See [the development audit](DEVELOPMENT_AUDIT.md) and [validation and remaining Mac checks](docs/VALIDATION.md) for evidence and limits. A local-development build is not a notarized public release.

## Install and launch

Requires macOS 14+ and full Xcode 15+ to build; Apple Silicon is recommended. The project uses your installed Xcode SDK.

1. Download the repository and open **MacPulse.xcodeproj**.
2. Select **MacPulse → My Mac**, then press **⌘R**.
3. Explore **Demo mode**. Turn it off in Settings for real system metrics, and enable **Record application activity** to start a local history.

For a standalone bundle, run once from the repository:

```sh
./scripts/build-app.sh
```

The exact output is `build/MacPulse.app`. Drag it to Applications, then open it normally. The script generates an icon and verifies an ad hoc signature; it does not notarize or disable macOS security settings. Select full Xcode in Xcode → Settings → Locations if command-line tools point to a standalone installation. No Terminal or server is needed for routine launches. Downloaded CI bundles are unnotarized; macOS may require app-specific approval in System Settings → Privacy & Security. Confirm the artifact comes from your intended repository commit; do not disable Gatekeeper or SIP.

The [GitHub Actions workflow](https://github.com/tigbittyboy-jpg/MacPulse-menubar/actions) builds/tests on macOS and uploads `MacPulse-macOS.zip` inside the **MacPulse-validation** artifact when packaging succeeds. Only download an artifact from a successful run for the commit you intend to use.

## What's new

| Page | Useful information and controls |
| --- | --- |
| Overview | Current app and period duration; daily screen time and observed-day average; recorded comparison with yesterday; development time; system pulse; app ranking; category chart; day timeline; recent computer sessions |
| Screen Time | Ending date and week/month range; app/category filtering; observed-day averages; stacked category history; active/idle/sleep timeline with hover details and segment detail sheets |
| Codex | Optional official subscription windows; refresh/reset status; remaining percentage; measured local session counts; project leaderboard; last reported model; cached/input/output tokens; session and recorded usage histories |
| Applications | Today/week/month totals; sort by duration/name/last-used/period count; average/longest period; shares and icons; persistent category editing |
| System | Normalized CPU and recent average/peak; memory estimate, compressed memory, swap and OS pressure signal; battery; storage; network rates and sampled totals; uptime; historical sample selection; process CPU averages and resident memory |
| Sessions | Explicit persisted computer sessions; active/idle/sleep totals and switch count; date/app filters; detail sheets with timelines and app breakdowns; lifecycle events |
| Insights | Rolling seven-day recap; category balance; most active observed day; conditional preceding-week comparison; average completed-session active time; personal records; recap export |
| Settings | Recording, retained history, exclusions, login registration, menu bar/notch visibility, hover delay, compact indicator/default tab, sampling/idle thresholds, CLI connection/refresh/alerts, appearance/accent/density, export and diagnostics |

Charts and cards identify Live, Historical, Estimated, Demo and Unavailable data. Permission Required is an explicit supported source state, although ordinary activity and system collection do not need extra privacy permissions. Missing historical days stay unknown; a blank chart date does not mean zero usage. Historical comparisons describe **recorded time**, including partial-day coverage, not reconstructed OS Screen Time.

## Notch and menu bar

The existing safe-area based panel and spring behavior remain. Hover a side indicator for a preview; click to expand Overview, Codex or Activity. Open the dashboard with the arrow; click outside or use the close control to collapse. Escape works when MacPulse receives keyboard events; global keyboard monitoring is not requested.

Settings can choose a collapsed activity/CPU/battery/session/Codex indicator, the default tab, CPU ring visibility, hover behavior and animation settings. Demo statistics are explicitly labeled, including the collapsed indicator. System Reduce Motion and the reduced-effects preference are respected.

A notched display is preferred. Other displays use a control center below the menu bar icon. Disabling the physical notch still permits the menu bar fallback. Closing/minimizing the dashboard reduces sampling and leaves the utility running; the Dock icon reopens it. Turning off both menu bar and notch visibility leaves the Dock dashboard available.

Now Playing has an honest unavailable state that can be hidden. No universal private media API, pretend track, nonfunctional playback control or mandatory Automation permission is included.

## Tracking and history

Recording is opt-in and the saved preference resumes on launch. Foreground observations run every two seconds plus NSWorkspace activation/termination events. Duration uses system uptime to validate wall-clock timestamps. Rapid switches are accounted against the preceding app; exclusions do not erase its final interval. Detected idle is clipped at the configured threshold. The idle grace period before that threshold still counts as active; resumption between polls is conservative. Gaps over 15 seconds and significant wall-clock jumps are omitted rather than backfilled.

Computer sessions start when recording is enabled and close on pause/quit. Observed sleep/wake interruptions are recorded inside the session. After an unexpected exit, an open session closes at its last stored observation; downtime is not reconstructed. Session events and records are distinct from Codex session spans.

SQLite uses atomic activity/state/session transactions, WAL, duplicate-ID upserts, versioned additive schema changes, indexes and configurable rolling 30/90/365-day retention. Existing records are preserved. Unreadable JSON rows are omitted with diagnostics while their originals remain in storage; a future schema version is refused without a reset. Existing historical activity is not fabricated into computer sessions; explicit session history starts with this upgrade.

Daily totals are derived from intervals at local calendar boundaries, including 23/25-hour daylight-saving days. There is no second stored daily aggregate that can drift from the underlying intervals. The UI loads up to 5,000 recent minute samples; full JSON exports can include up to 600,000 retained samples. Extended sessions, events and interval tables have bounded loading limits; retained records remain in SQLite until pruning or explicit deletion.

## Codex: two different data sources

### Local metadata

In Live mode, choose **Import local session metadata** and select your Codex sessions folder, usually `~/.codex/sessions`. Imports merge by session ID, preserve prior metadata, tolerate partial/unknown events, skip unreadable/oversized/symlink files, and report skipped files. The scan recognizes up to 1,000 JSONL files under 16 MB each; directory enumeration order is not a guarantee that this is the newest 1,000 files.

Only session ID, project **basename**, timestamps, last reported model and available aggregate token counts are retained. No prompt/response text, auth file or full project path is saved or uploaded. Excluded project basenames are hidden from reports and new imports; delete history to remove already stored metadata. Reimport to refresh; no automatic filesystem watcher is installed.

Local JSONL formats are version-dependent. Missing token/model values remain unavailable. Session span includes event gaps and is **not measured active project work**. Last reported model is not a complete model-by-model token attribution. Local tokens are **not ChatGPT plan consumption or API billing**.

### Official subscription windows — optional

Choose the installed official **Codex CLI executable** in Settings and click **Read allowance**. The CLI must already be signed in through its own supported authentication flow. MacPulse does not request, extract, store or copy credentials.

The adapter starts a short-lived `codex app-server` process, sends `initialize`, `initialized`, and the documented `account/rateLimits/read` request, then stops its owned process. It does not create threads/turns, execute tools or scrape browser cookies. It uses backend-reported multi-bucket windows and reset times without hardcoded plan limits. Unsupported CLI versions, API-only accounts, request failures and missing windows produce an unavailable state. A previous reading is marked Historical/stale rather than silently presented as current.

Opt-in refresh is every five minutes. Alerts at a selectable 50/80/95% threshold require fresh authenticated data and a known future reset; they are deduplicated per window/reset/threshold and never run from demo or stale data. Notification permission is requested only when you enable alerts. Consumption projection appears only with increasing readings for the same reset window separated by at least five minutes and is labeled an estimate.

The protocol was inspected in [OpenAI's official generated schema](https://github.com/openai/codex/blob/a9b0815167c27ab13719dd12d13b63e02b70d221/codex-rs/app-server-protocol/schema/typescript/v2/GetAccountRateLimitsResponse.ts). See [integration notes](docs/INTEGRATIONS.md). Real authenticated end-to-end usage on your Mac still needs validation; deterministic protocol tests do not prove your particular CLI/account supports it.

## System monitoring and power use

Mach aggregate CPU ticks provide a 0–100% normalized total. Active/wired/compressed VM pages provide a memory **estimate**, not an arbitrary pressure score. Compressed memory and swap are shown when reported. Native memory-pressure events remain unavailable until a signal arrives. IOKit supplies battery charge/charging state; volume values supply storage. No root access is required.

Slow queries are cached: memory at least three seconds, battery fifteen seconds, storage sixty seconds. Configurable CPU/network sampling slows to at least ten seconds with hidden views and fifteen seconds in Low Power Mode. Queries run in a monitoring actor; visible chart history is bounded. One performance sample per minute is retained only while live activity recording is enabled. Hidden charts do not accumulate a dense visual buffer.

Network rates use individual interface deltas, skipping new/reset/wrapped counters and long sleep gaps. Observed transfer totals cover sampled periods since launch, not all historical network traffic; VPN/bridge interfaces may still overlap bytes. Process information refreshes only while the System dashboard is visible, at most every fifteen seconds. Process CPU is the system tool's lifetime average and may exceed 100% on multicore workloads; resident memory is shown, and arguments are not collected.

GPU utilization, temperatures, battery health/cycle counts and reliable discharge-time estimates remain unavailable. No readings are invented. Background CPU/memory/battery impact still needs profiling on actual Apple Silicon hardware.

## Privacy and export

Data lives in `~/Library/Application Support/MacPulse/activity.sqlite`; preferences and a bounded diagnostic log live in UserDefaults. Activity history is never uploaded. Optional CLI allowance refresh uses Codex's own authenticated service connection. No screenshots, key logging, window-title collection or browser-history collection occurs during ordinary use.

Exports support activity, daily totals, weekly recap, application analytics, computer sessions and Codex metadata as CSV. Full JSON includes source labels, activity, sessions, idle/sleep intervals, system samples, metadata and recorded allowance readings. Unknown CSV values remain blank; spreadsheet-formula prefixes are escaped. Demo exports have separate names and never contain the live history. Deleting live history requires confirmation and preserves preferences; if recording remains enabled, a new empty session starts afterward.

## Development and validation

On the prepared Linux cloud machine:

```sh
./scripts/bootstrap-linux.sh  # only if tools are missing
./scripts/test-linux.sh
```

On macOS:

```sh
swift test --jobs 4
xcodebuild -project MacPulse.xcodeproj -scheme MacPulse \
  -destination 'platform=macOS' -derivedDataPath build/TestData \
  CODE_SIGNING_ALLOWED=NO test
./scripts/build-app.sh
```

UI tests use an isolated temporary database and test-only preference domain:

```sh
xcodebuild -project MacPulse.xcodeproj -scheme MacPulse-UI \
  -destination 'platform=macOS' -derivedDataPath build/UIData \
  -resultBundlePath build/UITests.xcresult CODE_SIGNING_ALLOWED=NO test
```

They exercise navigation, capture page screenshots and toggle demo/recording. UI test availability depends on the runner's GUI/automation permissions. No UI test outcome or visual review is claimed merely because these tests exist. The workflow uploads logs, a successfully generated app ZIP, and UI result bundles separately. `scripts/sync-xcode-project.py --check` verifies source registration; run it without `--check` after adding a Swift file.

## Remaining release checks

See `docs/VALIDATION.md` for the current run results and exact pending checks. In particular: physical notch alignment, fullscreen/Spaces, auto-hidden menu bars, scaling/hot-plug recovery, focus, long labels, chart interactions, idle accuracy, launch-at-login approval, authenticated Codex reads/notifications, rendered visual inspection and extended resource profiling require Mac verification. Detailed session sheets currently show the start day's timeline; sessions spanning multiple dates remain represented in their aggregate totals and daily Screen Time timelines.

The API adapter is read-only and optional; media integration, per-project foreground attribution, precise per-app activation counts, universal historical OS Screen Time import, custom category creation, auto-update, public distribution signing and notarization are not included. The app uses editable default categories, including Utilities, without claiming unsupported productivity scores.
