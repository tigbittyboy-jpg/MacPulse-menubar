# Integration contracts

## Official Codex app-server

Source inspected: OpenAI `openai/codex` commit `a9b0815167c27ab13719dd12d13b63e02b70d221`.

- `codex-rs/app-server-protocol/src/protocol/common.rs`: `initialize`, `initialized`, `account/rateLimits/read`.
- `schema/typescript/InitializeParams.ts`, `ClientInfo.ts`: client name/title/version and optional capabilities.
- `schema/typescript/v2/GetAccountRateLimitsResponse.ts`, `RateLimitSnapshot.ts`, `RateLimitWindow.ts`: `rateLimitsByLimitId`, backward-compatible `rateLimits`, optional primary/secondary windows, `usedPercent`, `windowDurationMins`, `resetsAt`.

Client initialization does not enable experimental APIs. The initialized notification has no params. Requests use newline-delimited JSON over stdin/stdout. Only a matching response ID is accepted. Errors, missing windows, invalid percentages, malformed JSON or a bounded timeout cause an unavailable result. Other notifications are ignored; no new turns or tool requests are sent. The selected executable is passed directly to Process rather than interpolated into a shell command. Opaque backend account IDs are retained only as allowance-history scope; raw responses and authentication tokens are not persisted.

The owned app-server process is shut down at the end of each request. This adapter is optional and user-authorized. Its read is exercised against deterministic fake child processes in tests; real account/network/CLI compatibility must be checked on the user's Mac. If an installed version requires a different handshake or does not support the method, update the adapter against that version's documented schema rather than using an internal web endpoint or a guessed limit.

Allowance readings are separate from local session tokens. They are marked stale on refresh failure, restart or after ten minutes; reset expiry is never interpreted as a newly refreshed allowance. Alerts require fresh live data and a known reset. Projections require increasing observations for the same known backend account and matching reset; no projection is inferred from zero or missing history.

## Local Codex JSONL

Only `session_meta`, `turn_context/model` and `event_msg/token_count` metadata is decoded. Other payloads are ignored and never saved. `total_token_usage` provides available input/output/cached input values; unknown and negative values remain unavailable. Timestamps support ISO8601 with or without fractional seconds. Project paths are reduced to basenames. This is version-dependent local metadata rather than a stable subscription API.

## Native macOS

NSWorkspace supplies foreground identity and lifecycle events. CGEventSource supplies time since input without recording the input itself. ProcessInfo uptime checks duration independently of wall-clock jumps. Mach host counters supply normalized CPU and VM estimates. IOKit power sources and Foundation volume resource values supply battery/storage. Interface counters and the system process listing are read without privileged helpers. Dispatch memory-pressure events supply a signal only when reported; no invented pressure score is assigned.

## Media

No supported provider-specific media adapter has been connected in this upgrade. Now Playing remains explicitly unavailable. The optional status row can be hidden. No private MediaRemote framework or automatic Music/Spotify Automation access is used.
