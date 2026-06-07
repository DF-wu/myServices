#!/usr/bin/env python3
"""Build the generated Android project when local native prerequisites exist."""

from __future__ import annotations

import os
import pathlib
import platform
import shutil
import subprocess


ROOT = pathlib.Path(__file__).resolve().parents[1]
ANDROID_ROOT = ROOT / "android"


def parse_local_sdk_dir() -> pathlib.Path | None:
    local_properties = ANDROID_ROOT / "local.properties"
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


def find_sdk_dir() -> pathlib.Path | None:
    for env_name in ("ANDROID_HOME", "ANDROID_SDK_ROOT"):
        value = os.environ.get(env_name)
        if value:
            candidate = pathlib.Path(value).expanduser()
            if candidate.exists():
                return candidate

    local_sdk_dir = parse_local_sdk_dir()
    if local_sdk_dir and local_sdk_dir.exists():
        return local_sdk_dir

    return None


def check_prerequisites() -> int:
    if not ANDROID_ROOT.exists():
        print("android project missing; run npm run prebuild:android first")
        return 1

    java_home = os.environ.get("JAVA_HOME")
    java_on_path = shutil.which("java")
    java_binary = pathlib.Path(java_home) / "bin" / "java" if java_home else None
    if java_binary is None and java_on_path:
        java_binary = pathlib.Path(java_on_path)
    if java_binary is None or not java_binary.exists():
        print("Java not found; install JDK 17+ or set JAVA_HOME")
        return 1

    sdk_dir = find_sdk_dir()
    if sdk_dir is None:
        print(
            "Android SDK not found; set ANDROID_HOME/ANDROID_SDK_ROOT or "
            "android/local.properties sdk.dir"
        )
        return 1

    for child in ("platforms", "build-tools"):
        if not (sdk_dir / child).exists():
            print(f"Android SDK missing {child}; install API platform and build tools")
            return 1

    return 0


def main() -> int:
    prerequisite_status = check_prerequisites()
    if prerequisite_status:
        return prerequisite_status

    gradlew = ANDROID_ROOT / (
        "gradlew.bat" if platform.system() == "Windows" else "gradlew"
    )
    command = [str(gradlew), ":app:assembleDebug", "--no-daemon"]
    print("running " + " ".join(command))
    return subprocess.run(command, cwd=ANDROID_ROOT, check=False).returncode


if __name__ == "__main__":
    raise SystemExit(main())
