#!/usr/bin/env python3
"""Render a private inventory summary without exposing individual hosts/secrets."""
from __future__ import annotations
import json
from pathlib import Path

base = Path(__file__).resolve().parents[1]
priv = base / "inventory" / "private"

def load_json(name: str):
    p = priv / name
    if not p.exists():
        return None
    return json.loads(p.read_text())

containers = load_json("docker-homepage-readiness.json") or []
heimdall = load_json("heimdall-items.safe.json") or []

projects = {}
for c in containers:
    projects.setdefault(c.get("compose_project") or "<no-compose>", 0)
    projects[c.get("compose_project") or "<no-compose>"] += 1

print("# Private Inventory Summary")
print()
print(f"- Containers inventoried: {len(containers)}")
print(f"- Containers with homepage labels: {sum(bool(c.get('homepage_labels')) for c in containers)}")
print(f"- Compose projects observed: {len(projects)}")
print(f"- Heimdall items exported safely: {len(heimdall)}")
print(f"- Heimdall export includes descriptions: {any(any(k in x for k in ['description','appdescription','role']) for x in heimdall)}")
print()
print("## Compose project container counts")
for name, count in sorted(projects.items(), key=lambda x: (-x[1], x[0])):
    print(f"- {name}: {count}")
