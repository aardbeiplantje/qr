# build the container image

```
docker buildx bake
```

# deploy the stack

1. Create a network for the stack:
```
Add the ip to the DOCKER ip6tables chain as ACCEPT:
```
ip6tables -I DOCKER -s ::/0 -d fd53:5729:c558:8d8f::/64 -p tcp --dport 443 -j ACCEPT

After finding the IP of the container, add a proxy neighbor:
```
ip -6 neigh add proxy fd53:5729:c558:8d8f:a::5 dev eno1
```

2. open port 80 to the host:

This is done on a firewall.

3. get the tls cert

```
export QRENCODE_DOMAIN=qrencode.example.com
export CERTBOT_MAIL=me@example.com
docker run \
    -p 80:80 \
    --rm \
    -e CERTBOT_MAIL \
    -v qrencode-https-cert:/certs:rw\
    ghcr.io/myrepo/certbot/certbot:latest \
        certonly \
            --agree-tos \
            --domains QRENCODE_DOMAIN
```

4. deploy the stack

```
bash deploy.sh
```
