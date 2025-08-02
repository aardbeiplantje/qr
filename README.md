# build the container image

```
docker buildx bake
```

# deploy

* open port 80 to the host:

This is done on a firewall. This is only needed for letsencrypt to verify the
DNS entry, we will be running HTTPS only on port 443.

* make the ipv6 network

```
IPV6_PREFIX=$(ip -6 r l dev eno1 proto kernel metric 100|awk -F/ '{print $1}')
IPV6_PREFIX=${IPV6_PREFIX%::*}:c::/112
docker network rm dmz-ipv6-qrencode
docker network create \
    --ipv6 dmz-ipv6-qrencode \
    --subnet=$IPV6_PREFIX \
    --ipv4=false \
    --attachable=true \
    --scope=local \
    --driver=bridge \
    -o com.docker.network.bridge.name=dlocal-dmz0 \
    -o com.docker.network.container_iface_prefix=dmz \
    -o com.docker.network.bridge.gateway_mode_ipv6=routed \
    -o com.docker.network.bridge.enable_icc=true \
    -o com.docker.network.bridge.enable_ip_masquerade=false \
    -o com.docker.network.bridge.enable_ip6_masquerade=false \
    -o com.docker.network.enable_ipv6=true \
    -o com.docker.network.bridge.inhibit_ipv4=true \
    -o com.docker.network.driver.mtu=1500 \
    --ipam-driver default
```

* add the ipv6 neighbor to the host:

```
IFACE=eno1
QRENCODE_DOMAIN=qrencode.example.com
IPV6=$(dig -6 $QRENCODE_DOMAIN -t AAAA +short)
sudo ip -6 neigh add proxy $IPV6 dev $IFACE
sudo sysctl net.ipv6.conf.$IFACE.proxy_ndp=1
```

* get the tls cert

```
QRENCODE_DOMAIN=qrencode.example.com
IPV6=$(dig -6 $QRENCODE_DOMAIN -t AAAA +short)
CERTBOT_MAIL=me@example.com
docker run \
    -p 80:80 \
    --rm \
    -e CERTBOT_MAIL="$CERTBOT_MAIL" \
    --network dmz-ipv6-qrencode \
    --ip6 $IPV6 \
    -v qrencode-https-cert:/certs:rw\
    local/certbot/certbot:latest \
        certonly \
            --agree-tos \
            --domains "$QRENCODE_DOMAIN"
```

* deploy the service

```
bash deploy.sh
```
