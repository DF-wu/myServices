#!/usr/bin/env python3
"""Small OpenAI-compatible mock server for client integration checks."""

from __future__ import annotations

import argparse
import json
import time
from email.parser import BytesParser
from email.policy import default
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


WAV_BYTES = (
    b"RIFF$\x00\x00\x00WAVEfmt "
    b"\x10\x00\x00\x00\x01\x00\x01\x00@\x1f\x00\x00\x80>\x00\x00\x02\x00\x10\x00"
    b"data\x00\x00\x00\x00"
)


class Handler(BaseHTTPRequestHandler):
    server_version = "DFVoiceMock/1.0"

    def do_OPTIONS(self) -> None:
        self.send_response(204)
        self._cors()
        self.end_headers()

    def do_GET(self) -> None:
        if self.path == "/v1/models":
            self._maybe_delay()
            self._json(
                {
                    "object": "list",
                    "data": [
                        {"id": "mock-chat", "object": "model", "owned_by": "df-voice"},
                        {"id": "mock-response", "object": "model", "owned_by": "df-voice"},
                    ],
                }
            )
            return
        self.send_error(404)

    def do_POST(self) -> None:
        if self.path == "/v1/audio/transcriptions":
            fields = self._multipart_fields()
            if not self._request_options_ok("asr", fields=fields):
                return
            self._maybe_delay()
            response_format = fields.get("response_format", "json")
            text = "Mock ASR transcript."
            if response_format == "text":
                self._text(text)
            elif response_format == "srt":
                self._text("1\n00:00:00,000 --> 00:00:01,000\nMock ASR transcript.\n", "application/x-subrip")
            elif response_format == "vtt":
                self._text("WEBVTT\n\n00:00:00.000 --> 00:00:01.000\nMock ASR transcript.\n", "text/vtt")
            elif response_format == "verbose_json":
                self._json(
                    {
                        "task": "transcribe",
                        "language": fields.get("language", "zh"),
                        "duration": 1.0,
                        "text": text,
                        "segments": [
                            {"id": 0, "seek": 0, "start": 0.0, "end": 1.0, "text": text}
                        ],
                        "words": [{"word": "Mock", "start": 0.0, "end": 1.0}],
                    }
                )
            else:
                self._json({"text": text})
            return

        payload = self._payload()
        if self.path == "/v1/chat/completions":
            if not self._request_options_ok("conversation", payload=payload):
                return
            self._maybe_delay()
            if payload.get("stream"):
                self._sse(
                    [
                        {"choices": [{"delta": {"content": "Mock "}}]},
                        {"choices": [{"delta": {"content": "chat "}}]},
                        {"choices": [{"delta": {"content": "stream."}}]},
                    ]
                )
            else:
                self._json(
                    {
                        "choices": [
                            {"message": {"role": "assistant", "content": "Mock chat response."}}
                        ]
                    }
                )
            return

        if self.path == "/v1/responses":
            if not self._request_options_ok("conversation", payload=payload):
                return
            self._maybe_delay()
            if payload.get("stream"):
                self._sse(
                    [
                        {"type": "response.output_text.delta", "delta": "Mock "},
                        {"type": "response.output_text.delta", "delta": "responses "},
                        {"type": "response.output_text.delta", "delta": "stream."},
                        {
                            "type": "response.completed",
                            "output_text": "Mock responses stream.",
                        },
                    ],
                    event="response.output_text.delta",
                )
            else:
                self._json({"output_text": "Mock responses output."})
            return

        if self.path == "/v1/audio/speech":
            if not self._request_options_ok("tts", payload=payload):
                return
            self._maybe_delay()
            self.send_response(200)
            self._cors()
            self.send_header("Content-Type", "audio/wav")
            self.send_header("Content-Length", str(len(WAV_BYTES)))
            self.end_headers()
            self._write(WAV_BYTES)
            return

        self.send_error(404)

    def log_message(self, fmt: str, *args: object) -> None:
        return

    def _payload(self) -> dict:
        length = int(self.headers.get("content-length", "0") or 0)
        if not length:
            return {}
        raw = self.rfile.read(length)
        try:
            return json.loads(raw.decode("utf-8"))
        except json.JSONDecodeError:
            return {}

    def _multipart_fields(self) -> dict[str, str]:
        length = int(self.headers.get("content-length", "0") or 0)
        content_type = self.headers.get("content-type", "")
        if not length or "multipart/form-data" not in content_type:
            return {}
        body = self.rfile.read(length)
        message = BytesParser(policy=default).parsebytes(
            f"Content-Type: {content_type}\r\n\r\n".encode("utf-8") + body
        )
        fields: dict[str, str] = {}
        for part in message.iter_parts():
            name = part.get_param("name", header="content-disposition")
            if not name or part.get_filename():
                continue
            content = part.get_content()
            fields[name] = content if isinstance(content, str) else str(content)
        return fields

    def _request_options_ok(
        self,
        scope: str,
        *,
        fields: dict[str, str] | None = None,
        payload: dict | None = None,
    ) -> bool:
        marker = self.headers.get("x-df-voice-test")
        if not marker:
            return True
        if marker != scope:
            self._json({"error": {"message": f"unexpected test header {marker}"}}, status=400)
            return False
        if scope == "asr":
            fields = fields or {}
            if fields.get("provider_hint") != "asr-extra":
                self._json({"error": {"message": "missing ASR extra form field"}}, status=400)
                return False
        elif scope == "conversation":
            metadata = (payload or {}).get("metadata")
            if not isinstance(metadata, dict) or metadata.get("test") != "conversation-extra":
                self._json({"error": {"message": "missing conversation extra body"}}, status=400)
                return False
        elif scope == "tts":
            if (payload or {}).get("provider_hint") != "tts-extra":
                self._json({"error": {"message": "missing TTS extra body"}}, status=400)
                return False
        return True

    def _cors(self) -> None:
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header(
            "Access-Control-Allow-Headers",
            "authorization,content-type,x-df-voice-delay-ms,x-df-voice-test",
        )
        self.send_header("Access-Control-Allow-Methods", "GET,POST,OPTIONS")

    def _maybe_delay(self) -> None:
        value = self.headers.get("x-df-voice-delay-ms")
        if not value:
            return
        try:
            delay = max(0, min(5000, int(value))) / 1000
        except ValueError:
            return
        time.sleep(delay)

    def _json(self, data: dict, status: int = 200) -> None:
        body = json.dumps(data).encode("utf-8")
        self.send_response(status)
        self._cors()
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self._write(body)

    def _text(self, text: str, content_type: str = "text/plain") -> None:
        body = text.encode("utf-8")
        self.send_response(200)
        self._cors()
        self.send_header("Content-Type", f"{content_type}; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self._write(body)

    def _sse(self, payloads: list[dict], event: str | None = None) -> None:
        self.send_response(200)
        self._cors()
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()
        try:
            for payload in payloads:
                if event:
                    self.wfile.write(f"event: {event}\n".encode("utf-8"))
                self.wfile.write(f"data: {json.dumps(payload)}\n\n".encode("utf-8"))
                self.wfile.flush()
                time.sleep(0.03)
            self.wfile.write(b"data: [DONE]\n\n")
            self.wfile.flush()
        except BrokenPipeError:
            return

    def _write(self, body: bytes) -> None:
        try:
            self.wfile.write(body)
        except BrokenPipeError:
            return


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8099)
    args = parser.parse_args()

    server = ThreadingHTTPServer((args.host, args.port), Handler)
    print(f"mock OpenAI-compatible server on http://{args.host}:{args.port}", flush=True)
    server.serve_forever()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
