#!/bin/bash
set -e

cp /etc/nginx/conf.d/default.conf.template /etc/nginx/conf.d/default.conf

cat /etc/nginx/conf.d/default.conf

nginx -g "daemon off;"
