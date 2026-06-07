#!/usr/bin/env python3
from __future__ import annotations
import csv, json, re
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1]
PRIV = ROOT / 'inventory/private'
OUT = Path('/mnt/appdata/homepage/config/services.yaml')
TEMPLATE_OUT = ROOT / 'config-template/config/services.generated.yaml'
REPORT = ROOT / 'docs/16-stage2-service-catalog-report.md'

GROUP_RULES = [
    ('Network & Ingress', ['nginx', 'proxy', 'cloudflare', 'cloudflared', 'adguard', 'tailscale', 'vproxy', 'gluetun', 'flaresolverr']),
    ('Observability', ['netdata', 'uptime', 'status', 'goaccess', 'speedtest', 'grafana', 'prometheus']),
    ('AI & LLM', ['chat', 'open-webui', 'llm', 'api', 'claude', 'metamcp', 'sub2api', 'pplx', 'duck', 'deep', 'research', 'n8n', 'hf2api', 'qwen', 'vits', 'tgbot', 'telegram', 'sillytavern', 'canvas', 'conversion', 'ccr', 'crs']),
    ('Media', ['jellyfin', 'jellyseerr', 'theater', 'anime', 'ani', 'manga', 'suwayomi', 'moontv', 'luna', 'autobangumi', 'jackett', 'danmu']),
    ('Downloads & Network', ['qbittorrent', 'qbit', 'bt', 'aria2', 'download']),
    ('Photos & Files', ['nextcloud', 'immich', 'photo', 'photoprism', 'alist', 'rclone', 'easyimage', 'nas']),
    ('Databases & Admin', ['mariadb', 'mysql', 'postgres', 'redis', 'valkey', 'pgadmin', 'phpmyadmin', 'db', 'database', 'qdrant']),
    ('Backup & Maintenance', ['backrest', 'vaultwarden', 'portainer', 'dockge', 'komodo', 'teslamate', 'qiandao', 'oracle', 'watchtower']),
]
ICON_MAP = {
    'portainer': '/images/dracula-icons/portainer.png',
    'nginx': '/images/dracula-icons/nginx-proxy-manager.png',
    'proxy': '/images/dracula-icons/nginx-proxy-manager.png',
    'adguard': '/images/dracula-icons/adguardhome.png',
    'jellyfin': '/images/dracula-icons/jellyfin.png',
    'jellyseerr': '/images/dracula-icons/jellyseerr.png',
    'overseerr': '/images/dracula-icons/overseerr.png',
    'immich': '/images/dracula-icons/immich.png',
    'nextcloud': '/images/dracula-icons/nextcloud.png',
    'photoprism': '/images/dracula-icons/photoprism.png',
    'photo': '/images/dracula-icons/photoprism.png',
    'qbittorrent': '/images/dracula-icons/qbittorrent.png',
    'netdata': '/images/dracula-icons/netdata.png',
    'uptime': '/images/dracula-icons/uptime-kuma.png',
    'grafana': '/images/dracula-icons/grafana.png',
    'backrest': '/images/dracula-icons/backrest.png',
    'homeassistant': '/images/dracula-icons/homeassistant.png',
    'home assistant': '/images/dracula-icons/homeassistant.png',
    'truenas': '/images/dracula-icons/truenas.png',
    'cloudflare': '/images/dracula-icons/cloudflare.png',
    'cloudflared': '/images/dracula-icons/cloudflare.png',
    'tailscale': '/images/dracula-icons/tailscale.png',
    'suwayomi': '/images/dracula-icons/suwayomi.png',
    'mariadb': '/images/dracula-icons/mariadb.png',
    'mysql': '/images/dracula-icons/mysql.png',
    'phpmyadmin': '/images/dracula-icons/phpmyadmin.png',
    'pgadmin': '/images/dracula-icons/pgadmin.png',
    'vaultwarden': '/images/dracula-icons/vaultwarden.png',
    'github': '/images/dracula-icons/github.png',
    'docker': '/images/dracula-icons/docker.png',
    'speedtest': '/images/dracula-icons/speedtest.png',
    'alist': '/images/dracula-icons/alist.png',
}
WEB_PORT_HINTS = {'80', '81', '443', '3000', '3001', '5000', '5001', '5055', '5678', '8080', '8181', '8443', '9000', '9443', '9898', '12008'}


def norm(s): return (s or '').strip()
def slug(s): return re.sub(r'[^a-z0-9]+', '-', s.lower()).strip('-') or 'service'
def yaml_quote(s): return '"' + str(s).replace('"', '\\"') + '"'
def labelize(s): return ' '.join(w.upper() if w in {'llm','api','n8n','db','ui'} else w.capitalize() for w in re.split(r'[-_.]+', s) if w)
def title_from_domain(d):
    d = d.lower().strip()
    if d.endswith('.dfder.tw'): d = d[:-9]
    return labelize(d)
def group_for(*parts):
    t = ' '.join(p or '' for p in parts).lower()
    for group, keys in GROUP_RULES:
        if any(k in t for k in keys): return group
    return 'Core Infrastructure'
def icon_for(*parts):
    t = ' '.join(p or '' for p in parts).lower()
    for k, v in ICON_MAP.items():
        if k in t: return v
    return 'mdi-docker'
def image_short(image):
    if not image: return ''
    return image.split('@')[0]
def first_host_port(ports):
    if not isinstance(ports, dict): return None
    candidates=[]
    for container_port, bindings in ports.items():
        if not bindings: continue
        portnum = container_port.split('/')[0]
        for b in bindings:
            hp = b.get('HostPort')
            if not hp: continue
            candidates.append((0 if portnum in WEB_PORT_HINTS else 1, portnum, hp))
    if not candidates: return None
    candidates.sort()
    return candidates[0][2]
def public_url_key(url):
    u = url.rstrip('/').lower()
    return u

# Public NPM route indexes.
public_by_endpoint = {}
public_cards = []
npm_path = PRIV / 'npm-proxy-hosts.safe.csv'
if npm_path.exists():
    with npm_path.open() as f:
        for r in csv.DictReader(f):
            if r.get('enabled') != '1':
                continue
            try:
                domains = json.loads(r.get('domain_names') or '[]')
            except Exception:
                domains = []
            if not domains: continue
            href = 'https://' + domains[0]
            endpoint = f"{r.get('forward_host')}:{r.get('forward_port')}".lower()
            public_by_endpoint[endpoint] = href
            public_cards.append({
                'source': 'npm', 'name': title_from_domain(domains[0]), 'href': href,
                'group': group_for(domains[0], endpoint), 'icon': icon_for(domains[0], endpoint),
                'description': f"Public reverse proxy route to {r.get('forward_scheme')}://{endpoint}",
                'siteMonitor': href,
            })

# Heimdall URL index.
heimdall_by_url = {}
heimdall_cards = []
h_path = PRIV / 'heimdall-items.safe.json'
if h_path.exists():
    for r in json.loads(h_path.read_text()):
        if r.get('type') != 0: continue
        url = norm(r.get('url'))
        name = norm(r.get('title'))
        if not url or not name or not re.match(r'https?://', url): continue
        heimdall_by_url[public_url_key(url)] = name
        heimdall_cards.append({
            'source': 'heimdall', 'name': name, 'href': url, 'group': group_for(name, url),
            'icon': icon_for(name, url), 'description': 'Migrated from Heimdall safe export', 'siteMonitor': url,
        })

# Docker container cards: canonical for every running container.
docker_cards = []
docker_path = PRIV / 'docker-homepage-readiness.json'
containers = json.loads(docker_path.read_text()) if docker_path.exists() else []
for c in containers:
    if c.get('status') != 'running':
        continue
    name = c.get('name') or c.get('compose_service') or 'container'
    project = c.get('compose_project') or '<no-compose>'
    service = c.get('compose_service') or name
    image = image_short(c.get('image'))
    group = group_for(project, service, name, image)
    href = None
    hp = first_host_port(c.get('ports'))
    if hp:
        endpoint = f"192.168.10.13:{hp}".lower()
        href = public_by_endpoint.get(endpoint) or f"http://axolotl.newhome:{hp}"
    desc = f"Docker: {project}/{service}"
    if image:
        desc += f" ({image})"
    docker_cards.append({
        'source': 'docker', 'name': name, 'href': href, 'group': group,
        'icon': icon_for(project, service, name, image), 'description': desc,
        'server': 'local-docker', 'container': name, 'showStats': True,
        'siteMonitor': href if href else None,
    })

# Include public/Heimdall cards not already represented by Docker cards URL-wise.
seen_urls = {public_url_key(c['href']) for c in docker_cards if c.get('href')}
items = list(docker_cards)
for c in public_cards + heimdall_cards:
    key = public_url_key(c['href'])
    if key in seen_urls:
        continue
    seen_urls.add(key)
    items.append(c)

# Stable names: prefix duplicates.
name_count = {}
for it in items:
    base = it['name']
    name_count[base] = name_count.get(base, 0) + 1
for it in items:
    if name_count[it['name']] > 1:
        suffix = it.get('source', 'card')
        if it.get('source') == 'docker' and it.get('container'):
            suffix = it['container']
        it['name'] = f"{it['name']} ({suffix})"

# Group/sort.
groups = {}
for it in items:
    groups.setdefault(it['group'], []).append(it)
for arr in groups.values():
    arr.sort(key=lambda x: (x.get('source') != 'docker', x['name'].lower()))
order = ['Core Infrastructure','Network & Ingress','Observability','AI & LLM','Media','Downloads & Network','Photos & Files','Databases & Admin','Backup & Maintenance']
for g in sorted(groups):
    if g not in order: order.append(g)

lines = ['---', '# Generated by scripts/generate-services-from-inventory.py', '# services.yaml-first catalog. Every running Docker container is connected via local-docker stats.', '# Secret-bearing widgets are intentionally not auto-enabled.', '']
for group in order:
    arr = groups.get(group, [])
    if not arr: continue
    lines.append(f'- {group}:')
    for it in arr:
        sid = slug(it['group'] + '-' + it['name'])
        lines.append(f'    - {it["name"]}:')
        lines.append(f'        id: {sid}')
        lines.append(f'        icon: {it["icon"]}')
        if it.get('href'):
            lines.append(f'        href: {yaml_quote(it["href"])}')
        lines.append(f'        description: {yaml_quote(it["description"])}')
        if it.get('siteMonitor'):
            lines.append(f'        siteMonitor: {yaml_quote(it["siteMonitor"])}')
        if it.get('server') and it.get('container'):
            lines.append(f'        server: {it["server"]}')
            lines.append(f'        container: {yaml_quote(it["container"])}')
            lines.append('        showStats: true')
    lines.append('')
text = '\n'.join(lines) + '\n'
OUT.write_text(text)
TEMPLATE_OUT.write_text(text)

report = []
report.append('# Stage 2 Service Catalog Report')
report.append('')
report.append('Generated by `scripts/generate-services-from-inventory.py`.')
report.append('')
report.append('## Summary')
report.append('')
report.append(f'- Running Docker containers connected: {len(docker_cards)}')
report.append(f'- Total Homepage service cards generated: {len(items)}')
report.append(f'- Groups generated: {len(groups)}')
report.append(f'- Public NPM routes considered: {len(public_cards)}')
report.append(f'- Heimdall safe-export cards considered: {len(heimdall_cards)}')
report.append('')
report.append('## Group counts')
report.append('')
for group in order:
    if group in groups:
        report.append(f'- {group}: {len(groups[group])}')
report.append('')
report.append('## Notes')
report.append('')
report.append('- Every running Docker container has `server: local-docker`, `container: <name>`, and `showStats: true`.')
report.append('- Cards with known HTTP host ports or public reverse proxy routes include `href` and `siteMonitor`.')
report.append('- Secret-bearing widgets were not auto-enabled; they require reviewed credentials in `.env`.')
report.append('- NPM/Heimdall data is used only to enrich cards. Heimdall descriptions remain excluded by safe export.')
REPORT.write_text('\n'.join(report) + '\n')

print(f'wrote {OUT} with {len(items)} cards; docker={len(docker_cards)} groups={len(groups)}')
