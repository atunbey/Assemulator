# Assemulator YunoHost Package Scaffold

This folder contains a starter package structure for a YunoHost app package repository.

## Intended repository name

- `assemulator_ynh`

## What this scaffold does

- Installs Assemulator as a Docker Compose app bound to localhost only.
- Configures YunoHost Nginx reverse proxy for domain/path access.
- Provides install/remove/upgrade/backup/restore/change_url scripts.

## What you must customize before publishing package

1. In `manifest.toml`, set final maintainer metadata and any optional fields for submission quality.
2. In `scripts/install`, set the final container image tag policy if needed.
3. Test on a real YunoHost VM/server:
   - install
   - upgrade
   - backup/restore
   - change_url
   - remove/reinstall
4. Run YunoHost packaging checks before official catalog submission.

## Quick lifecycle test commands

Run these on your YunoHost server after cloning the package repo (for example in `/root/assemulator_ynh`):

```bash
yunohost app install /root/assemulator_ynh --debug --args "domain=your.domain.tld&path=/assemulator"
yunohost app upgrade assemulator -u /root/assemulator_ynh --debug
yunohost backup create --apps assemulator --name assemulator-test --debug
yunohost app remove assemulator --debug
yunohost backup restore assemulator-test --apps assemulator --debug
yunohost app change-url assemulator -d your.domain.tld -p /retro --debug
yunohost app remove assemulator --debug
```

## Required executable bits

Before publishing the package repository, mark scripts executable:

```bash
git update-index --chmod=+x scripts/install scripts/remove scripts/upgrade scripts/backup scripts/restore scripts/change_url scripts/_common.sh
```

## Typical split

- App source repo: this repository (`Assemulator`)
- Package repo: dedicated YunoHost package repo (`assemulator_ynh`)
