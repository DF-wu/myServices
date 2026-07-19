# Homepage Theme Presets

These presets change only Homepage's visual settings and `custom.css`. Service
catalog, widgets, layout, bookmarks, and secret files are left in place.

## Available presets

| ID | Mode | Style | Best for |
|---|---|---|---|
| `dracula` | Dark | Purple/pink Dracula with the existing background | Restoring the current look |
| `obsidian` | Dark | Slate glass with emerald/cyan accents | Recommended for general daily use |
| `nord` | Dark | Muted arctic blue-gray | Calm, low-fatigue operations view |
| `cyber` | Dark | Near-black cyan/lime NOC console | Stronger monitoring-console character |
| `minimal` | Dark | Neutral zinc with low decoration | Fast scanning and low visual noise |
| `graphite` | Dark | Charcoal with amber focus | Dense catalog with clear emphasis |
| `rose-pine` | Dark | Mauve, rose, gold, and foam | A warmer personal dashboard |
| `daylight` | Light | Bright white, blue, and green | Light-mode daytime use |
| `paper` | Light | Light neutral with cobalt/coral accents | Clean catalog/documentation feel |
| `high-contrast` | Dark | Black/white with cyan/yellow focus | Maximum legibility |

## Switching from a Portainer Git stack

The stack uses `homepage/docker-compose.yml` from this repository. After these
files are pushed to GitHub, open the Homepage stack in Portainer:

1. Go to **Stacks → homepage → Editor**.
2. Under **Environment variables**, add or change `HOMEPAGE_THEME`.
3. Set it to one of the IDs in the table above, for example `obsidian`.
4. Click **Pull and redeploy** (or **Update the stack** with repository pull
   enabled). Do not use **Restart**; restart does not rerun the preset initializer.
5. Wait for `homepage-theme-init` to exit successfully and `homepage` to become
   healthy, then hard-refresh `https://hp.dfder.tw/` once.

Portainer stores the variables entered in the stack editor in `stack.env` and
uses them for Compose interpolation. The compose file maps the Homepage
`HOMEPAGE_VAR_*` values explicitly, so a `.env` file is not required in the Git
checkout. Keep the existing host paths, allowed hosts, and widget variables in
the stack environment when updating the stack.

The one-shot initializer downloads the preset from the same GitHub repository
and branch, changes only visual keys in the persistent `settings.yaml`, and
replaces `custom.css`. Homepage starts only after that succeeds. Portainer CE is
supported; **Enable relative path volumes** is not required.

Rollback is the same operation: set `HOMEPAGE_THEME=dracula`, then **Pull and
redeploy**. An unknown preset or download failure prevents the new Homepage
deployment from starting with a partial theme.

Optional variables normally stay at their defaults:

| Variable | Default | Purpose |
|---|---|---|
| `HOMEPAGE_THEME_REF` | `master` | Git branch/tag containing presets |
| `HOMEPAGE_THEME_REPOSITORY` | `DF-wu/myServices` | GitHub owner/repository |

## Local switching

From the repository root:

```bash
./scripts/switch-theme.sh list
./scripts/switch-theme.sh obsidian
./scripts/switch-theme.sh minimal --dry-run
./scripts/switch-theme.sh current
./scripts/switch-theme.sh history
./scripts/switch-theme.sh rollback
```

This host-side script is only for a local Compose deployment. It backs up the
two files it changes under
`/mnt/appdata/homepage/config/.theme-backups/`, validates the generated YAML,
invalidates Homepage's generated page cache, and restarts only the `homepage`
service. Use `--no-restart` when preparing a change for a later maintenance
window. `--config-dir` and
`HOMEPAGE_THEME_BACKUP_DIR` are available for non-default installations.

`dracula/custom.css` is an exact copy of the currently deployed Dracula CSS.
The other presets use `_base.css` plus their palette-specific `theme.css`.
