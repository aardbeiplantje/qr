#!/bin/bash 
export WORKSPACE=${WORKSPACE:-${BASH_SOURCE%/*}}
export APP_NAME=${APP_NAME:-qrencode}
export STACK_NAME=${STACK_NAME:-$APP_NAME}

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

echo "clean up $STACK_NAME"
docker stack rm $STACK_NAME 2>/dev/null

nw_name=dmz-$STACK_NAME
if_name=${BRIDGE_IF_NAME:-${nw_name}0}
ipv6_prefix=${IPV6_PREFIX?Need IPV6_PREFIX}
echo "network name: $nw_name if_name: $if_name ipv6_prefix: $ipv6_prefix"
docker network rm $nw_name 2>/dev/null
sleep 5
docker network create \
    $nw_name \
    --ipv6=true \
    --ipv4=true \
    --attachable \
    --scope=swarm \
    --subnet=$ipv6_prefix \
    --driver=bridge \
    -o com.docker.network.bridge.name=$if_name \
    -o com.docker.network.container_iface_prefix=dmz \
    -o com.docker.network.bridge.gateway_mode_ipv6=routed \
    -o com.docker.network.bridge.enable_icc=true \
    -o com.docker.network.bridge.enable_ip_masquerade=false \
    -o com.docker.network.bridge.enable_ip6_masquerade=false \
    -o com.docker.network.bridge.host_binding_ipv4=:: \
    -o com.docker.network.enable_ipv6=true \
    -o com.docker.network.bridge.inhibit_ipv4=true \
    -o com.docker.network.driver.mtu=1500 \
    --ipam-driver default || exit $?

echo "stack deploy $STACK_NAME"
docker stack deploy \
    -c $WORKSPACE/qrencode.yml \
    --with-registry-auth \
    --detach=false \
    $STACK_NAME
