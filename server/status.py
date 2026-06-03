from __future__ import annotations

import html
import threading
import time
from dataclasses import dataclass
from typing import Any, Optional

from .config import ServerConfig


@dataclass(frozen=True)
class RequestStatus:
    total: int
    succeeded: int
    failed: int
    last_at: Optional[float]
    last_status_code: Optional[int]
    last_model_id: Optional[str]
    last_engine: Optional[str]
    last_model: Optional[str]
    last_duration_seconds: Optional[float]
    last_processing_seconds: Optional[float]


class StatusMetrics:
    def __init__(self, started_at: Optional[float] = None) -> None:
        self.started_at = time.time() if started_at is None else started_at
        self._lock = threading.Lock()
        self._total = 0
        self._succeeded = 0
        self._failed = 0
        self._last_at: Optional[float] = None
        self._last_status_code: Optional[int] = None
        self._last_model_id: Optional[str] = None
        self._last_engine: Optional[str] = None
        self._last_model: Optional[str] = None
        self._last_duration_seconds: Optional[float] = None
        self._last_processing_seconds: Optional[float] = None

    def record_success(
        self,
        *,
        now: Optional[float] = None,
        model_id: str,
        engine: str,
        model: str,
        duration_seconds: float,
        processing_seconds: float,
    ) -> None:
        with self._lock:
            self._total += 1
            self._succeeded += 1
            self._last_at = time.time() if now is None else now
            self._last_status_code = 200
            self._last_model_id = model_id
            self._last_engine = engine
            self._last_model = model
            self._last_duration_seconds = duration_seconds
            self._last_processing_seconds = processing_seconds

    def record_failure(
        self,
        *,
        now: Optional[float] = None,
        status_code: int,
        model_id: Optional[str] = None,
        engine: Optional[str] = None,
        model: Optional[str] = None,
    ) -> None:
        with self._lock:
            self._total += 1
            self._failed += 1
            self._last_at = time.time() if now is None else now
            self._last_status_code = status_code
            self._last_model_id = model_id
            self._last_engine = engine
            self._last_model = model
            self._last_duration_seconds = None
            self._last_processing_seconds = None

    def snapshot(self) -> RequestStatus:
        with self._lock:
            return RequestStatus(
                total=self._total,
                succeeded=self._succeeded,
                failed=self._failed,
                last_at=self._last_at,
                last_status_code=self._last_status_code,
                last_model_id=self._last_model_id,
                last_engine=self._last_engine,
                last_model=self._last_model,
                last_duration_seconds=self._last_duration_seconds,
                last_processing_seconds=self._last_processing_seconds,
            )


def build_status_payload(
    *,
    config: ServerConfig,
    default_engine_name: str,
    default_engine_model: str,
    default_engine_available: bool,
    metrics: StatusMetrics,
    now: Optional[float] = None,
) -> dict[str, Any]:
    current_time = time.time() if now is None else now
    request_status = metrics.snapshot()
    return {
        "ok": default_engine_available,
        "server": config.server_name,
        "version": config.version,
        "uptime_seconds": round(max(0.0, current_time - metrics.started_at), 3),
        "engine": default_engine_name,
        "model": default_engine_model,
        "default_model_id": config.default_model_id,
        "models": [
            {
                "id": profile.id,
                "label": profile.label,
                "engine": profile.engine,
                "model": profile.model,
                "speed": profile.speed,
                "description": profile.description,
            }
            for profile in config.model_profiles
        ],
        "cleanup": list(config.cleanup_modes),
        "max_duration_seconds": config.max_duration_seconds,
        "requests": {
            "total": request_status.total,
            "succeeded": request_status.succeeded,
            "failed": request_status.failed,
            "last_at": request_status.last_at,
            "last_status_code": request_status.last_status_code,
            "last_model_id": request_status.last_model_id,
            "last_engine": request_status.last_engine,
            "last_model": request_status.last_model,
            "last_duration_seconds": request_status.last_duration_seconds,
            "last_processing_seconds": request_status.last_processing_seconds,
        },
    }


def render_status_html(payload: dict[str, Any]) -> str:
    def esc(value: Any) -> str:
        if value is None:
            return "none"
        return html.escape(str(value), quote=True)

    models = "\n".join(
        "<tr>"
        f"<td>{esc(model['id'])}</td>"
        f"<td>{esc(model['label'])}</td>"
        f"<td>{esc(model['engine'])}</td>"
        f"<td>{esc(model['model'])}</td>"
        f"<td>{esc(model['speed'])}</td>"
        "</tr>"
        for model in payload["models"]
    )
    requests = payload["requests"]
    status_class = "ok" if payload["ok"] else "bad"
    status_text = "available" if payload["ok"] else "unavailable"

    return f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Whisker Status</title>
  <style>
    :root {{
      color-scheme: light dark;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      background: Canvas;
      color: CanvasText;
    }}
    body {{ margin: 0; padding: 28px; }}
    main {{ max-width: 920px; margin: 0 auto; }}
    h1 {{ font-size: 28px; margin: 0 0 18px; }}
    h2 {{ font-size: 17px; margin: 26px 0 10px; }}
    .grid {{
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
      gap: 10px;
    }}
    .metric {{
      border: 1px solid color-mix(in srgb, CanvasText 18%, transparent);
      border-radius: 8px;
      padding: 12px;
    }}
    .label {{ color: GrayText; font-size: 12px; text-transform: uppercase; }}
    .value {{ font-size: 18px; margin-top: 4px; overflow-wrap: anywhere; }}
    .ok {{ color: #0a7f42; }}
    .bad {{ color: #c2272d; }}
    table {{ width: 100%; border-collapse: collapse; }}
    th, td {{
      text-align: left;
      border-bottom: 1px solid color-mix(in srgb, CanvasText 16%, transparent);
      padding: 8px 6px;
      vertical-align: top;
      overflow-wrap: anywhere;
    }}
    th {{ color: GrayText; font-weight: 600; font-size: 12px; }}
  </style>
</head>
<body>
  <main>
    <h1>Whisker Status</h1>
    <section class="grid">
      <div class="metric"><div class="label">Server</div><div class="value">{esc(payload["server"])}</div></div>
      <div class="metric"><div class="label">Health</div><div class="value {status_class}">{status_text}</div></div>
      <div class="metric"><div class="label">Default</div><div class="value">{esc(payload["default_model_id"])}</div></div>
      <div class="metric"><div class="label">Model</div><div class="value">{esc(payload["model"])}</div></div>
      <div class="metric"><div class="label">Uptime</div><div class="value">{esc(payload["uptime_seconds"])}s</div></div>
      <div class="metric"><div class="label">Max Duration</div><div class="value">{esc(payload["max_duration_seconds"])}s</div></div>
    </section>
    <h2>Requests</h2>
    <section class="grid">
      <div class="metric"><div class="label">Total</div><div class="value">{esc(requests["total"])}</div></div>
      <div class="metric"><div class="label">Succeeded</div><div class="value">{esc(requests["succeeded"])}</div></div>
      <div class="metric"><div class="label">Failed</div><div class="value">{esc(requests["failed"])}</div></div>
      <div class="metric"><div class="label">Last Status</div><div class="value">{esc(requests["last_status_code"])}</div></div>
      <div class="metric"><div class="label">Last Model</div><div class="value">{esc(requests["last_model_id"])}</div></div>
      <div class="metric"><div class="label">Last Processing</div><div class="value">{esc(requests["last_processing_seconds"])}s</div></div>
    </section>
    <h2>Models</h2>
    <table>
      <thead><tr><th>ID</th><th>Label</th><th>Engine</th><th>Model</th><th>Speed</th></tr></thead>
      <tbody>{models}</tbody>
    </table>
  </main>
</body>
</html>"""
