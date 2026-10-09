---
name: codex-usage-screenshot
description: Re-shoots the Codex Usage README screenshot (assets/readme/codex-usage.png) with mock data, using an isolated CODEX_HOME and a local mock API server so no real account data or network calls are involved. Use when the README screenshot is stale, the app UI changed, or the user asks to capture or re-shoot the Codex Usage window.
---

# Codex Usage Screenshot

Re-shoots `assets/readme/codex-usage.png` from a live app window running on
mock data. The output is a transparent-background PNG with the native window
shadow, at the raw capture size (2x, roughly 900-1000px wide). The README
displays it compactly through an `<img>` tag with `width="538"`, so keep the
asset full-resolution and change the display size in the README if needed.

This skill lives in `.agents/skills/` so any agent can use it; pi finds it
through the `.pi/skills/codex-usage-screenshot` symlink.

## Quick start

```sh
python3 .agents/skills/codex-usage-screenshot/scripts/capture.py
```

The script does the whole capture:

1. Builds `/tmp/codex-usage-demo` with fixture JSON, an isolated `CODEX_HOME`
   (synthetic JWT with `exp` 30 days out, so the token refresh path never
   fires), and a `config.toml` pointing `chatgpt_base_url` at
   `http://127.0.0.1:8931/backend-api`.
2. Serves the fixtures from a local mock server and launches
   `CodexUsage.app/Contents/MacOS/CodexUsage` with `CODEX_HOME` set to the
   demo dir. No real credentials, no real network traffic.
3. Waits until the app fetches both `/wham/usage` and
   `/wham/rate-limit-reset-credits` (data loaded, no spinner).
4. Finds the demo instance's window via CGWindowList (filtered by pid) and
   captures it with `screencapture -x -l <id>`: transparent background,
   native shadow kept.
5. Strips `eXIf`/`Exif`/`xMP`/`iTXt`/`tEXt`/`zTXt` metadata chunks that
   macOS embeds in screenshot PNGs, verifying every remaining chunk CRC.
6. Kills the demo instance and removes `/tmp/codex-usage-demo`.

## Options

| Flag | Default | Purpose |
| --- | --- | --- |
| `--app PATH` | `<repo>/CodexUsage.app` | App bundle to capture (run `make app` if missing) |
| `--out PATH` | `<repo>/assets/readme/codex-usage.png` | Output PNG |
| `--fixtures PATH` | built-in mock | JSON with `usage` and `reset_credits` keys, same shape as `fixtures.json` in the demo dir |
| `--port N` | 8931 | Mock server port |
| `--width N` | 0 (raw) | Resize the capture to N pixels wide; display size is set by the README's `<img>` tag |
| `--keep` | off | Leave the demo dir and app running for inspection |

## Verify (required after every capture)

1. Open the output PNG with the image reader and check:
   - Only mock values are visible (`demo@example.com` by default). No real
     email, account data, or local paths.
   - No spinner, error view, or orange warning banner.
   - No clipping or blur at the chosen display width; ring and bar colors
     follow the app convention (green at >=30% remaining, orange at >=10%,
     red below).
2. Read the script's final line and confirm no sensitive metadata chunks
   (`eXIf`, `xMP`, `iTXt`) remain in the output.

## Custom mock values

Edit `DEFAULT_FIXTURES` in `scripts/capture.py`, or pass `--fixtures` with a
file of the same shape. Date fields are epoch seconds; keep `reset_at` and
credit `expires_at` in the future so relative labels render.

## Failure notes

- `screencapture -l` needs Screen Recording permission for the agent's
  terminal process.
- If a previous run crashed, the script kills the stale demo instance via
  `/tmp/codex-usage-demo/app.pid` before starting. It never touches an
  instance launched without the demo `CODEX_HOME`; use `pgrep -fl
  CodexUsage` to inspect other instances.
- The window frame is remembered in app defaults
  (`dev.spmurray.codex-usage`), so the capture uses whatever size the window
  currently has. Reset it while the app is quit:
  `defaults delete dev.spmurray.codex-usage`.
