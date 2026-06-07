# Docker Label Patterns

Homepage Docker labels are the best long-term mechanism for non-secret service card metadata. This document gives copy-paste patterns for Phase 2.

## Minimal card

```yaml
labels:
  - homepage.group=Observability
  - homepage.name=Speedtest
  - homepage.icon=speedtest-tracker.svg
  - homepage.href=https://REPLACE_ME
  - homepage.description=Speed test
  - homepage.weight=10
```

## Card with internal monitor

Use this when browser click URL and internal health URL differ.

```yaml
labels:
  - homepage.group=Media
  - homepage.name=Jellyfin
  - homepage.icon=jellyfin.svg
  - homepage.href=https://REPLACE_ME_PUBLIC_OR_LAN_URL
  - homepage.description=Media server
  - homepage.siteMonitor=http://jellyfin:8096
  - homepage.weight=20
```

`siteMonitor` makes a HEAD request and falls back to GET. If a public URL is protected by auth, use an internal URL for `siteMonitor`.

## Non-secret widget label

Only use label widgets when no secret is required.

```yaml
labels:
  - homepage.group=Observability
  - homepage.name=Netdata
  - homepage.icon=netdata.svg
  - homepage.href=https://REPLACE_ME
  - homepage.widget.type=netdata
  - homepage.widget.url=http://netdata:19999
```

## Secret-bearing widget: do not label the secret

Avoid this:

```yaml
# BAD: docker labels expose the key.
- homepage.widget.key=literal-secret-value
```

Prefer `services.yaml`:

```yaml
- Media:
    - Jellyfin:
        icon: jellyfin.svg
        href: https://REPLACE_ME
        widget:
          type: jellyfin
          url: http://jellyfin:8096
          key: "{{HOMEPAGE_VAR_JELLYFIN_API_KEY}}"
```

## Multiple Homepage instances

If DF later wants public/private dashboards, set `instanceName` in `settings.yaml` and scope labels:

```yaml
labels:
  - homepage.group=Media
  - homepage.name=Jellyfin
  - homepage.instance.internal.href=http://jellyfin.lan/
  - homepage.instance.public.href=https://jellyfin.example.invalid/
```

## Compose label syntax warning

If using mapping syntax and an array-like value, quote it as a string:

```yaml
labels:
  homepage.widget.fields: '["queued","wanted"]'
```

List syntax is usually less surprising:

```yaml
labels:
  - homepage.widget.fields=["queued","wanted"]
```

## Swarm warning

If Docker Swarm is ever introduced, labels must be under `deploy.labels`, and Homepage should run on a manager node with `swarm: true` in `docker.yaml`.
