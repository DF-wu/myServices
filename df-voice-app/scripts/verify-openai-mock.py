#!/usr/bin/env python3
"""Exercise chat and responses streaming against the mock provider."""

from __future__ import annotations

import os
import json
import pathlib

from playwright.sync_api import expect, sync_playwright

from browser_utils import goto_with_retry


CLIENT_URL = os.environ.get("CLIENT_URL", "http://localhost:8081")
MOCK_BASE_URL = os.environ.get("MOCK_BASE_URL", "http://127.0.0.1:8099/v1")
SETTINGS_KEY = "df-voice-app.settings.v1"
WORKSPACE_KEY = "df-voice-app.workspace.v1"
ROOT = pathlib.Path(__file__).resolve().parents[1]
ARTIFACTS = ROOT / "test-artifacts"


def settings(mode: str, *, stream: bool = True, variant: str | None = None) -> dict:
    metadata = {"test": "conversation-extra"}
    if variant:
        metadata["variant"] = variant
    return {
        "asr": {
            "baseUrl": MOCK_BASE_URL,
            "apiKey": "",
            "model": "whisper-1",
            "responseFormat": "verbose_json",
            "language": "zh",
            "prompt": "",
            "temperature": 0,
            "timeoutSec": 30,
            "maxUploadMb": 100,
            "extraHeadersJson": "",
            "extraFormFieldsJson": "",
        },
        "conversation": {
            "baseUrl": MOCK_BASE_URL,
            "apiKey": "",
            "mode": mode,
            "model": "mock-model",
            "systemPrompt": "Reply tersely.",
            "temperature": 0,
            "topP": 1,
            "frequencyPenalty": 0,
            "presencePenalty": 0,
            "maxOutputTokens": 64,
            "stream": stream,
            "timeoutSec": 30,
            "extraHeadersJson": '{"x-df-voice-test":"conversation"}',
            "extraBodyJson": json.dumps({"metadata": metadata}, separators=(",", ":")),
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
            "extraHeadersJson": "",
            "extraBodyJson": "",
        },
        "autoSpeak": False,
        "keepConversationHistory": False,
    }


def delayed_settings(mode: str, *, delay_ms: int = 900, stream: bool = False, timeout_sec: int = 30) -> dict:
    value = settings(mode, stream=stream)
    value["conversation"]["extraHeadersJson"] = json.dumps(
        {
            "x-df-voice-test": "conversation",
            "x-df-voice-delay-ms": str(delay_ms),
        },
        separators=(",", ":"),
    )
    value["conversation"]["timeoutSec"] = timeout_sec
    return value


def run_case(
    page,
    mode: str,
    expected: str,
    *,
    stream: bool = True,
    variant: str | None = None,
    verify_export: bool = False,
) -> None:
    page.evaluate(
        """([key, value]) => localStorage.setItem(key, JSON.stringify(value))""",
        [SETTINGS_KEY, settings(mode, stream=stream, variant=variant)],
    )
    page.reload(wait_until="domcontentloaded")
    page.wait_for_selector("text=DF Voice App")
    page.get_by_role("button", name="對話").click()
    page.get_by_placeholder("Type a message, or send the latest transcript.").fill("hello")
    page.get_by_role("button", name="Send").click()
    expect(page.get_by_text(expected)).to_be_visible(timeout=10000)
    page.get_by_label("Copy assistant message").click()
    expect(page.get_by_text("Message copied.")).to_be_visible(timeout=10000)
    page.wait_for_function(
        """([key, expected]) => {
            const stored = JSON.parse(localStorage.getItem(key) || "{}");
            return Array.isArray(stored.messages)
                && stored.messages.some((message) => message.content === expected);
        }""",
        arg=[WORKSPACE_KEY, expected],
        timeout=10000,
    )
    body_text = page.locator("body").inner_text()
    assert body_text.count(expected) == 1, body_text
    if verify_export:
        with page.expect_download() as download_info:
            page.get_by_role("button", name="Export").click()
        download = download_info.value
        assert download.suggested_filename.startswith("df-voice-conversation-")
        export_path = ARTIFACTS / download.suggested_filename
        download.save_as(export_path)
        export_text = export_path.read_text(encoding="utf-8")
        assert "DF Voice Conversation" in export_text
        assert expected in export_text


def run_cancel_case(page) -> None:
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
        [SETTINGS_KEY, WORKSPACE_KEY, delayed_settings("chat_completions")],
    )
    page.reload(wait_until="domcontentloaded")
    page.wait_for_selector("text=DF Voice App")
    page.get_by_role("button", name="對話").click()
    page.get_by_placeholder("Type a message, or send the latest transcript.").fill("cancel me")
    page.get_by_role("button", name="Send").click()
    expect(page.get_by_role("button", name="Send")).to_be_disabled(timeout=10000)
    page.get_by_role("button", name="Cancel request").click()
    expect(page.get_by_text("Request cancelled.").first).to_be_visible(timeout=10000)
    page.wait_for_timeout(1200)
    expect(page.get_by_text("Mock chat response.")).not_to_be_visible()
    stored = page.evaluate(
        """(key) => JSON.parse(localStorage.getItem(key) || "{}")""",
        WORKSPACE_KEY,
    )
    contents = [message.get("content") for message in stored.get("messages", [])]
    assert "cancel me" in contents, stored
    assert "Request cancelled." in contents, stored
    assert "Mock chat response." not in contents, stored


def run_timeout_case(page) -> None:
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
        [SETTINGS_KEY, WORKSPACE_KEY, delayed_settings("chat_completions", delay_ms=1500, timeout_sec=1)],
    )
    page.reload(wait_until="domcontentloaded")
    page.wait_for_selector("text=DF Voice App")
    page.get_by_role("button", name="對話").click()
    page.get_by_placeholder("Type a message, or send the latest transcript.").fill("time out")
    page.get_by_role("button", name="Send").click()
    expect(page.get_by_text("Request timed out after 1 seconds.").first).to_be_visible(
        timeout=10000
    )
    stored = page.evaluate(
        """(key) => JSON.parse(localStorage.getItem(key) || "{}")""",
        WORKSPACE_KEY,
    )
    contents = [message.get("content") for message in stored.get("messages", [])]
    assert "time out" in contents, stored
    assert "Request failed: Request timed out after 1 seconds." in contents, stored
    assert "Mock chat response." not in contents, stored


def run_diagnostics(page) -> None:
    page.evaluate(
        """([key, value]) => localStorage.setItem(key, JSON.stringify(value))""",
        [SETTINGS_KEY, settings("responses")],
    )
    page.reload(wait_until="domcontentloaded")
    page.wait_for_selector("text=DF Voice App")
    page.get_by_role("button", name="設定").click()
    page.get_by_role("button", name="Check all").click()
    expect(page.get_by_text("All provider model endpoints are reachable.")).to_be_visible(
        timeout=10000
    )
    expect(page.get_by_text("2 models available").first).to_be_visible(timeout=10000)
    expect(page.get_by_text("mock-chat").first).to_be_visible(timeout=10000)
    page.get_by_label("Use mock-chat for Chat").click()
    expect(page.get_by_text("Conversation model set to mock-chat.")).to_be_visible(
        timeout=10000
    )
    model = page.evaluate(
        """(key) => JSON.parse(localStorage.getItem(key)).conversation.model""",
        SETTINGS_KEY,
    )
    assert model == "mock-chat", model
    page.screenshot(path=str(ARTIFACTS / "web-diagnostics-models.png"), full_page=True)


def run_diagnostics_missing_base_url(page) -> None:
    value = settings("responses")
    value["asr"]["baseUrl"] = ""
    page.evaluate(
        """([key, value]) => localStorage.setItem(key, JSON.stringify(value))""",
        [SETTINGS_KEY, value],
    )
    page.reload(wait_until="domcontentloaded")
    page.wait_for_selector("text=DF Voice App")
    page.get_by_role("button", name="設定").click()
    page.get_by_label("Check ASR").click()
    expect(page.get_by_text("ASR base URL is required.", exact=True)).to_be_visible(timeout=10000)


def run_missing_conversation_settings_case(page) -> None:
    value = settings("responses", stream=False)
    value["conversation"]["baseUrl"] = ""
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
        [SETTINGS_KEY, WORKSPACE_KEY, value],
    )
    page.reload(wait_until="domcontentloaded")
    page.wait_for_selector("text=DF Voice App")
    page.get_by_role("button", name="對話").click()
    page.get_by_placeholder("Type a message, or send the latest transcript.").fill("missing base")
    page.get_by_role("button", name="Send").click()
    expect(page.get_by_text("Request failed: Conversation base URL is required.")).to_be_visible(
        timeout=10000
    )
    expect(page.get_by_text("Mock responses output.")).not_to_be_visible()
    page.wait_for_function(
        """(key) => {
            const stored = JSON.parse(localStorage.getItem(key) || "{}");
            const messages = Array.isArray(stored.messages) ? stored.messages : [];
            const contents = messages.map((message) => message.content);
            return contents.includes("missing base")
                && contents.includes("Request failed: Conversation base URL is required.");
        }""",
        arg=WORKSPACE_KEY,
        timeout=10000,
    )
    stored = page.evaluate(
        """(key) => JSON.parse(localStorage.getItem(key) || "{}")""",
        WORKSPACE_KEY,
    )
    contents = [message.get("content") for message in stored.get("messages", [])]
    assert "missing base" in contents, stored
    assert "Request failed: Conversation base URL is required." in contents, stored
    assert "Mock responses output." not in contents, stored


def run_settings_portability(page) -> None:
    seeded = settings("responses")
    seeded["asr"]["apiKey"] = "asr-secret"
    seeded["conversation"]["apiKey"] = "conversation-secret"
    seeded["tts"]["apiKey"] = "tts-secret"
    page.evaluate(
        """([key, value]) => localStorage.setItem(key, JSON.stringify(value))""",
        [SETTINGS_KEY, seeded],
    )
    page.reload(wait_until="domcontentloaded")
    page.wait_for_selector("text=DF Voice App")
    page.get_by_role("button", name="設定").click()

    with page.expect_download() as download_info:
        page.get_by_role("button", name="Export settings").click()
    download = download_info.value
    assert download.suggested_filename.startswith("df-voice-settings-")
    export_path = ARTIFACTS / download.suggested_filename
    download.save_as(export_path)
    export_text = export_path.read_text(encoding="utf-8")
    assert "asr-secret" not in export_text
    assert "conversation-secret" not in export_text
    assert "tts-secret" not in export_text
    assert "__DF_VOICE_REDACTED__" in export_text

    import_path = ARTIFACTS / "settings-import.json"
    import_path.write_text(
        json.dumps(
            {
                "app": "df-voice-app",
                "version": 1,
                "redacted": True,
                "exportedAt": "2026-06-08T00:00:00.000Z",
                "settings": {
                    **seeded,
                    "conversation": {
                        **seeded["conversation"],
                        "apiKey": "__DF_VOICE_REDACTED__",
                        "model": "imported-model",
                    },
                },
            }
        ),
        encoding="utf-8",
    )
    with page.expect_file_chooser() as chooser:
        page.get_by_role("button", name="Import settings").click()
    chooser.value.set_files(str(import_path))
    expect(page.get_by_text("Settings imported.")).to_be_visible(timeout=10000)
    imported = page.evaluate(
        """(key) => JSON.parse(localStorage.getItem(key))""",
        SETTINGS_KEY,
    )
    assert imported["conversation"]["model"] == "imported-model", imported
    assert imported["conversation"]["apiKey"] == "conversation-secret", imported

    invalid_path = ARTIFACTS / "settings-invalid-import.json"
    invalid_path.write_text(
        json.dumps(
            {
                "app": "df-voice-app",
                "version": 1,
                "redacted": True,
                "exportedAt": "2026-06-08T00:00:00.000Z",
                "settings": {
                    "autoSpeak": "yes",
                    "asr": {
                        "maxUploadMb": 0,
                        "responseFormat": "docx",
                        "temperature": "hot",
                        "timeoutSec": -10,
                        "unknown": "ignored",
                    },
                    "conversation": {
                        "mode": "legacy_completions",
                        "maxOutputTokens": 0,
                        "stream": "true",
                    },
                    "tts": {
                        "responseFormat": "ogg",
                        "speed": -2,
                    },
                },
            }
        ),
        encoding="utf-8",
    )
    with page.expect_file_chooser() as chooser:
        page.get_by_role("button", name="Import settings").click()
    chooser.value.set_files(str(invalid_path))
    expect(page.get_by_text("Settings imported.")).to_be_visible(timeout=10000)
    sanitized = page.evaluate(
        """(key) => JSON.parse(localStorage.getItem(key))""",
        SETTINGS_KEY,
    )
    assert sanitized["autoSpeak"] is False, sanitized
    assert sanitized["asr"]["responseFormat"] == "verbose_json", sanitized
    assert sanitized["asr"]["temperature"] == 0, sanitized
    assert sanitized["asr"]["timeoutSec"] == 30, sanitized
    assert sanitized["asr"]["maxUploadMb"] == 100, sanitized
    assert sanitized["conversation"]["mode"] == "responses", sanitized
    assert sanitized["conversation"]["maxOutputTokens"] == 64, sanitized
    assert sanitized["conversation"]["stream"] is True, sanitized
    assert sanitized["tts"]["responseFormat"] == "wav", sanitized
    assert sanitized["tts"]["speed"] == 1, sanitized
    assert "unknown" not in sanitized["asr"], sanitized


def main() -> int:
    ARTIFACTS.mkdir(exist_ok=True)
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page(viewport={"width": 1180, "height": 900})
        goto_with_retry(page, CLIENT_URL)
        run_diagnostics(page)
        run_diagnostics_missing_base_url(page)
        run_settings_portability(page)
        run_cancel_case(page)
        run_timeout_case(page)
        run_missing_conversation_settings_case(page)
        run_case(page, "chat_completions", "Mock chat stream.", verify_export=True)
        run_case(page, "responses", "Mock responses stream.")
        run_case(page, "responses", "Mock response text done.", variant="responses-text-done")
        run_case(page, "responses", "Mock completed response.", variant="responses-completed-only")
        run_case(page, "chat_completions", "Mock chat response.", stream=False)
        run_case(page, "responses", "Mock responses output.", stream=False)
        browser.close()
    print("mock conversation integration passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
