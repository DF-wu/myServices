#!/usr/bin/env python3
"""Change only SearXNG search settings through the installed WebUI Config API."""
import argparse
import json
import os
import subprocess
from pathlib import Path

SETTINGS = {
    "web.search.enable": True,
    "web.search.engine": "searxng",
    "web.search.result_count": 8,
    "web.search.concurrent_requests": 2,
    "web.search.searxng_query_url": "http://searxng:8080/search",
    "web.search.searxng_language": "zh-TW",
    "web.search.bypass_web_loader": True,
    "web.search.bypass_embedding_and_retrieval": True,
}

PROGRAM = """
import asyncio, json, os, sys
from pathlib import Path
# docker exec does not inherit start.sh's generated environment. Reuse its
# existing key file inside the container; never replace or export the key.
if not os.environ.get('WEBUI_SECRET_KEY') and not os.environ.get('WEBUI_JWT_SECRET_KEY'):
    os.environ['WEBUI_SECRET_KEY'] = Path(os.environ.get(
        'WEBUI_SECRET_KEY_FILE', '/app/backend/.webui_secret_key')).read_text().strip()
from open_webui.models.config import Config
async def main():
    p = json.load(sys.stdin)
    if p['action'] == 'write':
        await Config.upsert(p['values'])
    elif p['action'] == 'restore':
        await Config.upsert(p['values'])
        for key in p['keys']:
            if key not in p['values']:
                await Config.delete(key)
    print('SEARXNG_CONFIG_JSON=' + json.dumps(await Config.get_many(*p['keys'])))
asyncio.run(main())
"""


def config(action, values=None):
    result = subprocess.run(["rtk", "proxy", "docker", "exec", "-i",
        "-e", "ENABLE_DB_MIGRATIONS=false", "open-webui-ollama", "python", "-c", PROGRAM],
        input=json.dumps({"action": action, "values": values, "keys": list(SETTINGS)}),
        text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError("WebUI Config API failed: " + result.stderr[-2000:])
    for line in reversed(result.stdout.splitlines()):
        if line.startswith("SEARXNG_CONFIG_JSON="):
            return json.loads(line.split("=", 1)[1])
    raise RuntimeError("WebUI Config API returned no structured result")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    actions = parser.add_mutually_exclusive_group()
    actions.add_argument("--apply", action="store_true")
    actions.add_argument("--restore", type=Path)
    parser.add_argument("--backup", type=Path, help="Required new private backup file for --apply")
    args = parser.parse_args()
    if args.apply:
        if args.backup is None:
            parser.error("--apply requires --backup")
        before = config("read")
        with os.fdopen(os.open(args.backup, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), "w") as file:
            json.dump(before, file, indent=2)
        after = config("write", SETTINGS)
        assert after == SETTINGS, "Persisted search configuration differs from requested values"
        print("PASS: 8 search settings applied and verified; prior values backed up privately")
    elif args.restore:
        before = json.loads(args.restore.read_text())
        assert set(before).issubset(SETTINGS), "Backup contains unrelated configuration keys"
        assert config("restore", before) == before
        print("PASS: prior search settings restored")
    else:
        assert config("read") == SETTINGS, "Persisted SearXNG settings are not configured"
        print("PASS: persisted Open WebUI SearXNG settings match the VPN-safe snippet flow")


if __name__ == "__main__":
    main()
