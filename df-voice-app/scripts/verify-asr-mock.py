#!/usr/bin/env python3
"""Exercise ASR file upload against the mock provider."""

from __future__ import annotations

import os
import json
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


def settings(response_format: str = "verbose_json", *, delay_ms: int = 0, timeout_sec: int = 30) -> dict:
    asr_headers = {"x-df-voice-test": "asr"}
    if delay_ms:
        asr_headers["x-df-voice-delay-ms"] = str(delay_ms)
    return {
        "asr": {
            "baseUrl": MOCK_BASE_URL,
            "apiKey": "",
            "model": "whisper-1",
            "responseFormat": response_format,
            "language": "zh",
            "prompt": "mock vocabulary",
            "temperature": 0,
            "timeoutSec": timeout_sec,
            "extraHeadersJson": json_dumps(asr_headers),
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


def json_dumps(value: dict[str, str]) -> str:
    return json.dumps(value, separators=(",", ":"))


def write_wav(path: str) -> None:
    with wave.open(path, "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(16000)
        frames = [struct.pack("<h", 0) for _ in range(1600)]
        handle.writeframes(b"".join(frames))


def seed_settings(page, response_format: str = "verbose_json") -> None:
    page.evaluate(
        """([key, value]) => localStorage.setItem(key, JSON.stringify(value))""",
        [SETTINGS_KEY, settings(response_format)],
    )
    page.reload(wait_until="domcontentloaded")
    page.wait_for_selector("text=DF Voice App")


def upload_audio(page, path: str, expected_text: str) -> None:
    with page.expect_file_chooser() as chooser:
        page.get_by_role("button", name="Upload").click()
    chooser.value.set_files(path)
    expect(page.get_by_text(expected_text).first).to_be_visible(timeout=10000)
    expect(page.get_by_text("Transcribed")).to_be_visible(timeout=10000)
    page.wait_for_function(
        """([key, expected]) => {
            const stored = JSON.parse(localStorage.getItem(key) || "{}");
            return typeof stored.transcript === "string" && stored.transcript.includes(expected);
        }""",
        arg=[WORKSPACE_KEY, expected_text],
        timeout=10000,
    )


def verify_response_format(page, path: str, response_format: str, expected_text: str) -> None:
    seed_settings(page, response_format)
    upload_audio(page, path, expected_text)


def verify_cancel_transcription(page, path: str) -> None:
    page.evaluate(
        """([settingsKey, workspaceKey, value]) => {
            localStorage.setItem(settingsKey, JSON.stringify(value));
            localStorage.setItem(workspaceKey, JSON.stringify({
                transcript: "",
                rawResult: "",
                chatDraft: "",
                messages: [],
                customPromptTemplates: [],
                customProviderTemplates: []
            }));
        }""",
        [SETTINGS_KEY, WORKSPACE_KEY, settings(delay_ms=900)],
    )
    page.reload(wait_until="domcontentloaded")
    page.wait_for_selector("text=DF Voice App")
    with page.expect_file_chooser() as chooser:
        page.get_by_role("button", name="Upload").click()
    chooser.value.set_files(path)
    page.get_by_role("button", name="Cancel request").click()
    expect(page.get_by_text("Request cancelled.")).to_be_visible(timeout=10000)
    page.wait_for_timeout(1200)
    expect(page.get_by_text("Mock ASR transcript.")).not_to_be_visible()
    stored = page.evaluate(
        """(key) => JSON.parse(localStorage.getItem(key) || "{}")""",
        WORKSPACE_KEY,
    )
    assert stored.get("transcript") == "", stored
    assert stored.get("rawResult") == "", stored


def verify_timeout_transcription(page, path: str) -> None:
    page.evaluate(
        """([settingsKey, workspaceKey, value]) => {
            localStorage.setItem(settingsKey, JSON.stringify(value));
            localStorage.setItem(workspaceKey, JSON.stringify({
                transcript: "",
                rawResult: "",
                chatDraft: "",
                messages: [],
                customPromptTemplates: [],
                customProviderTemplates: []
            }));
        }""",
        [SETTINGS_KEY, WORKSPACE_KEY, settings(delay_ms=1500, timeout_sec=1)],
    )
    page.reload(wait_until="domcontentloaded")
    page.wait_for_selector("text=DF Voice App")
    with page.expect_file_chooser() as chooser:
        page.get_by_role("button", name="Upload").click()
    chooser.value.set_files(path)
    expect(page.get_by_text("Request timed out after 1 seconds.")).to_be_visible(timeout=10000)
    stored = page.evaluate(
        """(key) => JSON.parse(localStorage.getItem(key) || "{}")""",
        WORKSPACE_KEY,
    )
    assert stored.get("transcript") == "", stored


def main() -> int:
    ARTIFACTS.mkdir(exist_ok=True)
    with tempfile.NamedTemporaryFile(suffix=".wav") as audio:
        write_wav(audio.name)
        with sync_playwright() as p:
            browser = p.chromium.launch(headless=True)
            page = browser.new_page(viewport={"width": 1180, "height": 900})
            goto_with_retry(page, CLIENT_URL)
            seed_settings(page)
            upload_audio(page, audio.name, "Mock ASR transcript.")
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
            verify_response_format(page, audio.name, "text", "Mock ASR transcript.")
            verify_response_format(page, audio.name, "srt", "00:00:00,000 --> 00:00:01,000")
            verify_response_format(page, audio.name, "vtt", "WEBVTT")
            verify_cancel_transcription(page, audio.name)
            verify_timeout_transcription(page, audio.name)
            browser.close()
    print("mock ASR upload, response formats, and TTS integration passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
