"""Shared Playwright helpers for local Expo verification scripts."""

from __future__ import annotations

from playwright.sync_api import Error as PlaywrightError


def goto_with_retry(
    page,
    url: str,
    *,
    wait_until: str = "domcontentloaded",
    attempts: int = 10,
    delay_ms: int = 500,
) -> None:
    last_error: PlaywrightError | None = None
    for attempt in range(attempts):
        try:
            page.goto(url, wait_until=wait_until)
            return
        except PlaywrightError as error:
            last_error = error
            if attempt == attempts - 1:
                break
            page.wait_for_timeout(delay_ms)

    if last_error is not None:
        raise last_error
