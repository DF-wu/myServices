#!/usr/bin/env python3
"""Install and launch the debug APK on a connected Android device/emulator."""

from __future__ import annotations

import json
import os
import pathlib
import subprocess
import time

from android_sdk import find_adb

ROOT = pathlib.Path(__file__).resolve().parents[1]
ANDROID_ROOT = ROOT / "android"
APP_JSON = ROOT / "app.json"
APK = ROOT / "android" / "app" / "build" / "outputs" / "apk" / "debug" / "app-debug.apk"
ARTIFACTS = ROOT / "test-artifacts"
DEFAULT_LAUNCH_WAIT_SECONDS = 25


def run(command: list[str], *, check: bool = True, binary: bool = False) -> subprocess.CompletedProcess:
    return subprocess.run(
        command,
        check=check,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=not binary,
    )


def android_package_name() -> str:
    app = json.loads(APP_JSON.read_text(encoding="utf-8"))
    return app["expo"]["android"]["package"]


def report_failure(label: str, result: subprocess.CompletedProcess) -> None:
    print(f"{label} failed with exit code {result.returncode}")
    if result.stdout:
        print(result.stdout.strip())
    if result.stderr:
        print(result.stderr.strip())


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


def install_apk(device_args: list[str]) -> bool:
    result = run([*device_args, "install", "--no-streaming", "-r", str(APK)], check=False)
    if result.returncode == 0:
        return True

    if "Unknown option: --no-streaming" in result.stderr or "Unknown option: --no-streaming" in result.stdout:
        result = run([*device_args, "install", "-r", str(APK)], check=False)
        if result.returncode == 0:
            return True

    report_failure("adb install", result)
    return False


def launch_app(device_args: list[str], package_name: str) -> bool:
    monkey = run(
        [
            *device_args,
            "shell",
            "monkey",
            "-p",
            package_name,
            "-c",
            "android.intent.category.LAUNCHER",
            "1",
        ],
        check=False,
    )
    if monkey.returncode == 0:
        return True

    resolved = run(
        [
            *device_args,
            "shell",
            "cmd",
            "package",
            "resolve-activity",
            "--brief",
            "-a",
            "android.intent.action.MAIN",
            "-c",
            "android.intent.category.LAUNCHER",
            "-p",
            package_name,
        ],
        check=False,
    )
    component = next(
        (
            line.strip()
            for line in reversed(resolved.stdout.splitlines())
            if "/" in line and not line.startswith("priority=")
        ),
        None,
    )
    if not component:
        report_failure("monkey launch", monkey)
        report_failure("resolve launch activity", resolved)
        return False

    started = run([*device_args, "shell", "am", "start", "-n", component], check=False)
    if started.returncode != 0:
        report_failure("am start", started)
        return False

    return True


def main() -> int:
    adb = find_adb(ANDROID_ROOT)
    if not adb:
        print(
            "adb not found; install Android platform-tools, set ANDROID_HOME, "
            "or add sdk.dir to android/local.properties"
        )
        return 1

    if not APK.exists():
        print("debug APK missing; run npm run verify:android-build first")
        return 1

    serial = connected_device(adb)
    if not serial:
        return 1

    package_name = android_package_name()
    device_args = [adb, "-s", serial]
    if not install_apk(device_args):
        return 1

    run([*device_args, "reverse", "tcp:8081", "tcp:8081"], check=False)
    run([*device_args, "shell", "am", "force-stop", package_name], check=False)
    run([*device_args, "logcat", "-c"], check=False)
    if not launch_app(device_args, package_name):
        return 1

    launch_wait_seconds = int(os.environ.get("ANDROID_LAUNCH_WAIT_SECONDS", DEFAULT_LAUNCH_WAIT_SECONDS))
    time.sleep(launch_wait_seconds)

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
    if 'ReactNativeJS: Running "main"' not in logcat.stdout:
        print(f"{package_name} launched but React Native did not report JS startup")
        return 1

    print(f"android runtime verification passed on {serial}; pid={pid}")
    print(f"artifacts: {ARTIFACTS}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
