#!/usr/bin/env python3
"""Exercise ASR file upload against the mock provider."""

from __future__ import annotations

import os
import pathlib
import struct
import tempfile
import wave

from playwright.sync_api import expect, sync_playwright

from browser_utils import goto_with_retry


CLIENT_URL = os.environ.get("CLIENT_URL", "http://localhost:8081")
MOCK_BASE_URL = os.environ.get("MOCK_BASE_URL", "http://127.0.0.1:8099/v1")
SETTINGS_KEY = "df-voice-app.settings.v1"
WORKSPACE_KEY = "df-voice-app.workspace.v1"
ROOT = pathlib.Path(__file__).resolve().parents[1]
ARTIFACTS = ROOT / "test-artifacts"


def settings() -> dict:
    return {
        "asr": {
            "baseUrl": MOCK_BASE_URL,
            "apiKey": "",
            "model": "whisper-1",
            "responseFormat": "verbose_json",
            "language": "zh",
            "prompt": "mock vocabulary",
            "temperature": 0,
            "timeoutSec": 30,
            "extraHeadersJson": '{"x-df-voice-test":"asr"}',
            "extraFormFieldsJson": '{"provider_hint":"asr-extra"}',
        },
        "conversation": {
            "baseUrl": MOCK_BASE_URL,
            "apiKey": "",
            "mode": "chat_completions",
            "model": "mock-model",
            "systemPrompt": "Reply tersely.",
            "temperature": 0,
            "topP": 1,
            "frequencyPenalty": 0,
            "presencePenalty": 0,
            "maxOutputTokens": 64,
            "stream": True,
            "timeoutSec": 30,
            "extraHeadersJson": "",
            "extraBodyJson": "",
        },
        "tts": {
            "baseUrl": MOCK_BASE_URL,
            "apiKey": "",
            "model": "tts-1",
            "voice": "alloy",
            "responseFormat": "wav",
            "speed": 1,
            "instructions": "",
            "timeoutSec": 30,
            "extraHeadersJson": '{"x-df-voice-test":"tts"}',
            "extraBodyJson": '{"provider_hint":"tts-extra"}',
        },
        "autoSpeak": False,
        "keepConversationHistory": False,
    }


def write_wav(path: str) -> None:
    with wave.open(path, "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(16000)
        frames = [struct.pack("<h", 0) for _ in range(1600)]
        handle.writeframes(b"".join(frames))


def main() -> int:
    ARTIFACTS.mkdir(exist_ok=True)
    with tempfile.NamedTemporaryFile(suffix=".wav") as audio:
        write_wav(audio.name)
        with sync_playwright() as p:
            browser = p.chromium.launch(headless=True)
            page = browser.new_page(viewport={"width": 1180, "height": 900})
            goto_with_retry(page, CLIENT_URL)
            page.evaluate(
                """([key, value]) => localStorage.setItem(key, JSON.stringify(value))""",
                [SETTINGS_KEY, settings()],
            )
            page.reload(wait_until="domcontentloaded")
            page.wait_for_selector("text=DF Voice App")
            with page.expect_file_chooser() as chooser:
                page.get_by_role("button", name="Upload").click()
            chooser.value.set_files(audio.name)
            expect(page.get_by_text("Mock ASR transcript.").first).to_be_visible(timeout=10000)
            expect(page.get_by_text("Transcribed")).to_be_visible(timeout=10000)
            page.wait_for_function(
                """(key) => {
                    const stored = JSON.parse(localStorage.getItem(key) || "{}");
                    return stored.transcript === "Mock ASR transcript.";
                }""",
                arg=WORKSPACE_KEY,
                timeout=10000,
            )
            page.reload(wait_until="domcontentloaded")
            expect(page.get_by_text("Mock ASR transcript.").first).to_be_visible(timeout=10000)
            with page.expect_response(
                lambda response: "/v1/audio/speech" in response.url and response.status == 200
            ):
                page.get_by_label("Speak").click()
            expect(page.get_by_text("TTS audio is playing.")).to_be_visible(timeout=10000)
            with page.expect_download() as download_info:
                page.get_by_label("Export transcript").click()
            download = download_info.value
            assert download.suggested_filename.startswith("df-voice-transcript-")
            export_path = ARTIFACTS / download.suggested_filename
            download.save_as(export_path)
            export_text = export_path.read_text(encoding="utf-8")
            assert "Mock ASR transcript." in export_text
            assert "Raw ASR Response" in export_text
            page.get_by_role("button", name="範本").click()
            page.get_by_role("button", name="Run with transcript").first.click()
            expect(page.get_by_text("Mock chat stream.")).to_be_visible(timeout=10000)
            browser.close()
    print("mock ASR upload and TTS integration passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
