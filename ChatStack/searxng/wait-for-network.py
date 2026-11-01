#!/usr/bin/env python3
"""Gate engine initialization on local VPN/Valkey; check all three services."""
import os
import socket
import sys
import time
import urllib.request


def ready(include_web=False):
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    # Only loopback is contacted before the VPN's own health check succeeds.
    urls = ["http://127.0.0.1:9999/"]
    if include_web:
        urls.append("http://127.0.0.1:8080/healthz")
    for url in urls:
        with opener.open(url, timeout=2) as response:
            if response.status != 200:
                raise RuntimeError("Local service health check failed")
    with socket.create_connection(("127.0.0.1", 6379), timeout=2) as connection:
        connection.sendall(b"*1\r\n$4\r\nPING\r\n")
        response = b""
        while not response.endswith(b"\r\n"):
            data = connection.recv(64)
            if not data:
                raise RuntimeError("Valkey closed before its PONG")
            response += data
        if response != b"+PONG\r\n":
            raise RuntimeError("Unexpected Valkey health response")


if __name__ == "__main__":
    if sys.argv[1:] == ["--check"]:
        try:
            ready(include_web=True)
        except Exception:
            sys.exit(1)
        sys.exit(0)
    if sys.argv[1:]:
        raise SystemExit("Only --check is supported")
    waiting = False
    while True:
        try:
            ready()
            break
        except Exception:
            if not waiting:
                print("Waiting for local VPN and Valkey before loading search engines", flush=True)
                waiting = True
            time.sleep(2)
    os.execv("/usr/local/searxng/entrypoint.sh", ["/usr/local/searxng/entrypoint.sh"])
