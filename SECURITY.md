# Security Policy

Whisker is designed for private networks. Run the server only on a trusted LAN, direct Tailscale IP, or Tailscale Serve endpoint. Do not expose the raw FastAPI service to the public internet.

## Supported Versions

Security fixes target the current `main` branch until formal releases exist.

## Reporting

Open a private advisory or contact the maintainer before publishing details for issues that expose tokens, transcripts, audio uploads, or server execution paths.

## Hardening Checklist

- Set `WHISKER_AUTH_TOKEN` to at least 32 random characters before starting the server.
- Keep `WHISKER_BIND_HOST=127.0.0.1` unless you intentionally expose the server to LAN or Tailscale.
- Prefer Tailscale or another private overlay network for phone-to-Mac access.
- Keep server logs out of transcript and raw-audio content.
- Rotate the bearer token if it is shared in screenshots, logs, demos, or support requests.
- Put any public deployment behind TLS, authentication, rate limits, request-size limits, and reviewed access logs.

## Data Handling

The server writes uploads to a temporary request directory, converts them for inference, and deletes the directory after the request finishes. The client deletes temporary recordings after transcription. Saved transcript history is local to the iPhone app and can be disabled in Settings.
