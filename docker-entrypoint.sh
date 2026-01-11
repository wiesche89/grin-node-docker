#!/bin/sh
set -eu

# Fallback auf den Default, falls nichts gesetzt ist
if [ -z "${CONTROLLER_PROXY:-}" ]; then
    CONTROLLER_PROXY="controller:8080"
fi

export CONTROLLER_PROXY

envsubst '${CONTROLLER_PROXY}' \
    < /etc/nginx/conf.d/default.conf.template \
    > /etc/nginx/conf.d/default.conf

exec nginx -g 'daemon off;'
