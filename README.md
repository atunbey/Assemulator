# Assemulator

Assemulator is a Blazor WebAssembly retro gaming frontend served as static files via Nginx.

## Local run with Docker

```bash
docker compose up -d --build
```

App URL:

- http://localhost:8088

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
