#!/usr/bin/env python3
"""Low-concurrency real engine checks; public example queries only."""
import argparse
import concurrent.futures
import json
import os
import time
import urllib.parse
import urllib.request
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", default=os.environ.get("SEARXNG_URL"),
                        help="Private instance URL (or set SEARXNG_URL locally)")
    parser.add_argument("--all", action="store_true", help="Include disabled engines")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if not args.url:
        parser.error("Supply --url or SEARXNG_URL for your private instance")
    base = args.url.rstrip("/")
    with urllib.request.urlopen(base + "/config", timeout=10) as response:
        engines = json.load(response)["engines"]

    def probe(engine):
        name = engine["name"]
        language = "en"
        query = "Docker"
        if name in {"google", "bing", "brave", "duckduckgo", "yahoo", "qwant",
                    "bilibili", "google news", "bing news", "duckduckgo news"}:
            query, language = "台灣 高鐵", "zh-TW"
        elif name in {"arxiv", "pubmed", "crossref", "semantic scholar", "google scholar"}:
            query = "large language models"
        elif name == "mdn":
            query = "fetch API"
        elif name in {"wikipedia", "wikidata"}:
            query = "Taiwan"
        elif name == "currency":
            query = "10 USD in TWD"
        elif name == "pypi":
            query = "requests"
        params = urllib.parse.urlencode(dict(
            q=query, format="json", engines=name, language=language, safesearch=0))
        started = time.monotonic()
        result = {"engine": name, "query": query, "language": language}
        try:
            with urllib.request.urlopen(base + "/search?" + params, timeout=25) as response:
                data = json.load(response)
                result.update(http=response.status, results=len(data.get("results", [])),
                              infoboxes=len(data.get("infoboxes", [])),
                              answers=len(data.get("answers", [])),
                              errors=data.get("unresponsive_engines", []))
        except Exception as error:
            result["error"] = str(error)
        result["seconds"] = round(time.monotonic() - started, 3)
        print(json.dumps(result, ensure_ascii=False), flush=True)
        return result

    selected = [e for e in engines if args.all or e.get("enabled")]
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(probe, selected))
    if args.output:
        args.output.write_text(json.dumps(results, ensure_ascii=False, indent=2) + "\n")
    web_ok = any(r["engine"] in {"google", "bing", "brave", "duckduckgo", "yahoo", "qwant"}
                 and r.get("results", 0) > 0 and not r.get("errors") for r in results)
    if not web_ok:
        raise SystemExit("No tested general web engine returned usable results")


if __name__ == "__main__":
    main()
