#!/usr/bin/env bash
# Pós-instalação do Keycloak: troca o admin temporário (bootstrap) pelo admin permanente. Rode UMA vez.
# Uso: ssh server@192.168.0.200 'docker exec -i -e NEW_ADMIN=<usuario> infra_keycloak bash -s' < postinstall.sh
# Antes: crie o admin permanente no console (realm master, role "admin"). Aqui autentica com o bootstrap
# (que ainda existe) para: conferir o novo admin, exigir TOTP no próximo login dele e apagar o bootstrap.
# Depois disso o setup-realm-marketplace.sh não loga mais com KC_BOOTSTRAP_ADMIN_*: passe KC_ADMIN_USER/KC_ADMIN_PASSWORD
# de um usuário de serviço (sem TOTP) com permissão no realm marketplace.
set -euo pipefail
K=/opt/keycloak/bin/kcadm.sh
OLD="${KC_BOOTSTRAP_ADMIN_USERNAME:-}"
NEW="${NEW_ADMIN:?defina NEW_ADMIN (docker exec -e NEW_ADMIN=...)}"
[ -n "$OLD" ] || { echo "sem KC_BOOTSTRAP_ADMIN_USERNAME no container: bootstrap já removido do compose?"; exit 1; }
[ "$NEW" != "$OLD" ] || { echo "NEW_ADMIN não pode ser o próprio usuário de bootstrap ($OLD)"; exit 1; }

if ! $K config credentials --server http://localhost:8080 --realm master --user "$OLD" --password "$KC_BOOTSTRAP_ADMIN_PASSWORD" >/dev/null 2>&1; then
  echo "ok: o admin de bootstrap '$OLD' não loga mais (já foi apagado). Nada a fazer."; exit 0
fi

uid() { $K get users -r master -q "username=$1" -q exact=true --fields id --format csv --noquotes | head -1; }
NEW_ID=$(uid "$NEW")
[ -n "$NEW_ID" ] || { echo "erro: usuário '$NEW' não existe no realm master. Crie antes."; exit 1; }
$K get-roles -r master --uusername "$NEW" --effective --fields name --format csv --noquotes | grep -qx admin \
  || { echo "erro: '$NEW' não tem a role admin. Nada foi apagado."; exit 1; }

if $K get "users/$NEW_ID/credentials" -r master --fields type --format csv --noquotes | grep -qx otp; then
  echo "MFA: '$NEW' já tem TOTP."
else
  $K update "users/$NEW_ID" -r master -s 'requiredActions=["CONFIGURE_TOTP"]'
  echo "MFA: '$NEW' vai configurar o TOTP no próximo login."
fi

OLD_ID=$(uid "$OLD")
[ -z "$OLD_ID" ] || $K delete "users/$OLD_ID" -r master
echo "ok: bootstrap '$OLD' removido; admin permanente = $NEW"
