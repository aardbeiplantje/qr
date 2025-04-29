#!/bin/bash 
export WORKSPACE=${WORKSPACE:-${BASH_SOURCE%/*}}
export APP_NAME=${APP_NAME:-qrencode}
export QRENCODE_DOMAIN=${QRENCODE_DOMAIN?Need to set QRENCODE_DOMAIN}

echo "checking for registry auth"
if [   ! -z "$DOCKER_REGISTRY" \
    -a ! -z "$DOCKER_REGISTRY_USER" \
    -a ! -z "$DOCKER_REGISTRY_PASS" ]; then
    echo "login on the registry"
    export DOCKER_REGISTRY_PASS DOCKER_REGISTRY_USER DOCKER_REGISTRY
    printenv DOCKER_REGISTRY_PASS \
        |docker login -u $DOCKER_REGISTRY_USER $DOCKER_REGISTRY --password-stdin
else
    echo "no registry login"
    export DOCKER_REGISTRY=${DOCKER_REGISTRY:-local}
    export DOCKER_REPOSITORY=${DOCKER_REPOSITORY:-qrencode}
fi
export DOCKER_REPOSITORY=${DOCKER_REPOSITORY:-qrencode}
export DOCKER_REGISTRY

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

    echo "running sysctl for proxy_ndp and add $IPV6 as neighbour"
    sudo ip -6 neigh add proxy $IPV6 dev eno1
    sudo sysctl net.ipv6.conf.eno1.proxy_ndp=1
else
    echo "no network"
    IPV6=$(dig -6 $QRENCODE_DOMAIN -t AAAA +short)
fi

if [ "${DO_CERTBOT:-0}" -eq 1 ]; then
    echo "check the certtificate"
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
    -p 443:443 \
    --rm \
    -d \
    --network $nw_name \
    --ip6 $IPV6 \
    --shm-size=4m \
    --name $APP_NAME \
    $extra_volume \
    -v ${QRENCODE_CERT_VOLUME}:/certs:ro \
    local/qrencode/qrencode
