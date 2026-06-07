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
        assert_layout(page, "desktop settings")
        page.screenshot(path=str(ARTIFACTS / "web-settings.png"), full_page=True)
        page.set_viewport_size({"width": 390, "height": 844})
        expect(page.get_by_text("Provider checks")).to_be_visible()
        assert_layout(page, "mobile settings")
        page.screenshot(path=str(ARTIFACTS / "web-settings-mobile.png"), full_page=True)
        page.set_viewport_size({"width": 1366, "height": 900})

        page.get_by_role("button", name="範本").click()
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
