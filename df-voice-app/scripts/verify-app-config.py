#!/usr/bin/env python3
"""Verify Expo app config and required image assets."""

from __future__ import annotations

import json
import pathlib
import re
import struct
from typing import Any


ROOT = pathlib.Path(__file__).resolve().parents[1]
APP_JSON = ROOT / "app.json"
EAS_JSON = ROOT / "eas.json"
WEB_HTML = ROOT / "app" / "+html.tsx"
WEB_MANIFEST = ROOT / "public" / "manifest.webmanifest"
HEX_COLOR = re.compile(r"^#[0-9A-Fa-f]{6}$")
LOCAL_HTTP_PLUGIN = "./plugins/with-local-http-android"
EXPECTED_ASSETS = {
    "./assets/android-icon-background.png": (512, 512),
    "./assets/android-icon-foreground.png": (512, 512),
    "./assets/android-icon-monochrome.png": (432, 432),
    "./assets/favicon.png": (48, 48),
    "./assets/icon.png": (1024, 1024),
    "./assets/splash-icon.png": (1024, 1024),
}
EXPECTED_WEB_ICONS = {
    "/icon-192.png": (192, 192),
    "/icon-512.png": (512, 512),
}


def fail(message: str) -> int:
    print(message)
    return 1


def read_json(path: pathlib.Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def asset_path(value: str) -> pathlib.Path:
    return ROOT / value.removeprefix("./")


def public_path(value: str) -> pathlib.Path:
    return ROOT / "public" / value.removeprefix("/")


def png_size(path: pathlib.Path) -> tuple[int, int]:
    with path.open("rb") as handle:
        signature = handle.read(8)
        if signature != b"\x89PNG\r\n\x1a\n":
            raise ValueError(f"{path} is not a PNG")
        _length = struct.unpack(">I", handle.read(4))[0]
        chunk = handle.read(4)
        if chunk != b"IHDR":
            raise ValueError(f"{path} is missing an IHDR chunk")
        return struct.unpack(">II", handle.read(8))


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def require_asset(value: str, expected_size: tuple[int, int]) -> None:
    path = asset_path(value)
    require(path.exists(), f"missing asset {value}")
    actual_size = png_size(path)
    require(
        actual_size == expected_size,
        f"{value} must be {expected_size[0]}x{expected_size[1]}; got {actual_size[0]}x{actual_size[1]}",
    )


def require_public_png(value: str, expected_size: tuple[int, int]) -> None:
    path = public_path(value)
    require(path.exists(), f"missing web icon {value}")
    actual_size = png_size(path)
    require(
        actual_size == expected_size,
        f"{value} must be {expected_size[0]}x{expected_size[1]}; got {actual_size[0]}x{actual_size[1]}",
    )


def require_color(value: Any, label: str) -> None:
    require(isinstance(value, str) and HEX_COLOR.match(value) is not None, f"{label} must be a hex color")


def main() -> int:
    try:
        app = read_json(APP_JSON)["expo"]
        eas = read_json(EAS_JSON)
        web_manifest = read_json(WEB_MANIFEST)
        web_html = WEB_HTML.read_text(encoding="utf-8")

        require(app["name"] == "DF Voice App", "app name must be DF Voice App")
        require(app["slug"] == "df-voice-app", "slug must be df-voice-app")
        require(app["scheme"] == "df-voice-app", "scheme must be df-voice-app")
        require(app["orientation"] == "portrait", "native app orientation must be portrait")
        require(app["userInterfaceStyle"] == "automatic", "app must support system color scheme")
        require_asset(app["icon"], EXPECTED_ASSETS[app["icon"]])

        ios = app["ios"]
        require(ios["bundleIdentifier"] == "app.dfvoice.app", "iOS bundle identifier mismatch")
        require(ios["supportsTablet"] is True, "iOS tablet support must stay enabled")
        microphone_usage = ios["infoPlist"]["NSMicrophoneUsageDescription"]
        require("records microphone audio" in microphone_usage, "iOS microphone usage text must be explicit")

        android = app["android"]
        require(android["package"] == "app.dfvoice.app", "Android package mismatch")
        require(android["predictiveBackGestureEnabled"] is False, "Android predictive back must stay explicit")
        adaptive_icon = android["adaptiveIcon"]
        require_color(adaptive_icon["backgroundColor"], "Android adaptive icon background")
        for key in ["foregroundImage", "backgroundImage", "monochromeImage"]:
            require_asset(adaptive_icon[key], EXPECTED_ASSETS[adaptive_icon[key]])

        web = app["web"]
        require(web["bundler"] == "metro", "web bundler must be metro")
        require(web["output"] == "static", "web output must be static")
        require(web["name"] == "DF Voice App", "web name mismatch")
        require(web["shortName"] == "DF Voice", "web short name mismatch")
        require(len(web["shortName"]) <= 12, "web short name must fit launcher limits")
        require(web["lang"] == "zh-Hant", "web language must be zh-Hant")
        require(web["display"] == "standalone", "web display must be standalone")
        require(web["startUrl"] == "/", "web startUrl must launch the app root")
        require(web["scope"] == "/", "web scope must be app root")
        require(web["orientation"] == "portrait", "web orientation must be portrait")
        require(web["barStyle"] == "default", "web barStyle must be default")
        require("CapsWriter" in web["description"], "web description must mention CapsWriter")
        require("OpenAI-compatible" in web["description"], "web description must mention OpenAI compatibility")
        require_color(web["themeColor"], "web themeColor")
        require_color(web["backgroundColor"], "web backgroundColor")
        require_asset(web["favicon"], EXPECTED_ASSETS[web["favicon"]])
        require(web["splash"]["backgroundColor"] == web["backgroundColor"], "web splash background must match")
        require(web["splash"]["resizeMode"] == "contain", "web splash resize mode must be contain")
        require_asset(web["splash"]["image"], EXPECTED_ASSETS[web["splash"]["image"]])
        require(web_manifest["name"] == web["name"], "web manifest name must match app config")
        require(web_manifest["short_name"] == web["shortName"], "web manifest short_name must match app config")
        require(web_manifest["lang"] == web["lang"], "web manifest lang must match app config")
        require(web_manifest["description"] == web["description"], "web manifest description must match app config")
        require(web_manifest["display"] == web["display"], "web manifest display must match app config")
        require(web_manifest["start_url"] == web["startUrl"], "web manifest start_url must match app config")
        require(web_manifest["scope"] == web["scope"], "web manifest scope must match app config")
        require(web_manifest["orientation"] == web["orientation"], "web manifest orientation must match app config")
        require(web_manifest["theme_color"] == web["themeColor"], "web manifest theme_color must match app config")
        require(
            web_manifest["background_color"] == web["backgroundColor"],
            "web manifest background_color must match app config",
        )
        manifest_icons = {icon["src"]: icon for icon in web_manifest["icons"]}
        require("/favicon.ico" in manifest_icons, "web manifest must include favicon")
        for src, expected_size in EXPECTED_WEB_ICONS.items():
            icon = manifest_icons.get(src)
            require(icon is not None, f"web manifest must include {src}")
            require(icon["sizes"] == f"{expected_size[0]}x{expected_size[1]}", f"{src} size metadata mismatch")
            require(icon["type"] == "image/png", f"{src} must be a PNG icon")
            require_public_png(src, expected_size)
        require('rel="manifest"' in web_html, "web HTML must link the web manifest")
        require('name="theme-color"' in web_html, "web HTML must set theme-color")
        require("apple-mobile-web-app-capable" in web_html, "web HTML must enable iOS home screen metadata")
        require(web["description"] in web_html, "web HTML description must match app config")

        plugins = app["plugins"]
        require("expo-router" in plugins, "expo-router plugin missing")
        require("expo-secure-store" in plugins, "expo-secure-store plugin missing")
        require(LOCAL_HTTP_PLUGIN in plugins, "local HTTP Android plugin missing")
        audio_plugin = next(
            (plugin for plugin in plugins if isinstance(plugin, list) and plugin[0] == "expo-audio"),
            None,
        )
        require(audio_plugin is not None, "expo-audio plugin missing")
        audio_options = audio_plugin[1]
        require(audio_options["recordAudioAndroid"] is True, "Android recording permission must be enabled")
        require(audio_options["enableBackgroundRecording"] is False, "background recording must stay disabled")
        require(audio_options["enableBackgroundPlayback"] is False, "background playback must stay disabled")

        preview = eas["build"]["preview"]
        production = eas["build"]["production"]
        require(preview["distribution"] == "internal", "preview builds must be internal")
        require(preview["android"]["buildType"] == "apk", "preview Android build must produce an APK")
        require(
            production["android"]["buildType"] == "app-bundle",
            "production Android build must produce an app bundle",
        )
        require(production["autoIncrement"] is True, "production builds must auto-increment")
    except (AssertionError, KeyError, OSError, ValueError, json.JSONDecodeError) as error:
        return fail(str(error))

    print("app config verification passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
