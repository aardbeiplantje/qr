#!/bin/bash 
WORKSPACE=${WORKSPACE:-${BASH_SOURCE%/*}}
APP_NAME=${APP_NAME:-qrencode}
QRENCODE_DOMAIN=${QRENCODE_DOMAIN?Need to set QRENCODE_DOMAIN}

echo "checking for registry auth"
if [   ! -z "$DOCKER_REGISTRY" \
    -a ! -z "$DOCKER_REGISTRY_USER" \
    -a ! -z "$DOCKER_REGISTRY_PASS" ]; then
    echo "login on the registry"
    export DOCKER_REGISTRY_PASS
    printenv DOCKER_REGISTRY_PASS \
        |docker login -u $DOCKER_REGISTRY_USER $DOCKER_REGISTRY --password-stdin
    unset DOCKER_REGISTRY_PASS
else
    echo "no registry login"
fi

QRENCODE_CERT_VOLUME=${QRENCODE_CERT_VOLUME:-qrencode-https-cert}

echo "stopping $APP_NAME"
docker stop $APP_NAME 2>/dev/null 1>&2

nw_name=dmz-ipv6-$APP_NAME
if [ "${DO_NETWORK:-0}" -eq 1 ]; then
    echo "checking for docker network"
    IPV6_PREFIX_DEFAULT=$(ip -6 r l dev eno1 proto kernel metric 100|awk -F/ '{print $1}')
    IPV6_PREFIX_DEFAULT=${IPV6_PREFIX_DEFAULT%::*}:c::/112
    IPV6_PREFIX=${IPV6_PREFIX:-${IPV6_PREFIX_DEFAULT}}
    docker network rm $nw_name
    docker network create \
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
        --ipam-driver default
    IPV6=$(dig -6 $QRENCODE_DOMAIN -t AAAA +short)
    if [ $? ]; then
	echo -ne "problem looking up $QRENCODE_DOMAIN:\n$IPV6\n"
	exit 1
    fi

    echo "running sysctl for proxy_ndp and add $IPV6 as neighbour"
    sudo ip -6 neigh add proxy $IPV6 dev eno1
    sudo sysctl net.ipv6.conf.eno1.proxy_ndp=1
    sudo sysctl net.ipv6.conf.default.proxy_ndp=1
    sudo sysctl net.ipv6.conf.all.proxy_ndp=1
else
    echo "no network"
    IPV6=$(dig -6 $QRENCODE_DOMAIN -t AAAA +short)
    if [ $? ]; then
	echo -ne "problem looking up $QRENCODE_DOMAIN:\n$IPV6\n"
	exit 1
    fi
fi

if [ "${DO_CERTBOT:-0}" -eq 1 ]; then
    echo "check the certtificate"
    # work via export ENV, as this is a possible secret, and we dont want to
    # show this in a ps or log
    export CERTBOT_MAIL=${CERTBOT_MAIL?Need to set CERTBOT_MAIL}
    docker run \
        -p 80:80 \
        --rm \
        -e CERTBOT_MAIL \
        --network $nw_name \
        --ip6 $IPV6 \
        --name certbot_$APP_NAME \
        -v ${QRENCODE_CERT_VOLUME}:/certs:rw\
        local/certbot/certbot:latest \
            certonly \
                --agree-tos \
                --force-renewal \
                --domains "$QRENCODE_DOMAIN"
else
    echo "no certbot"
fi

if [ -d ${WORKSPACE}/site ]; then
    echo "stopping $APP_NAME and restarting development mode"
    extra_volume="-v ${WORKSPACE}/site:/app/site:ro"
else
    echo "stopping $APP_NAME and restarting"
fi
docker run \
    --rm \
    -d \
    --network $nw_name \
    --read-only \
    --shm-size=4m \
    --security-opt=no-new-privileges \
    --tmpfs /tmp:rw,noexec,nosuid,nodev,mode=1777,size=4k \
    --tmpfs /run:rw,noexec,nosuid,nodev,mode=1777,size=4k \
    --tmpfs /var/log/nginx:rw,noexec,nosuid,nodev,mode=1777,size=4k \
    --cap-drop=ALL \
    --cap-add=NET_BIND_SERVICE \
    --memory="32m" \
    --cpus="0.5" \
    --name $APP_NAME \
    -p 443:443 \
    --ip6 $IPV6 \
    $extra_volume \
    -v ${QRENCODE_CERT_VOLUME}:/certs:ro \
    local/qrencode/qrencode
