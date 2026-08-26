# AGENTS.md

## Architecture
- Single-service QR code generator: nginx (IPv6-only) + Perl backend + static frontend
- Main app logic: `lib/perl/qr.pm` (nginx Perl module, handles `/qr` endpoint)
- Static site: `site/` (index.html, logo.png, favicon.ico)
- nginx config: `nginx.conf` (rate limiting, TLS, security headers, Perl integration)
- Container entrypoint: `nginx.sh`

## Build & Run
- Build image: `docker buildx bake`
- Local dev: `docker compose up -d` (image tag defaults to `local/qrencode/qrencode:latest`, container name includes `$LOGNAME`)
- Deploy: `bash deploy.sh`

## Deployment (IPv6-only)
- IPv6-only network; no IPv4 allowed. DNS must resolve to IPv6.
- `deploy.sh` requires: `APP_DOMAIN`, `IPV6_SUBNET`, `IPV6_GATEWAY`
- Optional: set `APP_DO_CERTBOT=1` and `APP_CERTBOT_MAIL` to fetch TLS certs via certbot
- Cert volume name: defaults to `certs-qr`, configurable via `APP_CERT_VOLUME`
- Image: defaults to `local/qrencode/qrencode:latest`, configurable via `DOCKER_IMAGE` or `APP_IMAGE`

## Release build
- `docker buildx bake -f docker-bake.hcl release` — pushes to `ghcr.io/registry/qrencode:<tag>`, multi-platform (linux/arm/v6, linux/amd64), includes SBOM and provenance.

## Key constraints
- No tests, lint, or CI configured.
- Container runs as `nginx` user, read-only filesystem, minimal capabilities (SETUID, SETGID, NET_BIND_SERVICE).
- Memory limit: 32m, CPU limit: 0.5.
- Temp files written to `/dev/shm` (shared memory).
- ImageMagick policy (`policy.xml`) restricts all operations to PNG only.
- nginx logs to stdout; Perl logger writes to stderr.
- `nginx.conf` has no header merging — `add_header` at server level, not inside `location` blocks.
