FROM alpine:latest AS runtime
RUN apk add --no-cache nginx nginx-mod-http-auth-jwt nginx-mod-http-headers-more nginx-mod-http-lua
RUN apk add --no-cache libqrencode-tools
COPY ./nginx.conf /etc/nginx/nginx.conf
COPY ./nginx.sh /nginx.sh
RUN ln -s /certs/ /etc/nginx/certs
RUN \
    mkdir -p /etc/nginx/certs; \
    nginx -t -c /etc/nginx/nginx.conf
RUN qrencode --version
ENTRYPOINT ["/nginx.sh"]
