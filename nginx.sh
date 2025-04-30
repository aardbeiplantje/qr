#!/bin/busybox sh
exec /usr/sbin/nginx -c /etc/nginx/nginx.conf -g 'daemon off;'
