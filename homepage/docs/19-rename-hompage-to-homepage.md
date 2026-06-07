# Rename Report — `hompage` to `homepage`

Created after DF asked why axolotl did not show a `homepage` folder.

## Root cause

The working directory had been created as:

```text
~/workspace/myServices/hompage
```

This was a typo. The deployed container names were already `homepage` and `homepage-dockerproxy`, but the Git directory and Docker Compose project name were `hompage` because Compose inferred the project name from the directory.

## Changes performed

1. Stopped the old `hompage` Compose stack:

```bash
cd ~/workspace/myServices/hompage
docker compose down
```

2. Renamed directory:

```bash
mv ~/workspace/myServices/hompage ~/workspace/myServices/homepage
```

3. Replaced documentation and script references from `hompage` to `homepage`.

4. Added explicit Compose project name to both compose files:

```yaml
name: homepage
```

Files updated:

```text
homepage/docker-compose.yml
homepage/config-template/docker-compose.yml
```

5. Restarted the stack from the corrected path:

```bash
cd ~/workspace/myServices/homepage
docker compose up -d
```

6. Regenerated inventory and `services.yaml` so generated descriptions no longer use the old typo project name.

## Verified result

Correct directory now exists:

```text
~/workspace/myServices/homepage
```

Old typo directory no longer exists:

```text
~/workspace/myServices/hompage
```

Docker Compose now reports:

```text
homepage running(2) /home/df/workspace/myServices/homepage/docker-compose.yml
```

Containers are healthy:

```text
homepage               Up / healthy / 0.0.0.0:33080->3000/tcp
homepage-dockerproxy   Up / 2375/tcp
```

Local HTTP check:

```text
http://127.0.0.1:33080/ -> HTTP 200
```

Homepage API services:

```text
groups: 9
cards: 111
```

## Notes

Runtime config did not move and remains:

```text
/mnt/appdata/homepage/config
```

Runtime image assets remain:

```text
/mnt/appdata/homepage/images
```

Ignored private files under the project, such as `.env` and `inventory/private/`, moved with the directory locally but remain excluded from git.
