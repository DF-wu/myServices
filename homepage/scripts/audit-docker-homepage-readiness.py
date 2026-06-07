#!/usr/bin/env python3
"""Read-only Docker/Homepage readiness inventory.

Outputs container metadata useful for planning Homepage labels. Does not inspect env vars.
"""
from __future__ import annotations

import json
import subprocess
import sys


def run(cmd: list[str]) -> str:
    return subprocess.check_output(cmd, text=True)


def main() -> int:
    names = run(["docker", "ps", "--format", "{{.Names}}"]).splitlines()
    out = []
    for name in sorted(names):
        raw = run(["docker", "inspect", name])
        data = json.loads(raw)[0]
        cfg = data.get("Config") or {}
        host = data.get("HostConfig") or {}
        state = data.get("State") or {}
        labels = cfg.get("Labels") or {}
        out.append({
            "name": name,
            "image": cfg.get("Image"),
            "status": state.get("Status"),
            "health": (state.get("Health") or {}).get("Status"),
            "ports": data.get("NetworkSettings", {}).get("Ports"),
            "homepage_labels": {k: v for k, v in labels.items() if k.startswith("homepage.")},
            "compose_project": labels.get("com.docker.compose.project"),
            "compose_service": labels.get("com.docker.compose.service"),
            "network_mode": host.get("NetworkMode"),
        })
    json.dump(out, sys.stdout, ensure_ascii=False, indent=2)
    print()
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
