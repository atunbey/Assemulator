# Assemulator

Assemulator is a Blazor WebAssembly retro gaming frontend served as static files via Nginx.

## Local run with Docker

```bash
docker compose up -d --build
```

App URL:

- http://localhost:8088

## Environment-safe Nextcloud configuration

The app uses a runtime file (`wwwroot/runtime-config.json`) so environment-specific
Nextcloud values can change without rebuilding the Blazor app.

Contract used by the frontend:

- `Nextcloud:BaseUrl` -> relative `nc-api`
- `Nextcloud:ShareToken` -> public share token
- `Nextcloud:MetadataPath` -> `MetaData`

Share layout expectation:

- Share root (`Game`) contains ROM archives/folders.
- `MetaData/` under share root contains `consoles.json`, `manifest.json`, thumbnails, and other metadata files.

Docker renders `runtime-config.json` from `runtime-config.template.json` at startup
using these environment variables:

- `NEXTCLOUD_BASE_URL`
- `NEXTCLOUD_SHARE_TOKEN`
- `NEXTCLOUD_METADATA_PATH`

This keeps local Docker and production aligned on the same URL pattern:

- File read/download (DAV files endpoint): `GET <base>/public.php/dav/files/<token>/<path>`
- Directory listing (WebDAV): `PROPFIND <base>/public.php/dav/files/<token>/<path>/` with `Depth: 1`

Examples:

- List root (`Game`): `PROPFIND <base>/public.php/dav/files/<token>/`
- List metadata directory: `PROPFIND <base>/public.php/dav/files/<token>/MetaData/`
- Read consoles: `GET <base>/public.php/dav/files/<token>/MetaData/consoles.json`

For YunoHost production, ensure `__PATH__/nc-api/` in `yunohost-package/conf/nginx.conf`
proxies to `https://tools.kushkurriculum.org/nextcloud/`.

If that path-scoped proxy is not active yet, production can still work by setting
`NEXTCLOUD_BASE_URL=/nextcloud` so runtime-config points at the host-level Nextcloud path.

## Publish container image to GitHub Container Registry (GHCR)

This repository includes a GitHub Actions workflow at:

- `.github/workflows/docker-publish.yml`

It builds and pushes `ghcr.io/<owner>/<repo>:latest` on pushes to `main`.

### Required GitHub repository settings

1. Push this repository to GitHub.
2. In GitHub repository settings, ensure Actions are enabled.
3. Make sure the default branch is `main` (or adjust workflow trigger).

No extra secrets are required for GHCR push when using `${{ secrets.GITHUB_TOKEN }}`.

## YunoHost package scaffold

A YunoHost package-ready scaffold is included in:

- `yunohost-package/`

This is intended to be copied to a dedicated package repository (for example `assemulator_ynh`) and then validated with YunoHost packaging tools before catalog submission.

## Notes

- The app currently includes a Nextcloud proxy route in `nginx.conf` (`/nc-api/`).
- For production hosts, review upstream URLs and security headers to match your deployment.
