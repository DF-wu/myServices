#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

python - <<'PY'
from __future__ import annotations
from pathlib import Path
import re
import sys

print("== Homepage migration secret scan ==")
print("Scanning handoff files; excluding private inventory, .env files, and placeholder examples.")

root = Path('.')
exclude_dirs = {'.git', 'inventory/private'}
exclude_files = {'config-template/.env.example', 'scripts/scan-secrets.sh'}
exclude_suffixes = {'.png', '.jpg', '.jpeg', '.gif', '.webp', '.ico', '.sqlite', '.db'}

patterns = [
    re.compile(r'(?i)(password|passwd|pwd)\s*[:=]\s*([A-Za-z0-9_@#%+./:$-]{4,})'),
    re.compile(r'(?i)(token|api[_ -]?key|apikey|secret|bearer)\s*[:=]\s*([A-Za-z0-9_./:+-]{8,})'),
    re.compile(r'(?i)sk-[A-Za-z0-9_-]{12,}'),
    re.compile(r'(?i)https?://[^\s/:@]+:[^\s/@]+@'),
    re.compile(r'(?i)zxcv[0-9A-Za-z]{3,}'),
]

allowed_line_markers = [
    'HOMEPAGE_VAR_',
    'HOMEPAGE_FILE_',
    'REPLACE_ME',
    '<redacted>',
    'your-secret-here',
    'apikeyapikeyapikey',
    'yourembyapikeyhere',
    'secret-bearing widgets',
    'secret scan',
    'Secret scan',
    'Do not put secrets',
    'must not include',
]

findings: list[str] = []
for path in sorted(root.rglob('*')):
    if not path.is_file():
        continue
    rel = path.as_posix().removeprefix('./')
    if rel in exclude_files:
        continue
    if path.name == '.env' or path.suffix in exclude_suffixes:
        continue
    if any(rel == d or rel.startswith(d + '/') for d in exclude_dirs):
        continue
    try:
        text = path.read_text(errors='ignore')
    except Exception:
        continue
    for no, line in enumerate(text.splitlines(), 1):
        if any(marker in line for marker in allowed_line_markers):
            continue
        if any(p.search(line) for p in patterns):
            findings.append(f'{rel}:{no}:{line}')

if findings:
    print('Potential literal secret(s) found:')
    for f in findings:
        print(f)
    sys.exit(1)

print('Secret scan passed.')
PY
