#!/usr/bin/env python3
"""Smoke-test the Expo web client with Playwright."""

from __future__ import annotations

import os
import pathlib

from playwright.sync_api import expect, sync_playwright

from browser_utils import goto_with_retry


ROOT = pathlib.Path(__file__).resolve().parents[1]
ARTIFACTS = ROOT / "test-artifacts"
URL = os.environ.get("CLIENT_URL", "http://localhost:8081")


def assert_layout(page, label: str) -> None:
    metrics = page.evaluate(
        """() => {
            const root = document.documentElement;
            const body = document.body;
            const buttons = Array.from(document.querySelectorAll('[role="button"]'))
                .map((element) => {
                    const rect = element.getBoundingClientRect();
                    const style = window.getComputedStyle(element);
                    return {
                        label: element.getAttribute('aria-label') || element.textContent || element.tagName,
                        width: rect.width,
                        height: rect.height,
                        visible: rect.width > 0 && rect.height > 0 && style.visibility !== 'hidden' && style.display !== 'none',
                    };
                })
                .filter((button) => button.visible);
            return {
                clientWidth: root.clientWidth,
                scrollWidth: Math.max(root.scrollWidth, body.scrollWidth),
                smallButtons: buttons.filter((button) => button.width < 40 || button.height < 40),
            };
        }""",
    )
    assert metrics["scrollWidth"] <= metrics["clientWidth"] + 1, (
        f"{label}: horizontal overflow "
        f"{metrics['scrollWidth']} > {metrics['clientWidth']}"
    )
    assert not metrics["smallButtons"], f"{label}: small tap targets {metrics['smallButtons']}"


def main() -> int:
    ARTIFACTS.mkdir(exist_ok=True)
    console_errors: list[str] = []

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page(viewport={"width": 1366, "height": 900})
        page.on(
            "console",
            lambda msg: console_errors.append(msg.text) if msg.type == "error" else None,
        )
        goto_with_retry(page, URL)
        page.wait_for_selector("text=DF Voice App")

        expect(page.get_by_role("heading", name="DF Voice App")).to_be_visible()
        expect(page.get_by_text("Voice pipeline")).to_be_visible()
        expect(page.get_by_text("Record or upload audio")).to_be_visible()
        assert_layout(page, "desktop capture")
        page.screenshot(path=str(ARTIFACTS / "web-home.png"), full_page=True)

        page.get_by_role("button", name="設定").click()
        expect(page.get_by_text("Provider checks")).to_be_visible()
        expect(page.get_by_text("Transcription provider")).to_be_visible()
        expect(page.get_by_text("Chat provider")).to_be_visible()
        expect(page.get_by_text("Speech provider")).to_be_visible()
        asr_headers_json = page.get_by_label("Extra headers JSON").nth(0)
        asr_headers_json.fill("{")
        expect(page.get_by_text("Invalid JSON syntax.")).to_be_visible()
        asr_headers_json.fill('{"x-test":{"nested":true}}')
        expect(page.get_by_text("Header values must be strings, numbers, booleans, or null.")).to_be_visible()
        asr_headers_json.fill('{"x-test":"1"}')
        expect(page.get_by_text("Valid headers JSON.")).to_be_visible()
        page.get_by_label("Extra form fields JSON").fill("[]")
        expect(page.get_by_text("Must be a JSON object.")).to_be_visible()
        page.get_by_label("Extra form fields JSON").fill('{"timestamp_granularities":["word"]}')
        expect(page.get_by_text("Valid JSON object.")).to_be_visible()
        original_asr_temperature = page.evaluate(
            """(key) => JSON.parse(localStorage.getItem(key)).asr.temperature""",
            "df-voice-app.settings.v1",
        )
        asr_temperature = page.get_by_label("Temperature").nth(0)
        asr_temperature.fill("2")
        expect(page.get_by_text("Enter a number from 0 to 1.")).to_be_visible()
        page.wait_for_function(
            """([key, original]) => JSON.parse(localStorage.getItem(key)).asr.temperature === original""",
            arg=["df-voice-app.settings.v1", original_asr_temperature],
            timeout=10000,
        )
        asr_temperature.fill("0.5")
        page.wait_for_function(
            """(key) => JSON.parse(localStorage.getItem(key)).asr.temperature === 0.5""",
            arg="df-voice-app.settings.v1",
            timeout=10000,
        )
        max_output_tokens = page.get_by_label("Max output tokens")
        max_output_tokens.fill("1.5")
        expect(page.get_by_text("Enter a whole number of at least 1.")).to_be_visible()
        max_output_tokens.fill("256")
        page.wait_for_function(
            """(key) => JSON.parse(localStorage.getItem(key)).conversation.maxOutputTokens === 256""",
            arg="df-voice-app.settings.v1",
            timeout=10000,
        )
        tts_speed = page.get_by_label("Speed")
        tts_speed.fill("5")
        expect(page.get_by_text("Enter a number from 0.25 to 4.")).to_be_visible()
        tts_speed.fill("1.25")
        page.wait_for_function(
            """(key) => JSON.parse(localStorage.getItem(key)).tts.speed === 1.25""",
            arg="df-voice-app.settings.v1",
            timeout=10000,
        )
        assert_layout(page, "desktop settings")
        page.screenshot(path=str(ARTIFACTS / "web-settings.png"), full_page=True)
        page.set_viewport_size({"width": 390, "height": 844})
        expect(page.get_by_text("Provider checks")).to_be_visible()
        assert_layout(page, "mobile settings")
        page.screenshot(path=str(ARTIFACTS / "web-settings-mobile.png"), full_page=True)
        page.set_viewport_size({"width": 1366, "height": 900})

        page.evaluate(
            """() => localStorage.setItem("df-voice-app.workspace.v1", JSON.stringify({
                transcript: "Sensitive test transcript.",
                rawResult: "{\\"text\\":\\"Sensitive test transcript.\\"}",
                chatDraft: "Sensitive draft",
                messages: [
                    { id: "seed-user", role: "user", content: "Sensitive seeded question.", createdAt: 1 },
                    { id: "seed-assistant", role: "assistant", content: "Sensitive seeded answer.", createdAt: 2 }
                ],
                customPromptTemplates: [
                    {
                        id: "custom-seeded",
                        name: "Sensitive custom prompt",
                        category: "Custom",
                        description: "Temporary sensitive prompt.",
                        tags: ["sensitive"],
                        prompt: "Sensitive prompt body."
                    }
                ],
                customProviderTemplates: [
                    {
                        id: "custom-provider-seeded",
                        name: "Sensitive provider setup",
                        description: "Temporary sensitive provider setup.",
                        tags: ["sensitive"],
                        settings: JSON.parse(localStorage.getItem("df-voice-app.settings.v1"))
                    }
                ]
            }))""",
        )
        page.reload(wait_until="domcontentloaded")
        page.wait_for_selector("text=DF Voice App")
        expect(page.get_by_text("Sensitive test transcript.", exact=True)).to_be_visible()
        page.get_by_role("button", name="設定").click()
        page.get_by_role("button", name="Clear workspace").click()
        expect(page.get_by_text("Workspace cleared.")).to_be_visible()
        page.wait_for_function(
            """() => {
                const stored = JSON.parse(localStorage.getItem("df-voice-app.workspace.v1") || "{}");
                return stored.transcript === ""
                    && stored.rawResult === ""
                    && stored.chatDraft === ""
                    && Array.isArray(stored.messages)
                    && stored.messages.length === 0
                    && Array.isArray(stored.customPromptTemplates)
                    && stored.customPromptTemplates.length === 0
                    && Array.isArray(stored.customProviderTemplates)
                    && stored.customProviderTemplates.length === 0;
            }""",
            timeout=10000,
        )
        page.get_by_role("button", name="語音").click()
        expect(page.get_by_text("Sensitive test transcript.", exact=True)).not_to_be_visible()
        page.get_by_role("button", name="對話").click()
        expect(page.get_by_text("Sensitive seeded answer.", exact=True)).not_to_be_visible()

        page.get_by_role("button", name="範本").click()
        expect(page.get_by_text("Prompt templates")).to_be_visible()
        expect(page.get_by_text("Create prompt template")).to_be_visible()
        page.get_by_role("textbox", name="Name", exact=True).fill("Custom voice brief")
        page.get_by_role("textbox", name="Category", exact=True).fill("Custom")
        page.get_by_role("textbox", name="Tags", exact=True).fill("brief, personal")
        page.get_by_role("textbox", name="Description", exact=True).fill("Reusable custom prompt for smoke testing.")
        page.get_by_role("textbox", name="Prompt", exact=True).fill("Turn this transcript into a direct project brief.")
        page.get_by_role("button", name="Save custom prompt").click()
        expect(page.get_by_text("Saved custom prompt template: Custom voice brief")).to_be_visible()
        expect(page.get_by_text("Custom voice brief", exact=True)).to_be_visible()
        page.wait_for_function(
            """() => {
                const stored = JSON.parse(localStorage.getItem("df-voice-app.workspace.v1") || "{}");
                return Array.isArray(stored.customPromptTemplates)
                    && stored.customPromptTemplates.some((template) => template.name === "Custom voice brief");
            }""",
            timeout=10000,
        )
        page.reload(wait_until="domcontentloaded")
        page.wait_for_selector("text=DF Voice App")
        page.get_by_role("button", name="範本").click()
        expect(page.get_by_text("Custom voice brief", exact=True)).to_be_visible()
        page.get_by_label("Delete Custom voice brief").click()
        expect(page.get_by_text("Custom prompt template deleted.")).to_be_visible()
        expect(page.get_by_text("Custom voice brief", exact=True)).not_to_be_visible()
        saved_asr_base = page.evaluate(
            """() => JSON.parse(localStorage.getItem("df-voice-app.settings.v1")).asr.baseUrl"""
        )
        page.get_by_role("button", name="設定").click()
        page.get_by_label("API key").nth(0).fill("asr-provider-template-secret")
        page.get_by_label("Extra headers JSON").nth(0).fill('{"x-secret-route":"asr-provider-template-secret"}')
        page.wait_for_function(
            """() => {
                const stored = JSON.parse(localStorage.getItem("df-voice-app.settings.v1"));
                return stored.asr.apiKey === "asr-provider-template-secret"
                    && stored.asr.extraHeadersJson.includes("asr-provider-template-secret");
            }""",
            timeout=10000,
        )
        page.get_by_role("button", name="範本").click()
        page.get_by_label("Provider template name").fill("Lab provider setup")
        page.get_by_label("Provider template tags").fill("lab, local")
        page.get_by_label("Provider template description").fill("Reusable provider setup for smoke testing.")
        page.get_by_role("button", name="Save provider template").click()
        expect(page.get_by_text("Saved custom provider template: Lab provider setup")).to_be_visible()
        expect(page.get_by_text("Lab provider setup", exact=True)).to_be_visible()
        page.wait_for_function(
            """() => {
                const stored = JSON.parse(localStorage.getItem("df-voice-app.workspace.v1") || "{}");
                return Array.isArray(stored.customProviderTemplates)
                    && stored.customProviderTemplates.some((template) => template.name === "Lab provider setup");
            }""",
            timeout=10000,
        )
        workspace_payload = page.evaluate(
            """() => localStorage.getItem("df-voice-app.workspace.v1") || "" """
        )
        assert "asr-provider-template-secret" not in workspace_payload
        page.wait_for_function(
            """() => {
                const stored = JSON.parse(localStorage.getItem("df-voice-app.workspace.v1") || "{}");
                const template = stored.customProviderTemplates.find((item) => item.name === "Lab provider setup");
                return template
                    && template.settings.asr.apiKey === "__DF_VOICE_REDACTED__"
                    && template.settings.asr.extraHeadersJson === "__DF_VOICE_REDACTED__";
            }""",
            timeout=10000,
        )
        page.reload(wait_until="domcontentloaded")
        page.wait_for_selector("text=DF Voice App")
        workspace_payload = page.evaluate(
            """() => localStorage.getItem("df-voice-app.workspace.v1") || "" """
        )
        assert "asr-provider-template-secret" not in workspace_payload
        page.get_by_role("button", name="範本").click()
        expect(page.get_by_text("Lab provider setup", exact=True)).to_be_visible()
        page.get_by_role("button", name="設定").click()
        page.get_by_label("Base URL").nth(0).fill("http://changed.local/v1")
        page.wait_for_function(
            """() => JSON.parse(localStorage.getItem("df-voice-app.settings.v1")).asr.baseUrl === "http://changed.local/v1" """,
            timeout=10000,
        )
        page.get_by_role("button", name="範本").click()
        page.get_by_role("button", name="Apply").first.click()
        expect(page.get_by_text("Applied template: Lab provider setup")).to_be_visible()
        page.wait_for_function(
            """(expected) => JSON.parse(localStorage.getItem("df-voice-app.settings.v1")).asr.baseUrl === expected""",
            arg=saved_asr_base,
            timeout=10000,
        )
        applied_settings = page.evaluate(
            """() => JSON.parse(localStorage.getItem("df-voice-app.settings.v1"))"""
        )
        assert applied_settings["asr"]["apiKey"] == "asr-provider-template-secret"
        assert "asr-provider-template-secret" in applied_settings["asr"]["extraHeadersJson"]
        page.get_by_label("Delete Lab provider setup").click()
        expect(page.get_by_text("Custom provider template deleted.")).to_be_visible()
        expect(page.get_by_text("Lab provider setup", exact=True)).not_to_be_visible()
        expect(page.get_by_text("逐字稿整理")).to_be_visible()
        expect(page.get_by_text("會議摘要")).to_be_visible()
        expect(page.get_by_text("CapsWriter 本機 ASR")).to_be_visible()
        expect(page.get_by_text("OpenAI / 相容雲端")).to_be_visible()
        expect(page.get_by_text("Android Emulator Host")).to_be_visible()
        assert_layout(page, "desktop templates")

        page.set_viewport_size({"width": 390, "height": 844})
        page.get_by_role("button", name="語音").click()
        expect(page.get_by_role("heading", name="DF Voice App")).to_be_visible()
        expect(page.get_by_text("Voice pipeline")).to_be_visible()
        assert_layout(page, "mobile capture")
        page.screenshot(path=str(ARTIFACTS / "web-mobile.png"), full_page=True)

        browser.close()

    blocking_errors = [
        error
        for error in console_errors
        if "favicon" not in error.lower() and "source map" not in error.lower()
    ]
    if blocking_errors:
        print("\n".join(blocking_errors))
        return 1

    print(f"screenshots: {ARTIFACTS}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
