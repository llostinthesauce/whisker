---
title: whisker
description: Self-hosted iPhone dictation powered by your own Mac
---

# whisker

**Your iPhone dictates. Your Mac transcribes. Nothing leaves your network.**

Whisker turns an iPhone keyboard into a remote Mac-powered dictation client.
The phone records temporary audio, ships it to your private transcription
server over LAN or Tailscale, and inserts the returned text back into any app.

| iPhone app | Keyboard | Server |
| --- | --- | --- |
| ![Whisker app recorder and status preview](assets/app-status.svg) | ![Whisker keyboard preview](assets/keyboard-session.svg) | ![Whisker server health preview](assets/server-health.svg) |

## Why

- On-device iPhone transcription is slow or unavailable; your Mac is not.
- Stronger Mac-hosted MLX speech models, lightweight phone interface.
- Private by construction: trusted LAN or Tailscale only, bearer-token auth,
  no third-party services, audio deleted after processing.

## Highlights

- **SwiftUI app + custom keyboard extension** with app-group handoff.
- **Switchable MLX engines**: Parakeet TDT (110M / 0.6B) and Qwen3-ASR
  (0.6B 4-bit / 1.7B 8-bit), plus whisper.cpp for portability.
- **Usage stats**: words, audio time, sessions, per-engine breakdown —
  computed from on-device history, never collected or sent anywhere.
- **Cleanup modes**: raw, light, message, email, notes, bullets.
- **LAN-first failover** to a Tailscale endpoint when you leave home.

## Get started

Full setup (server, signing, keyboard) is in the
[README](https://github.com/llostinthesauce/whisker#quick-start).

```sh
git clone https://github.com/llostinthesauce/whisker
cd whisker
python3 -m venv server/.venv
server/.venv/bin/python -m pip install -r server/requirements.txt
cp server/.env.example server/.env   # set WHISKER_AUTH_TOKEN
WHISKER_REMOTE_ROOT="$PWD" server/run_server.sh
```

Then build the iOS app from `Whisker.xcodeproj`, point it at
`http://<mac-ip>:8787`, and dictate.

## More

- [Architecture](https://github.com/llostinthesauce/whisker/blob/main/docs/architecture.md)
- [Security notes](https://github.com/llostinthesauce/whisker/blob/main/SECURITY.md)
- [Server docs](https://github.com/llostinthesauce/whisker/blob/main/server/README.md)
