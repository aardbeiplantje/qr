#!/bin/bash 

export APP_NAME=${APP_NAME?Need APP_NAME}
export DOMAIN=${APP_DOMAIN?Need APP_DOMAIN}
export CERT_VOLUME=${APP_CERT_VOLUME:-certs-$APP_NAME}
export APP_IMAGE=${APP_IMAGE:-local/qrencode/qrencode:latest}
export DOCKER_IMAGE=${DOCKER_IMAGE:-local/qrencode/qrencode:latest}

WORKSPACE=$(readlink -f "${WORKSPACE:-${BASH_SOURCE%/*}}")
WORKSPACE=${WORKSPACE%/*}
export WORKSPACE
cd $WORKSPACE || exit $?

echo "using: $APP_NAME"

IPV6=$(dig -6 $DOMAIN -t AAAA +short +retry=0 +tries=1)
if [ $? != 0 -o -z "$IPV6" ]; then
    echo -ne "problem looking up $DOMAIN:\n$IPV6\n"
    exit 1
fi

export IPV6_SUBNET=${IPV6_SUBNET?Need IPV6_SUBNET (e.g. 2001:db8:c::1:0/120)}
export IPV6_GATEWAY=${IPV6_GATEWAY?Need IPV6_GATEWAY (e.g. 2001:db8:c::1:1)}
export IPV6_ADDRESS=${IPV6_ADDRESS:-$IPV6}

nw_name=dmz-ipv6-${APP_NAME}

if [ "${APP_DO_CERTBOT:-0}" -eq 1 ]; then
    echo "checking for certificate"
    echo "running certbot"
    export APP_CERTBOT_MAIL=${APP_CERTBOT_MAIL?Need APP_CERTBOT_MAIL}
    docker run \
        -p 80:80 \
        --pull=always \
        --rm \
        -e CERTBOT_MAIL="$APP_CERTBOT_MAIL" \
        --network $nw_name \
        --ip6 $IPV6 \
        --name certbot_$APP_NAME \
        -v ${CERT_VOLUME}:/certs:rw \
        ghcr.io/aardbeiplantje/certbot/certbot:${APP_CERTBOT_TAG:-latest} \
            certonly \
                --agree-tos \
                --force-renewal \
                --domains "$DOMAIN" || exit $?
else
    echo "no certbot"
fi

echo "building images with buildx bake"
docker buildx bake -f docker-bake.hcl local || exit $?

echo "starting with docker compose"
APP_NAME=$APP_NAME \
CERT_VOLUME=$CERT_VOLUME \
DOCKER_IMAGE=$DOCKER_IMAGE \
IPV6_SUBNET=$IPV6_SUBNET \
IPV6_GATEWAY=$IPV6_GATEWAY \
IPV6_ADDRESS=$IPV6_ADDRESS \
exec docker compose up -d
