# build the container image

```
docker buildx bake
```

# deploy

Configure the following environment variables:

**Required:**
- `APP_DOMAIN` - Domain name (e.g., qr.example.com)
- `IPV6_SUBNET` - IPv6 subnet for Docker network (e.g., 2001:db8:c::1:0/120)
- `IPV6_GATEWAY` - IPv6 gateway (e.g., 2001:db8:c::1:1)

**Optional:**
- `APP_NAME` - Service name (default: qr)
- `APP_CERT_VOLUME` - Docker volume for TLS certs (default: certs-$APP_NAME)
- `APP_IMAGE` / `DOCKER_IMAGE` - Image to deploy (default: local/qrencode/qrencode:latest)
- `IPV6_ADDRESS` - Specific IPv6 address (default: resolved from APP_DOMAIN AAAA record)
- `APP_DO_CERTBOT` - Run certbot to fetch certs (default: 0)
- `APP_CERTBOT_MAIL` - Email for Let's Encrypt (required if APP_DO_CERTBOT=1)
- `APP_CERTBOT_TAG` - Certbot image tag (default: latest)

**Deploy:**

```
bash deploy.sh
```

The script will:
1. Resolve APP_DOMAIN to IPv6 address
2. Create IPv6-only Docker network
3. Optionally run certbot for TLS certificates (if APP_DO_CERTBOT=1)
4. Build images with buildx bake
5. Start services with docker compose

**Notes:**
- IPv6-only deployment; DNS must resolve to AAAA record
- Firewall: allow port 80 only for certbot validation (HTTPS runs on 443)
- Container runs as nginx user, read-only filesystem, 32MB memory limit