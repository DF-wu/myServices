#!/usr/bin/env python3
"""Install and launch the debug APK on a connected Android device/emulator."""

from __future__ import annotations

import json
import os
import pathlib
import shutil
import subprocess
import time


ROOT = pathlib.Path(__file__).resolve().parents[1]
APP_JSON = ROOT / "app.json"
APK = ROOT / "android" / "app" / "build" / "outputs" / "apk" / "debug" / "app-debug.apk"
ARTIFACTS = ROOT / "test-artifacts"


def run(command: list[str], *, check: bool = True, binary: bool = False) -> subprocess.CompletedProcess:
    return subprocess.run(
        command,
        check=check,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=not binary,
    )


def find_adb() -> str | None:
    sdk_root = os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT")
    candidates = [
        pathlib.Path(sdk_root) / "platform-tools" / "adb" if sdk_root else None,
        pathlib.Path(shutil.which("adb")) if shutil.which("adb") else None,
    ]
    for candidate in candidates:
        if candidate and candidate.exists():
            return str(candidate)
    return None


def android_package_name() -> str:
    app = json.loads(APP_JSON.read_text(encoding="utf-8"))
    return app["expo"]["android"]["package"]


def connected_device(adb: str) -> str | None:
    requested = os.environ.get("ANDROID_SERIAL")
    output = run([adb, "devices", "-l"]).stdout
    devices: list[str] = []
    blocked: list[str] = []
    for line in output.splitlines()[1:]:
        parts = line.split()
        if len(parts) < 2:
            continue
        serial, state = parts[0], parts[1]
        if state == "device":
            devices.append(serial)
        elif state in {"offline", "unauthorized"}:
            blocked.append(f"{serial} ({state})")

    if requested:
        if requested in devices:
            return requested
        print(f"ANDROID_SERIAL={requested} is not an online device")
        return None

    if len(devices) == 1:
        return devices[0]
    if len(devices) > 1:
        print(f"multiple devices online; set ANDROID_SERIAL. devices={', '.join(devices)}")
        return None
    if blocked:
        print(f"no online adb devices; blocked devices={', '.join(blocked)}")
    else:
        print("no online adb devices; connect a device or start an emulator")
    return None


def main() -> int:
    adb = find_adb()
    if not adb:
        print("adb not found; install Android platform-tools or set ANDROID_HOME")
        return 1

    if not APK.exists():
        print("debug APK missing; run npm run verify:android-build first")
        return 1

    serial = connected_device(adb)
    if not serial:
        return 1

    package_name = android_package_name()
    device_args = [adb, "-s", serial]
    run([*device_args, "install", "-r", str(APK)])
    run([
        *device_args,
        "shell",
        "monkey",
        "-p",
        package_name,
        "-c",
        "android.intent.category.LAUNCHER",
        "1",
    ])
    time.sleep(3)

    pid = run([*device_args, "shell", "pidof", package_name], check=False).stdout.strip()
    if not pid:
        print(f"{package_name} did not stay running after launch")
        return 1

    ARTIFACTS.mkdir(exist_ok=True)
    screenshot = run([*device_args, "exec-out", "screencap", "-p"], binary=True)
    (ARTIFACTS / "android-runtime.png").write_bytes(screenshot.stdout)
    logcat = run([*device_args, "logcat", "-d", "-t", "400"], check=False)
    (ARTIFACTS / "android-runtime-logcat.txt").write_text(logcat.stdout, encoding="utf-8")

    if "FATAL EXCEPTION" in logcat.stdout and package_name in logcat.stdout:
        print(f"{package_name} launched but logcat contains a fatal exception")
        return 1

    print(f"android runtime verification passed on {serial}; pid={pid}")
    print(f"artifacts: {ARTIFACTS}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
