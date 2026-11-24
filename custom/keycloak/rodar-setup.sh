#!/usr/bin/env bash
# Roda o setup-realm-marketplace.sh no servidor usando KC_ADMIN_USER/KC_ADMIN_PASSWORD do .env desta pasta.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
[ -f "$HERE/.env" ] && { set -a; . "$HERE/.env"; set +a; }
: "${KC_ADMIN_USER:?preencha no .env}" "${KC_ADMIN_PASSWORD:?preencha no .env}"
ssh "${SERVER:-server@192.168.0.200}" "docker exec -i -e KC_ADMIN_USER='$KC_ADMIN_USER' -e KC_ADMIN_PASSWORD='$KC_ADMIN_PASSWORD' infra_keycloak bash -s" < "$HERE/setup-realm-marketplace.sh"
