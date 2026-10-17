#!/bin/sh
set -eu
umask 077

CONTROLLER_PROXY="${CONTROLLER_PROXY:-controller:8080}"
CONTROLLER_AUTH_DIRECTIVE=""
TRUSTED_PROXY_DIRECTIVES=""

# Restrict access before injecting controller credentials.
if [ "${CONTROLLER_PASSWORD+x}" = x ]; then
    : "${CONTROLLER_PASSWORD:?Controller password must not be empty}"
    case "${TRUSTED_PROXY_MODE:-container}" in
        container)
            : "${TRUSTED_PROXY_HOST:?A trusted app-proxy hostname is required}"
            case "$TRUSTED_PROXY_HOST" in
                *[!a-zA-Z0-9_.-]*|'') echo 'Invalid trusted proxy hostname' >&2; exit 1 ;;
            esac
            ;;
        host) ;;
        *) echo 'Invalid trusted proxy mode' >&2; exit 1 ;;
    esac
    proxy_ip=""
    attempt=0
    while [ "$attempt" -lt 30 ]; do
        if [ "${TRUSTED_PROXY_MODE:-container}" = host ]; then
            proxy_ip=$(ip -4 route show default | awk '$1 == "default" && $2 == "via" {print $3; exit}') || true
        else
            proxy_ip=$(getent ahostsv4 "$TRUSTED_PROXY_HOST" | awk '$1 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ {print $1; exit}') || true
        fi
        [ -n "$proxy_ip" ] && break
        attempt=$((attempt + 1))
        sleep 1
    done
    # Accept only a literal IPv4 address.
    if ! printf '%s\n' "$proxy_ip" | awk -F. 'NF != 4 {exit 1} {for(i=1;i<=4;i++) if($i !~ /^[0-9]+$/ || $i > 255) exit 1}'; then
        echo 'Could not resolve trusted app proxy to IPv4' >&2
        exit 1
    fi
    TRUSTED_PROXY_DIRECTIVES="allow $proxy_ip; deny all;"
    controller_auth=$(printf 'grin:%s' "$CONTROLLER_PASSWORD" | base64 | tr -d '\n')
    CONTROLLER_AUTH_DIRECTIVE="proxy_set_header Authorization \"Basic $controller_auth\";"
fi

export CONTROLLER_PROXY CONTROLLER_AUTH_DIRECTIVE TRUSTED_PROXY_DIRECTIVES
envsubst '${CONTROLLER_PROXY} ${CONTROLLER_AUTH_DIRECTIVE} ${TRUSTED_PROXY_DIRECTIVES}' \
    < /etc/nginx/conf.d/default.conf.template \
    > /etc/nginx/conf.d/default.conf
chmod 600 /etc/nginx/conf.d/default.conf
unset CONTROLLER_PASSWORD controller_auth CONTROLLER_AUTH_DIRECTIVE TRUSTED_PROXY_DIRECTIVES
exec nginx -g 'daemon off;'
