# Assemulator YunoHost Package Scaffold

This folder contains a starter package structure for a YunoHost app package repository.

## Intended repository name

- `assemulator_ynh`

## What this scaffold does

- Installs Assemulator as a Docker Compose app bound to localhost only.
- Configures YunoHost Nginx reverse proxy for domain/path access.
- Provides install/remove/upgrade/backup/restore/change_url scripts.

## What you must customize before publishing package

1. In `manifest.toml`, replace all placeholders:
   - `YOUR_GITHUB_USER`
   - maintainer email/name
2. In `conf/docker-compose.yml`, set the final image path/tag if needed.
3. Test on a real YunoHost VM/server:
   - install
   - upgrade
   - backup/restore
   - change_url
   - remove/reinstall
4. Run YunoHost packaging checks before official catalog submission.

## Required executable bits

Before publishing the package repository, mark scripts executable:

```bash
git update-index --chmod=+x scripts/install scripts/remove scripts/upgrade scripts/backup scripts/restore scripts/change_url scripts/_common.sh
```

## Typical split

- App source repo: this repository (`Assemulator`)
- Package repo: dedicated YunoHost package repo (`assemulator_ynh`)
