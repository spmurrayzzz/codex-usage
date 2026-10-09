# AGENTS.md

Codex Usage is a small SwiftUI macOS app (no Xcode project; Swift Package + Makefile) that shows the user's ChatGPT/Codex account usage in one window, launched from Alfred.

## Build and verify

- `make app` — release build, assembles `CodexUsage.app`, ad-hoc codesigns it.
- `make install` — also copies to `~/Applications/CodexUsage.app` (Alfred search path).
- `make run` — debug run from source.
- `make icon` — regenerates `Resources/AppIcon.icns` from `Scripts/MakeIcon.swift` (auto-run by `make app` when missing).
- Headless check of the data path: `CodexUsage.app/Contents/MacOS/CodexUsage --dump`.
- The window is resizable only upward; content min-height drives the window min-size.
- To reset the remembered window frame: quit the app, then `defaults delete dev.spmurray.codex-usage`.
- Screenshot the live window without stealing focus: find the window id with a CGWindowList one-liner (owner name "Codex Usage"), then `screencapture -o -x -l <id> out.png`.

## Architecture

Single executable target `CodexUsage` (`Sources/CodexUsage/`):

- `main.swift` — entry; runs `--dump` mode via a detached task, else launches the app.
- `CodexUsageApp.swift` — `Window` scene, `defaultSize` 380×600, `.contentMinSize`.
- `UsageModel.swift` — `@MainActor ObservableObject`; 60s auto-refresh loop, manual refresh; `hardError` (no data yet) vs `softWarning` (stale data, last refresh failed).
- `UsageView.swift` — all UI: hero card with `RingView` (remaining %), section cards (`Card`, `SectionTitle`, `IconChip`), `UsageBar` for secondary/additional windows, status pills, footer.
- `CodexCredentials.swift` — `CodexPaths`, credential load/refresh/persist, `CodexDateParser`, `JSONDecoder.codex()`.
- `CodexUsageClient.swift` — endpoints (`CodexEndpoints.resolve()`), HTTP, fetch errors, `CodexUsageService` (orchestrates load → maybe refresh → usage → reset credits).
- `UsageModels.swift` — response models. All decoding is lossy by design: one malformed field must never fail the whole response.
- `UsageDumper.swift` — `--dump` terminal output.

## Credential and API facts (learned, keep true)

- Credentials live in `$CODEX_HOME/auth.json` (default `~/.codex/auth.json`). `auth_mode: "chatgpt"` means use `tokens` (access/refresh/id/account_id). `auth_mode: "apikey"` means use `OPENAI_API_KEY`. Also support `personal_access_token` (PAT). The auth file can contain both keys; `auth_mode` disambiguates.
- Refresh: `POST https://auth.openai.com/oauth/token`, JSON body `{client_id: "app_EMoamEEZ73f0CkXaXp7hrann", grant_type: "refresh_token", refresh_token, scope: "openid profile email"}`. This rotates the refresh token, so only call it when the access token JWT `exp` is within 5 minutes, the file is older than 8 days, or a usage call returned 401 (then retry once). Never refresh in tests.
- Persisting refreshed tokens: merge into existing `auth.json`, rewrite `tokens` + `last_refresh` (ISO-8601 UTC), keep all other top-level keys, pretty-print with sorted keys, write to a temp file, chmod 0600, atomic replace.
- Usage: `GET https://chatgpt.com/backend-api/wham/usage` with `Authorization: Bearer`, `Accept: application/json`, `User-Agent: CodexUsage`, optional `ChatGPT-Account-Id`. Base URL can be overridden by `chatgpt_base_url` in `~/.codex/config.toml`; when the normalized base does not contain `/backend-api`, the usage path is `/api/codex/usage` instead.
- Reset credits: `GET {base}/wham/rate-limit-reset-credits` with extra headers `OpenAI-Beta: codex-1` and `originator: "Codex Desktop"`. Only fetch when the usage response has `rate_limit_reset_credits.available_count > 0`.
- Response shape: `rate_limit.primary_window` / `secondary_window` with `used_percent` (Int), `limit_window_seconds`, `reset_at` (epoch seconds). `model_usage` lists only models with special availability state (gated/new/credit-enabled), not the full catalog — do not "fix" a short list. `credits.balance` can be a number or a string. `spend_control.individual_limit` and `additional_rate_limits` are usually null but must decode when present.
- Read-only `GET`s against these endpoints on the user's own account are safe for testing. Token refresh is mutating; do not exercise it against the real account.

## Platform gotchas (macOS 26, verified)

- `ISO8601DateFormatter` with fractional-second options is broken: it returns a `2000-01-01` sentinel instead of `nil` on failure. Setting `formatOptions = []` on any instance also breaks it (always returns the sentinel). Use `CodexDateParser` (default-constructed `ISO8601DateFormatter` plus manual fractional-seconds stripping). Do not reintroduce explicit `formatOptions`.
- `DateComponentsFormatter.string(for: date)` returns nil for far-future dates. Compute `Calendar.current.dateComponents(...)` and use `string(from:)`.
- In a nested-type scope, `catch is NestedError { throw error }` fails to compile (implicit `error` binding not available with a pattern-only catch). Use `catch let caught as NestedError { throw caught }`.
- Result builders reject mutating local statements; hoard `var` building logic into a helper function returning a value.
- SwiftUI `defaultSize` is clamped to the content's min size; the content's ideal frame does not drive the initial window size.

## Conventions

- Swift tools 5.9, deployment target macOS 14. No new dependencies.
- No code comments unless they explain a non-obvious constraint (the API/platform facts above qualify).
- Keep the window small and calm: card groups, one accent color, status colors only green/orange/red (remaining ≥30% green, ≥10% orange, else red). No gradients, glows, or decorative motion.
- Bundle id `dev.spmurray.codex-usage`; display name "Codex Usage".
- Upstream reference for API behavior and response evolution: `~/src/tries/2026-10-09-steipete-CodexBar` (CodexBar; see its `Sources/CodexBarCore/Providers/Codex/`).
