FROM alpine:3 AS runtime
RUN apk add --no-cache \
    nginx \
    nginx-mod-http-auth-jwt \
    nginx-mod-http-headers-more \
    nginx-mod-http-lua \
    nginx-mod-http-perl \
    perl-uri \
    perl-json \
    perl-json-xs
RUN apk add --no-cache libqrencode-tools
RUN qrencode --version
RUN apk add --no-cache imagemagick
RUN convert --version
RUN apk add -U libcap netcat-openbsd
COPY ./nginx.conf /etc/nginx/nginx.conf
COPY ./nginx.sh /nginx.sh
COPY site/ /app/site/
COPY lib/ /app/lib/
COPY policy.xml /etc/ImageMagick-7/policy.xml
RUN ln -s /certs/ /etc/nginx/certs
RUN <<EOngxtest
    export PERL5LIB=/usr/lib/perl5/vendor_perl/x86_64-linux-thread-multi
    export TZ=GMT
    nginx -t -c /etc/nginx/nginx.conf
    err=$?
    exit $err
EOngxtest
RUN mkdir -p /var/lib/nginx/logs/ && chown -R nginx:nginx /var/lib/nginx/logs/
RUN mkdir -p /run/nginx/ && chown -R nginx:nginx /run/nginx/
RUN find /bin -type l -exec rm {} +
USER nginx
ENTRYPOINT ["/nginx.sh"]
