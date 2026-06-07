#!/usr/bin/env python3
"""Export Heimdall items without secrets.

Default output intentionally excludes description/appdescription/role because local Heimdall
notes often contain credentials or operational secrets.
"""
from __future__ import annotations

import argparse
import csv
import json
import re
import sqlite3
import sys
from pathlib import Path

SECRET_PATTERNS = [
    (re.compile(r"(?i)(password|passwd|pwd|token|apikey|api[_ -]?key|secret|bearer)\s*[:=]\s*[^\s,;]+"), r"\1=<redacted>"),
    (re.compile(r"(?i)sk-[A-Za-z0-9_-]{12,}"), "sk-<redacted>"),
    (re.compile(r"(?i)(https?://)([^/@\s:]+):([^/@\s]+)@"), r"\1<redacted>:<redacted>@"),
]


def redact(value: object) -> object:
    if value is None:
        return None
    if not isinstance(value, str):
        return value
    out = value
    for pat, repl in SECRET_PATTERNS:
        out = pat.sub(repl, out)
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", default="/mnt/appdata/heimdall/www/app.sqlite")
    ap.add_argument("--format", choices=["json", "csv"], default="json")
    ap.add_argument("--include-descriptions", action="store_true", help="Include redacted descriptions; off by default.")
    args = ap.parse_args()

    db = Path(args.db)
    if not db.exists():
        raise SystemExit(f"Heimdall DB not found: {db}")

    conn = sqlite3.connect(str(db))
    conn.row_factory = sqlite3.Row

    cols = [
        'i.id', 'i.title', 'i.url', 'i.colour', 'i.icon', 'i.appid', 'i.pinned',
        'i."order" as order_index', 'i.type', 'i.class', 'i.created_at', 'i.updated_at',
        'a.name as application_name', 'a.icon as application_icon', 'a.website as application_website',
    ]
    if args.include_descriptions:
        cols.extend(['i.description', 'i.appdescription', 'i.role', 'a.description as application_description'])

    rows = [dict(r) for r in conn.execute(f"""
        select {', '.join(cols)}
        from items i
        left join applications a on i.appid = a.appid
        order by i.type, i."order", i.id
    """)]

    tags_by_item: dict[int, list[str]] = {}
    for r in conn.execute("""
        select child.id as item_id, tag.title as tag_title
        from item_tag jt
        join items child on child.id = jt.item_id
        join items tag on tag.id = jt.tag_id
        order by tag.title, child.title
    """):
        tags_by_item.setdefault(r["item_id"], []).append(r["tag_title"])

    for row in rows:
        row["tags"] = tags_by_item.get(row["id"], [])
        for k, v in list(row.items()):
            row[k] = redact(v)

    if args.format == "json":
        json.dump(rows, sys.stdout, ensure_ascii=False, indent=2)
        print()
    else:
        fieldnames = sorted({k for row in rows for k in row.keys()})
        writer = csv.DictWriter(sys.stdout, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            row = dict(row)
            row["tags"] = ";".join(row.get("tags") or [])
            writer.writerow(row)

    return 0

if __name__ == "__main__":
    raise SystemExit(main())
