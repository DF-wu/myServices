#!/usr/bin/env python3
"""Render only SearXNG's three services, preserving the existing ChatStack."""
import argparse
import os
from pathlib import Path

import yaml

SERVICES = ("searxng-vpn", "searxng-valkey", "searxng")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path,
                        default=Path("/mnt/appdata/ChatStack/searxng/deployment.compose.yml"))
    args = parser.parse_args()
    source = Path(__file__).resolve().parents[1] / "docker-compose.yml"
    model = yaml.safe_load(source.read_text())
    services = {name: model["services"][name] for name in SERVICES}
    assert services["searxng"]["network_mode"] == "service:searxng-vpn"
    assert services["searxng-valkey"]["network_mode"] == "service:searxng-vpn"
    assert not services["searxng"].get("ports")
    assert services["searxng-vpn"]["environment"]["FIREWALL_OUTBOUND_SUBNETS"] == ""
    output = {"name": "chatstack", "services": services,
              "networks": {"default": {"external": True, "name": "chatstack_default"}}}
    with os.fdopen(os.open(args.output, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), "w") as file:
        yaml.safe_dump(output, file, sort_keys=False)
    os.chmod(args.output, 0o600)
    print("Rendered only: " + ", ".join(SERVICES))
    print("Never use --remove-orphans or down against this partial model.")


if __name__ == "__main__":
    main()
