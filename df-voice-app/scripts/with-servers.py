#!/usr/bin/env python3
"""Run a command while one or more local TCP servers are alive."""

from __future__ import annotations

import argparse
import os
import pathlib
import signal
import socket
import subprocess
import sys
import tempfile
import time


def wait_for_port(host: str, port: int, timeout: float, process: subprocess.Popen) -> bool:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if process.poll() is not None:
            return False
        try:
            with socket.create_connection((host, port), timeout=1):
                time.sleep(0.5)
                if process.poll() is not None:
                    return False
                return True
        except OSError:
            time.sleep(0.5)
    return False


def print_log(path: pathlib.Path) -> None:
    if path.exists():
        print(path.read_text(encoding="utf-8", errors="replace"), file=sys.stderr)


def stop(process: subprocess.Popen) -> None:
    if process.poll() is not None:
        return
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    try:
        process.wait(timeout=10)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--server", action="append", required=True)
    parser.add_argument("--port", action="append", required=True, type=int)
    parser.add_argument("--host", default="localhost")
    parser.add_argument("--timeout", default=30, type=float)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()

    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not command:
        print("missing command after --", file=sys.stderr)
        return 2
    if len(args.server) != len(args.port):
        print("--server and --port counts must match", file=sys.stderr)
        return 2

    processes: list[tuple[subprocess.Popen, pathlib.Path]] = []
    try:
        for index, (server, port) in enumerate(zip(args.server, args.port), start=1):
            log = pathlib.Path(tempfile.gettempdir()) / f"df-voice-app-server-{index}.log"
            handle = log.open("w", encoding="utf-8")
            process = subprocess.Popen(
                server,
                shell=True,
                stdout=handle,
                stderr=subprocess.STDOUT,
                start_new_session=True,
            )
            handle.close()
            processes.append((process, log))
            print(f"waiting for server {index} on {args.host}:{port}")
            if not wait_for_port(args.host, port, args.timeout, process):
                print(f"server {index} did not become ready: {server}", file=sys.stderr)
                print_log(log)
                return 1

        result = subprocess.run(command, check=False)
        if result.returncode != 0:
            for _, log in processes:
                print_log(log)
        return result.returncode
    finally:
        for process, _ in processes:
            stop(process)


if __name__ == "__main__":
    raise SystemExit(main())
