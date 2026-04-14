# bt-gluetun / qBittorrent Investigation Report

Last updated: 2026-04-02 (Asia/Taipei)

## Summary

This report records the investigation into the `bt-gluetun` + `qbittorrent-enhanced` stack, the actions already taken, the current runtime state, and the migration assessment for `ddsderek/qbittorrentee`.

The main conclusion is simple: the original problem was **not** a full `gluetun` failure. The primary fault was inside qBittorrent session restore and runtime load. qBittorrent repeatedly entered a state where one worker thread consumed a full CPU core, the WebUI accepted TCP connections but returned no response, and DHT appeared broken as a downstream symptom.

## Stack Under Investigation

Compose folder:

- `qbittorrent-enhanced/docker-compose.yml`

Current deploy shape:

- `bt-gluetun`: `qmcgaw/gluetun`
- `qbittorrent-enhanced`: `superng6/qbittorrentee`
- qBittorrent shares the VPN network namespace with Gluetun via `network_mode: "container:bt-gluetun"`

Mounted paths:

- Downloads: `/mnt/mydata/BT/qbittorrentDownloads/data -> /data`
- qB config: `/mnt/appdata/qbittorrent-enhanced/qbittorrent-enhanced-config -> /config`
- Gluetun state: `/mnt/appdata/qbittorrent-enhanced/gluetun -> /gluetun`

Published ports are exposed on the Gluetun container:

- WebUI: `58080/tcp`
- BT listen: `51001/tcp`
- BT listen: `51001/udp`

## What Was Observed

### 1. Gluetun was not fully dead

Observed state during investigation:

- `bt-gluetun` was healthy
- `qbittorrent-enhanced` was running
- qBittorrent had UDP and TCP listeners on port `51001`

This ruled out the simplest explanation of “the VPN container is down.”

### 2. qBittorrent was repeatedly stuck

Observed runtime symptoms:

- qB WebUI accepted TCP connections but timed out without returning data
- a single qBittorrent thread stayed near 100% CPU
- qB memory usage grew large during the stuck state
- UDP receive backlog on `51001/udp` built up heavily

This pattern matched “qBittorrent session/runtime overload” much more closely than “DHT disabled” or “ports closed.”

### 3. DHT was enabled, but not healthy

The qBittorrent logs showed DHT support enabled. That means “DHT nodes = 0” was not caused by DHT being turned off in settings. Instead, DHT failure was treated as a secondary symptom of qBittorrent being overloaded or otherwise unable to keep up with peer and bootstrap traffic.

### 4. DNS instability existed, but did not look like the primary fault

Gluetun logs showed repeated DNS-over-TLS problems against Quad9 (`:853` reset/timeout). That could make DHT bootstrap worse, but direct checks showed DHT bootstrap hostnames could still resolve at least some of the time. The stronger evidence still pointed at qBittorrent itself.

## Primary Root Cause Assessment

The strongest working theory from the investigation was:

1. qBittorrent restored a problematic session state at startup
2. one or more hot torrents then pushed libtorrent into sustained high load
3. WebUI responsiveness collapsed
4. DHT looked broken because qBittorrent could not process network traffic normally

Earlier config review also found that qBittorrent had previously been configured with very aggressive limits, including extremely high values for active torrents, connections, uploads, and HTTP announces. Those settings increased risk, but later checks confirmed the user had already lowered several of them. Even after that reduction, qBittorrent still entered the bad state, which means the root problem was not only the old global limits.

## Session Repair Work Already Performed

### Backup created

Before making changes, the following files were backed up to:

- `/tmp/qbt-session-repair-lHBMUF`

Backed up items:

- `qBittorrent.conf`
- `queue` (saved as `queue.bak`)
- `3e5b4673d97b96f1eaa1409668c3d300da4168b2.fastresume`
- `e089862e4717921cb6bd89cf7fbdb0af78c8bfbc.fastresume`

### Changes made

The repair deliberately avoided deleting healthy torrent tasks.

Only the following stale/problem session references were removed:

From `BT_backup/queue`:

- `aa53368a9b070e6265c20e58c415076c18c62d12`
- `36ba2e234a008ec622edc691f741d464dc6cfc57`
- `77cd8ddfdd4a378eb8ce9ce7e1a16f3d900699eb`
- `e089862e4717921cb6bd89cf7fbdb0af78c8bfbc`
- `3e5b4673d97b96f1eaa1409668c3d300da4168b2`

Deleted orphan session files:

- `3e5b4673d97b96f1eaa1409668c3d300da4168b2.fastresume`
- `e089862e4717921cb6bd89cf7fbdb0af78c8bfbc.fastresume`

These two `.fastresume` files had no paired `.torrent` files. Healthy paired torrent tasks were intentionally left untouched.

## Runtime Result After Repair

### What improved

After the targeted session cleanup and qBittorrent restart:

- qB WebUI recovered and returned `HTTP/1.1 200 OK`
- the container stayed up for minutes instead of hanging immediately
- the stack was usable again instead of fully frozen

### What did not fully clear

Even after recovery:

- qBittorrent still kept one CPU core heavily loaded
- UDP backlog on `51001/udp` built up again later

This means the most catastrophic freeze was relieved, but the stack still has a high-load condition and likely still contains at least one hot torrent or active session path that stresses libtorrent heavily.

## Suspected Remaining High-Load Items

The logs repeatedly showed these torrent names early in restore:

- `暑假作业(林晓函，张婉莹，罗智莹，唐文慧，晨曦等等62.4G)`
- `暑假作业系列`

Those names were strongly associated with the earlier performance warnings and remain suspicious. The session cleanup completed so far was intentionally conservative: it removed only stale queue references and orphan fastresume files. It did **not** delete healthy paired torrent tasks solely by name guess.

## Research Result: `ddsderek/qbittorrentee`

### Maintenance status

`ddsderek/qbittorrentee` appears to be a real, maintained qBittorrent Enhanced Edition image.

Evidence gathered during research:

- Docker Hub showed it updated about four months ago at the time of inspection
- the public source repo is `DDSRem-Dev/qBittorrent-Enhanced-Edition-Docker`
- that repo tracks `c0re100/qBittorrent-Enhanced-Edition`
- published versions include the `5.1.3 / 5.1.3.10` generation

### Important compatibility note

This image is **not** a safe “change only the image line and nothing else” migration for the current stack.

Reason:

- current stack shape: `/data` for downloads, `/config` for qB config, Gluetun namespace sharing
- `ddsderek` official deployment model: single `/data` structure, with config under `/data/config` and session data under `/data/data/BT_backup`

That means the image is usable, but not a guaranteed zero-change swap for the current layout.

## Direct Recommendation

### Short version

- If the goal is **stability first**, do **not** assume switching to `ddsderek` alone will fix the root problem.
- The investigation so far points more strongly to qBittorrent session/runtime state than to the current image wrapper itself.

### Practical recommendation

1. Keep the current stack usable with the targeted session cleanup already performed
2. If high CPU and UDP backlog continue, isolate the next hot torrent conservatively rather than bulk-deleting tasks
3. Treat `ddsderek/qbittorrentee` as a migration candidate only if you are willing to do a controlled path/volume alignment, not a blind image swap

## Files and Paths Referenced in This Work

Compose and env in repo:

- `qbittorrent-enhanced/docker-compose.yml`
- `qbittorrent-enhanced/.env`

Live runtime config outside repo:

- `/mnt/appdata/qbittorrent-enhanced/qbittorrent-enhanced-config`
- `/mnt/appdata/qbittorrent-enhanced/gluetun`

Session repair backup:

- `/tmp/qbt-session-repair-lHBMUF`

## Final Status

At the end of this work:

- the stack is no longer in the original full WebUI timeout state
- qBittorrent remains under significant runtime load
- user download tasks were preserved except for stale/orphan session references
- `ddsderek/qbittorrentee` has been researched and judged to be maintained, but not a zero-change replacement for the current deployment
