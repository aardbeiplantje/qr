#!/bin/bash 
WORKSPACE=${WORKSPACE:-${BASH_SOURCE%/*}}
APP_NAME=${APP_NAME?Need APP_NAME}
APP_IMAGE=${APP_IMAGE?Need APP_IMAGE}
DOMAIN=${APP_DOMAIN?Need APP_DOMAIN}
CERT_VOLUME=${APP_CERT_VOLUME?Need APP_CERT_VOLUME}
CERTBOT_MAIL=${CERTBOT_MAIL?Need CERTBOT_MAIL}
export CERTBOT_MAIL
docker_cmd=${DOCKER_CMD:-docker}

echo "checking for registry auth"
if [   ! -z "$DOCKER_REGISTRY" \
    -a ! -z "$DOCKER_REGISTRY_USER" \
    -a ! -z "$DOCKER_REGISTRY_PASS" ]; then
    echo "login on the registry"
    export DOCKER_REGISTRY_PASS
    printenv DOCKER_REGISTRY_PASS \
        |$docker_cmd login -u $DOCKER_REGISTRY_USER $DOCKER_REGISTRY --password-stdin
    unset DOCKER_REGISTRY_PASS
else
    echo "no registry login"
fi

echo "stopping $APP_NAME"
$docker_cmd stop $APP_NAME 2>/dev/null 1>&2

nw_name=dmz-ipv6-$APP_NAME
if [ "${DO_NETWORK:-0}" -eq 1 ]; then
    IF_NAME=${IF_NAME:-eno1}
    echo "checking for docker network, using $IF_NAME"
    IPV6_PREFIX_DEFAULT=$(ip -json -6 a l dev wlan1 scope global |jq -r '.[0].addr_info[0].local')
    IPV6_PREFIX_DEFAULT=${IPV6_PREFIX_DEFAULT%::*}:c::/112
    IPV6_PREFIX=${IPV6_PREFIX:-${IPV6_PREFIX_DEFAULT}}
    $docker_cmd network rm $nw_name
    $docker_cmd network create \
        --ipv6 $nw_name \
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
        --ipam-driver default || exit $?
    IPV6=$(dig -6 $DOMAIN -t AAAA +short +retry=0 +tries=1)
    if [ $? != 0 -o -z "$IPV6" ]; then
        echo -ne "problem looking up $DOMAIN:\n$IPV6\n"
        exit 1
    fi

    echo "running sysctl for proxy_ndp and add $IPV6 as neighbour"
    sudo ip -6 neigh add proxy $IPV6 dev $IF_NAME
    sudo sysctl net.ipv6.conf.default.proxy_ndp=1
    sudo sysctl net.ipv6.conf.all.proxy_ndp=1
else
    echo "no network"
    IPV6=$(dig -6 $DOMAIN -t AAAA +short +retry=0 +tries=1)
    if [ $? != 0 -o -z "$IPV6" ]; then
        echo -ne "problem looking up $DOMAIN:\n$IPV6\n"
        exit 1
    fi
fi

if [ "${DO_CERTBOT:-0}" -eq 1 ]; then
    echo "check the certtificate"
    # work via export ENV, as this is a possible secret, and we dont want to
    # show this in a ps or log
    $docker_cmd run \
        -p 80:80 \
        --pull=always \
        --rm \
        -e CERTBOT_MAIL="$CERTBOT_MAIL" \
        --network $nw_name \
        --ip6 $IPV6 \
        --name certbot_$APP_NAME \
        -v ${CERT_VOLUME}:/certs:rw \
        ghcr.io/aardbeiplantje/certbot/certbot:latest \
            certonly \
                --agree-tos \
                --force-renewal \
                --domains "$DOMAIN" || exit $?
else
    echo "no certbot"
fi

if [ -d ${WORKSPACE}/site ]; then
    echo "stopping $APP_NAME and restarting development mode"
    extra_volume="-v ${WORKSPACE}/site:/app/site:ro"
else
    echo "stopping $APP_NAME and restarting"
fi
$docker_cmd run \
    -p 443:443 \
    --pull=always \
    --rm \
    -d \
    --network $nw_name \
    --ip6 $IPV6 \
    --read-only \
    --shm-size=4m \
    --security-opt=no-new-privileges \
    --tmpfs /tmp:rw,noexec,nosuid,nodev,mode=1777,size=4k \
    --tmpfs /run:rw,noexec,nosuid,nodev,mode=1777,size=4k \
    --tmpfs /var/log/nginx:rw,noexec,nosuid,nodev,mode=1777,size=4k \
    --cap-drop=ALL \
    --cap-add=NET_BIND_SERVICE \
    --memory="32m" \
    --memory-swap=0 \
    --cpus="0.5" \
    --name $APP_NAME \
    $extra_volume \
    -v ${CERT_VOLUME}:/certs:ro \
    "${APP_IMAGE}"
