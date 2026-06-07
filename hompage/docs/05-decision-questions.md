# Consolidated Questions for DF

Please answer these once before Phase 2 starts. These are the only decisions that should block implementation.

## 1. Exposure and authentication

Which exposure model should Homepage use?

- A. LAN/Tailscale only.
- B. Public domain behind Nginx Proxy Manager access list / Basic Auth.
- C. Public domain behind Cloudflare Access.
- D. Other.

Related: what final hostname should be used? If public, should it replace the old Heimdall route later, or use a new hostname first?

## 2. Runtime port and path

Is `33000:3000` acceptable for the temporary Phase 2 local test port? If not, provide preferred port.

Should runtime config live at `/mnt/appdata/homepage/config` as recommended, or inside the repo directory?

## 3. Visual direction

Choose the starting visual style:

- A. Clean dark slate, professional, low-noise.
- B. Glassy dark with background image and subtle blur.
- C. Minimal light theme.
- D. Custom direction.

If using a background image, provide the image or approve using a simple gradient/CSS-only background first.

## 4. Group/tab layout

Approve or adjust this tab plan:

- `Core`
- `AI`
- `Media`
- `Data`
- `External`

Should any service categories be hidden from the main dashboard by default, especially download/VPN/admin tools?

## 5. Automatic discovery depth

Which long-term model do you prefer?

- A. Mostly `services.yaml`, minimal labels.
- B. Labels for non-secret cards; YAML/env placeholders for secret widgets. **Recommended.**
- C. Labels for almost everything, including widgets where possible.

## 6. Secrets/API widgets

Which widgets do you want enabled in the first pass? Each may require creating or retrieving an API key/token/app password.

Recommended first pass:

- Portainer
- Nginx Proxy Manager
- Netdata
- Uptime Kuma
- Backrest
- Jellyfin
- Immich
- Nextcloud
- AdGuard

Optional first pass:

- qBittorrent
- PhotoPrism
- Home Assistant
- Gluetun
- Suwayomi
- TrueNAS
- Tailscale

## 7. Heimdall cleanup policy

For entries imported from Heimdall, should the next agent:

- A. Import every non-secret link first, then you clean later.
- B. Import only clearly active/current services, skip stale/duplicates.
- C. Create a review list and ask before adding uncertain entries. **Recommended.**

## 8. Old Heimdall route

During Stage 3, should the old Heimdall hostname become Homepage, or should Heimdall simply go offline and Homepage keep its new hostname?

## 9. Git/Portainer workflow

Should Phase 2 changes be committed to `myServices` git after successful local test? If yes, should the commit contain only template/config without `.env` and without private inventory?
