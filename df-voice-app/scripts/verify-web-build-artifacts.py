#!/usr/bin/env python3
"""Verify install metadata emitted by the static web export."""

from __future__ import annotations

import json
import pathlib


ROOT = pathlib.Path(__file__).resolve().parents[1]
DIST = ROOT / "dist"
INDEX_HTML = DIST / "index.html"
MANIFEST = DIST / "manifest.webmanifest"
EXPECTED_ICONS = {
    "/icon-192.png": (192, 192),
    "/icon-512.png": (512, 512),
}


def fail(message: str) -> int:
    print(message)
    return 1


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def png_size(path: pathlib.Path) -> tuple[int, int]:
    with path.open("rb") as handle:
        signature = handle.read(8)
        require(signature == b"\x89PNG\r\n\x1a\n", f"{path.name} must be a PNG")
        _length = int.from_bytes(handle.read(4), "big")
        chunk = handle.read(4)
        require(chunk == b"IHDR", f"{path.name} missing IHDR")
        return tuple(int.from_bytes(handle.read(4), "big") for _ in range(2))


def main() -> int:
    try:
        require(INDEX_HTML.exists(), "dist/index.html missing; run npm run build:web first")
        require(MANIFEST.exists(), "dist/manifest.webmanifest missing; run npm run build:web first")

        html = INDEX_HTML.read_text(encoding="utf-8")
        manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))

        require('<html  lang="zh-Hant">' in html or '<html lang="zh-Hant">' in html, "exported HTML must set zh-Hant")
        require('<link rel="manifest" href="/manifest.webmanifest"' in html, "exported HTML must link the manifest")
        require('<meta name="theme-color" content="#18765A"' in html, "exported HTML must set theme-color")
        require("apple-mobile-web-app-capable" in html, "exported HTML must include iOS home-screen metadata")
        require("CapsWriter and OpenAI-compatible voice workbench" in html, "exported HTML description missing")

        require(manifest["name"] == "DF Voice App", "manifest name mismatch")
        require(manifest["short_name"] == "DF Voice", "manifest short_name mismatch")
        require(manifest["lang"] == "zh-Hant", "manifest lang mismatch")
        require(manifest["display"] == "standalone", "manifest display mismatch")
        require(manifest["start_url"] == "/", "manifest start_url mismatch")
        require(manifest["scope"] == "/", "manifest scope mismatch")
        require(manifest["theme_color"] == "#18765A", "manifest theme_color mismatch")
        require(manifest["background_color"] == "#F4F7F8", "manifest background_color mismatch")
        require(manifest["orientation"] == "portrait", "manifest orientation mismatch")
        require("CapsWriter" in manifest["description"], "manifest description must mention CapsWriter")
        manifest_icons = {icon["src"]: icon for icon in manifest["icons"]}
        require("/favicon.ico" in manifest_icons, "manifest must include favicon")
        for src, expected_size in EXPECTED_ICONS.items():
            icon = manifest_icons.get(src)
            require(icon is not None, f"manifest must include {src}")
            require(icon["sizes"] == f"{expected_size[0]}x{expected_size[1]}", f"{src} size metadata mismatch")
            require(icon["type"] == "image/png", f"{src} type mismatch")
            icon_path = DIST / src.removeprefix("/")
            require(icon_path.exists(), f"exported {src} missing")
            require(png_size(icon_path) == expected_size, f"exported {src} dimensions mismatch")
    except (AssertionError, KeyError, OSError, json.JSONDecodeError) as error:
        return fail(str(error))

    print("web build artifact verification passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
