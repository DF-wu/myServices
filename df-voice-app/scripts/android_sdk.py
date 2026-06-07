#!/usr/bin/env python3
"""Helpers for locating Android SDK tools used by verification scripts."""

from __future__ import annotations

import os
import pathlib
import shutil


def parse_local_sdk_dir(android_root: pathlib.Path) -> pathlib.Path | None:
    local_properties = android_root / "local.properties"
    if not local_properties.exists():
        return None

    for raw_line in local_properties.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        key, separator, value = line.partition("=")
        if separator and key.strip() == "sdk.dir" and value.strip():
            return pathlib.Path(value.strip()).expanduser()
    return None


def find_sdk_dir(android_root: pathlib.Path) -> pathlib.Path | None:
    adb_on_path = shutil.which("adb")
    candidates: list[pathlib.Path | None] = [
        pathlib.Path(os.environ[name]).expanduser()
        if os.environ.get(name)
        else None
        for name in ("ANDROID_HOME", "ANDROID_SDK_ROOT")
    ]
    candidates.extend(
        [
            parse_local_sdk_dir(android_root),
            pathlib.Path.home() / ".local/share/android-sdk",
            pathlib.Path.home() / "Android/Sdk",
            pathlib.Path(adb_on_path).parent.parent if adb_on_path else None,
        ]
    )

    for candidate in candidates:
        if candidate and candidate.exists():
            return candidate

    return None


def find_adb(android_root: pathlib.Path) -> str | None:
    sdk_dir = find_sdk_dir(android_root)
    candidates = [
        sdk_dir / "platform-tools" / "adb" if sdk_dir else None,
        pathlib.Path(shutil.which("adb")) if shutil.which("adb") else None,
    ]
    for candidate in candidates:
        if candidate and candidate.exists():
            return str(candidate)
    return None
