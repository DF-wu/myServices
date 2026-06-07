#!/usr/bin/env python3
"""Build the generated Android project when local native prerequisites exist."""

from __future__ import annotations

import os
import pathlib
import platform
import shutil
import subprocess

from android_sdk import find_sdk_dir

ROOT = pathlib.Path(__file__).resolve().parents[1]
ANDROID_ROOT = ROOT / "android"


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

    sdk_dir = find_sdk_dir(ANDROID_ROOT)
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
    sdk_dir = find_sdk_dir(ANDROID_ROOT)
    env = os.environ.copy()
    if sdk_dir:
        env.setdefault("ANDROID_HOME", str(sdk_dir))
        env.setdefault("ANDROID_SDK_ROOT", str(sdk_dir))
    print("running " + " ".join(command))
    return subprocess.run(command, cwd=ANDROID_ROOT, env=env, check=False).returncode


if __name__ == "__main__":
    raise SystemExit(main())
