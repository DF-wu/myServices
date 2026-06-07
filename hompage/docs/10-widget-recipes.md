# Widget Recipes

These are first-pass recipes for widgets likely useful in DF's homelab. Replace URLs with the route reachable from the Homepage container, not necessarily the browser URL.

## Portainer

```yaml
widget:
  type: portainer
  url: https://REPLACE_ME_PORTAINER_URL
  env: 1
  key: "{{HOMEPAGE_VAR_PORTAINER_KEY}}"
```

Create an access key in Portainer and use the correct environment ID from the Portainer URL.

## Nginx Proxy Manager

```yaml
widget:
  type: npm
  url: http://REPLACE_ME_NPM_INTERNAL_URL
  username: "{{HOMEPAGE_VAR_NPM_USERNAME}}"
  password: "{{HOMEPAGE_VAR_NPM_PASSWORD}}"
```

Use the admin UI credentials or a dedicated account if available.

## Netdata

```yaml
widget:
  type: netdata
  url: http://REPLACE_ME_NETDATA_URL
```

No credential is shown in the basic upstream recipe. If the route is protected, place Homepage on a network/path that can reach a safe internal endpoint.

## Uptime Kuma

```yaml
widget:
  type: uptimekuma
  url: http://REPLACE_ME_KUMA_URL
  slug: REPLACE_ME_STATUS_PAGE_SLUG
```

Homepage uses a status page slug, not a full private API.

## Backrest

```yaml
widget:
  type: backrest
  url: http://REPLACE_ME_BACKREST_URL
  username: "{{HOMEPAGE_VAR_BACKREST_USERNAME}}"
  password: "{{HOMEPAGE_VAR_BACKREST_PASSWORD}}"
```

Username/password are optional if Backrest auth is disabled.

## Jellyfin

```yaml
widget:
  type: jellyfin
  url: http://REPLACE_ME_JELLYFIN_INTERNAL_URL
  key: "{{HOMEPAGE_VAR_JELLYFIN_API_KEY}}"
  version: 2
  enableBlocks: true
  enableNowPlaying: true
  fields: ["movies", "series", "episodes", "songs"]
```

Generate a Jellyfin API key from the admin dashboard.

## Immich

```yaml
widget:
  type: immich
  url: http://REPLACE_ME_IMMICH_INTERNAL_URL
  key: "{{HOMEPAGE_VAR_IMMICH_API_KEY}}"
  version: 2
```

The key should include server statistics permission.

## Nextcloud

```yaml
widget:
  type: nextcloud
  url: https://REPLACE_ME_NEXTCLOUD_URL
  key: "{{HOMEPAGE_VAR_NEXTCLOUD_TOKEN}}"
  fields: ["freespace", "activeusers", "numfiles", "numshares"]
```

Prefer NC-Token/app token over account password.

## AdGuard Home

```yaml
widget:
  type: adguard
  url: http://REPLACE_ME_ADGUARD_URL
  username: "{{HOMEPAGE_VAR_ADGUARD_USERNAME}}"
  password: "{{HOMEPAGE_VAR_ADGUARD_PASSWORD}}"
```

## qBittorrent

```yaml
widget:
  type: qbittorrent
  url: http://REPLACE_ME_QBITTORRENT_INTERNAL_URL
  username: "{{HOMEPAGE_VAR_QBITTORRENT_USERNAME}}"
  password: "{{HOMEPAGE_VAR_QBITTORRENT_PASSWORD}}"
  enableLeechProgress: true
  enableLeechSize: true
```

Keep download tools behind auth/VPN. Do not make this the first public widget.

## Home Assistant

```yaml
widget:
  type: homeassistant
  url: http://REPLACE_ME_HA_URL
  key: "{{HOMEPAGE_VAR_HOMEASSISTANT_TOKEN}}"
  custom:
    - state: sensor.total_power
      label: Power
    - template: "{{ states.light|selectattr('state','equalto','on')|list|length }}"
      label: lights on
```

Needs a long-lived access token.

## TrueNAS

```yaml
widget:
  type: truenas
  url: http://REPLACE_ME_TRUENAS_URL
  version: 2
  key: "{{HOMEPAGE_VAR_TRUENAS_API_KEY}}"
  enablePools: false
```

TrueNAS is high-importance infrastructure. Ask DF before enabling and use minimal permissions.
