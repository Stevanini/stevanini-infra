#!/usr/bin/env bash
# Move o atributo birthdate p/ o fim do formulário de cadastro (a ordem do User Profile é a ordem da tela). Idempotente.
# Uso: ./mover-birthdate-fim.sh   (lê KC_ADMIN_USER/KC_ADMIN_PASSWORD do .env desta pasta ou do ambiente)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
[ -f "$HERE/.env" ] && { set -a; . "$HERE/.env"; set +a; }
SERVER="${SERVER:-server@192.168.0.200}"
: "${KC_ADMIN_USER:?}" "${KC_ADMIN_PASSWORD:?}"
K='/opt/keycloak/bin/kcadm.sh'
LOGIN="$K config credentials --server http://localhost:8080 --realm master --user '$KC_ADMIN_USER' --password '$KC_ADMIN_PASSWORD' >/dev/null 2>&1"
kc() { ssh "$SERVER" "docker exec -i infra_keycloak bash -c \"$LOGIN; $1\""; }
kc "$K get users/profile -r marketplace" </dev/null | python3 -c '
import json,sys
p=json.load(sys.stdin); a=p["attributes"]
p["attributes"]=[x for x in a if x["name"]!="birthdate"]+[x for x in a if x["name"]=="birthdate"]
print(json.dumps(p))' | kc "$K update users/profile -r marketplace -f -"
echo "ok: birthdate no fim"
