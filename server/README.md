# Whisker Remote Server

Generic private ASR server for the Whisker iOS app and keyboard. The iPhone uploads temporary `.caf` audio, the server converts it to 16 kHz mono WAV, runs the configured model, applies optional cleanup, and returns the JSON contract used by the app.

## Defaults

- Engine: `parakeet_mlx`.
- Balanced model: `mlx-community/parakeet-tdt-0.6b-v3`.
- Bind host: `127.0.0.1`.
- Port: `8787`.
- API paths: `GET /health`, `GET /v1/health`, `GET /v1/status`, `GET /status`, and `POST /v1/transcribe`.

Keep this service private. Use a trusted LAN, direct Tailscale IP, or Tailscale Serve. Do not expose the raw FastAPI server to the public internet.

## Platform Notes

The default `parakeet_mlx` backend is intended for Apple Silicon Macs. The FastAPI server code is plain Python and can be developed on Linux, but Linux runtime use needs a Linux-compatible ASR backend such as `whisper.cpp`; the iOS app and keyboard still require macOS with Xcode to build and install.

## Install

```sh
cd ~/src/whisker
python3 -m venv server/.venv
server/.venv/bin/python -m pip install -r server/requirements.txt
cp server/.env.example server/.env
```

Edit `server/.env` and set at least:

```sh
WHISKER_AUTH_TOKEN="<32-plus-random-characters>"
WHISKER_BIND_HOST="127.0.0.1"
WHISKER_PORT="8787"
WHISKER_DEFAULT_MODEL_ID="balanced"
```

Run the server:

```sh
WHISKER_REMOTE_ROOT="$PWD" server/run_server.sh
```

The server fails at startup if `WHISKER_AUTH_TOKEN` is empty or shorter than 32 characters.

## Verify

From the Mac:

```sh
set -a
. server/.env
set +a
curl -sS -H "Authorization: Bearer $WHISKER_AUTH_TOKEN" http://127.0.0.1:8787/health | python3 -m json.tool
```

From the iPhone network path:

```sh
curl -sS -H "Authorization: Bearer $WHISKER_AUTH_TOKEN" http://<mac-ip>:8787/health
```

Runtime metrics (request counts, recent failures, model usage) are available
once the server is up:

```sh
# JSON payload
curl -sS -H "Authorization: Bearer $WHISKER_AUTH_TOKEN" http://127.0.0.1:8787/v1/status | python3 -m json.tool

# HTML status page. Like every endpoint it requires the Authorization header,
# so a plain browser visit returns 401 — fetch it with curl instead.
curl -sS -H "Authorization: Bearer $WHISKER_AUTH_TOKEN" http://127.0.0.1:8787/status
```

Expected `/health` shape:

```json
{
  "ok": true,
  "server": "whisker-server",
  "version": "0.1.0",
  "engine": "parakeet-mlx",
  "model": "parakeet-tdt-0.6b-v3",
  "default_model_id": "balanced",
  "models": [
    {
      "id": "balanced",
      "label": "Balanced",
      "engine": "parakeet_mlx",
      "model": "mlx-community/parakeet-tdt-0.6b-v3",
      "speed": "medium",
      "description": "Current default Parakeet TDT 0.6B v3 model with strong quality and speed."
    }
  ],
  "cleanup": ["raw", "light", "message", "email", "notes", "bullets"],
  "max_duration_seconds": 300.0
}
```

## Tailscale And LAN

Loopback plus Tailscale Serve:

```sh
WHISKER_BIND_HOST="127.0.0.1"
/Applications/Tailscale.app/Contents/MacOS/Tailscale serve --bg 8787
```

Direct LAN:

```sh
WHISKER_BIND_HOST="0.0.0.0"
```

Direct Tailscale IP:

```sh
WHISKER_BIND_HOST="<tailscale-ip>"
```

Use the corresponding `http://<host>:8787` or Tailscale Serve URL in Whisker Settings.

## Model Config Examples

Fast short dictation:

```sh
WHISKER_DEFAULT_MODEL_ID="fast"
WHISKER_FAST_MODEL="mlx-community/parakeet-tdt_ctc-110m"
```

Balanced default:

```sh
WHISKER_DEFAULT_MODEL_ID="balanced"
WHISKER_PARAKEET_MODEL="mlx-community/parakeet-tdt-0.6b-v3"
```

The app can also choose a profile per request. Cleanup mode is independent from model choice.

Temporary benchmark-only profiles can be appended with JSON:

```sh
WHISKER_EXTRA_MODEL_PROFILES='[
  {
    "id": "whisper-turbo",
    "label": "Whisper Large v3 Turbo",
    "engine": "whisper_cpp",
    "model": "ggml-large-v3-turbo.bin",
    "speed": "medium",
    "description": "whisper.cpp large-v3-turbo benchmark candidate."
  }
]'
```

Use `WHISKER_MODEL_PROFILES` with the same JSON shape to replace the default profile list entirely.

## ASR Bakeoff

The repeatable benchmark runner generates deterministic macOS `say` clips, adds pink-noise variants, posts the same WAV files to `/v1/transcribe` with `cleanup_mode=raw`, and writes `results.jsonl`, `summary.json`, raw responses, `health.json`, and `STATUS.md`.

```sh
set -a
. server/.env
set +a
python3 scripts/whisker_asr_bakeoff.py --start-server
```

For an already-running server, expose the requested model profiles first and omit `--start-server`. Use `--models fast,balanced` to benchmark only currently exposed production profile IDs.

## Environment

```text
WHISKER_AUTH_TOKEN              required bearer token
WHISKER_SERVER_NAME             default whisker-server
WHISKER_BIND_HOST               default 127.0.0.1
WHISKER_PORT                    default 8787
WHISKER_MAX_UPLOAD_BYTES        default 83886080; keep above ~60 MB so a full 5-minute CAF fits
WHISKER_MAX_DURATION_SECONDS    default 300; matches the iPhone recording cap
WHISKER_REQUEST_TIMEOUT_SECONDS default 300
WHISKER_WORK_DIR                default ~/Library/Caches/WhiskerRemote
WHISKER_FFMPEG                  default ffmpeg
WHISKER_FFPROBE                 default ffprobe
WHISKER_ENGINE                  default parakeet_mlx
WHISKER_PARAKEET_MODEL          default mlx-community/parakeet-tdt-0.6b-v3
WHISKER_FAST_MODEL              default mlx-community/parakeet-tdt_ctc-110m
WHISKER_DEFAULT_MODEL_ID        default balanced; one of fast, balanced for parakeet_mlx; balanced for whisper_cpp
WHISKER_EXTRA_MODEL_PROFILES    optional JSON array appended to default model profiles
WHISKER_MODEL_PROFILES          optional JSON array replacing default model profiles
WHISKER_PARAKEET_CACHE_DIR      optional Hugging Face model cache directory
WHISKER_DEBUG                   default false
```

## Cleanup Modes

| Mode | Behavior |
| --- | --- |
| `raw` | Returns the transcript exactly as produced by the ASR engine. |
| `light` | Trims leading/trailing whitespace, collapses repeated spaces, and reduces 3+ newlines to 2. |
| `message` | Applies `light`, then capitalizes the first character. |
| `email` | Uses message style in this build. |
| `notes` | Splits sentence-like text onto separate lines. |
| `bullets` | Same sentence split as `notes`, with each sentence prefixed by `- `. |

The repo includes an optional server-side `whisper_cpp` adapter for comparison, but the iPhone app has no local ASR runtime.

## launchd

An example user launch agent lives at [launchd/app.whisker.remote.plist](launchd/app.whisker.remote.plist).

```sh
mkdir -p ~/Library/LaunchAgents
cp server/launchd/app.whisker.remote.plist ~/Library/LaunchAgents/app.whisker.remote.plist
launchctl bootstrap "gui/$(id -u)" ~/Library/LaunchAgents/app.whisker.remote.plist
launchctl kickstart -k "gui/$(id -u)/app.whisker.remote"
```

The plist assumes the repo is at `~/src/whisker`. If your clone is elsewhere, either clone there or edit the plist command to set `WHISKER_REMOTE_ROOT`. Server logs are appended to `~/Library/Logs/whisker-remote-server.log` and `~/Library/Logs/whisker-remote-server.err.log`.

## Privacy Behavior

- All endpoints require `Authorization: Bearer <token>`.
- Raw transcripts and cleaned transcripts are not logged.
- Uploaded audio is written under a temporary request directory and deleted after the request.
- Client filenames are not used for server-side paths.
- The default service only listens on loopback unless configured otherwise.
