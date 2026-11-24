#!/usr/bin/env bash
# Remove do realm "marketplace" o que o app não usa (idempotente). O app só usa: OIDC + PKCE (marketplace-app),
# Admin API (marketplace-backend), cadastro, verificação de e-mail, reset de senha, Google/Facebook.
# Uso: ssh server@192.168.0.200 "docker exec -i -e KC_ADMIN_PASSWORD='SENHA' infra_keycloak bash -s" < limpar-realm-marketplace.sh
set -uo pipefail
K=/opt/keycloak/bin/kcadm.sh; R=marketplace
$K config credentials --server http://localhost:8080 --realm master \
  --user "${KC_ADMIN_USER:-$KC_BOOTSTRAP_ADMIN_USERNAME}" --password "${KC_ADMIN_PASSWORD:-$KC_BOOTSTRAP_ADMIN_PASSWORD}" >/dev/null || exit 1

echo "== antes =="
$K get clients -r $R --fields clientId --format csv --noquotes | sed 's/^/client: /'
$K get client-scopes -r $R --fields name --format csv --noquotes | sed 's/^/scope: /'

# clients: console da conta/admin do realm não são usados (admin do Keycloak fica no realm master)
for c in account account-console admin-cli security-admin-console; do
  id=$($K get clients -r $R -q clientId=$c --fields id --format csv --noquotes | head -1)
  [ -z "$id" ] && continue
  # clients embutidos não aceitam delete: nesse caso só desativa
  if $K delete "clients/$id" -r $R 2>/dev/null; then echo "client removido: $c"; else $K update "clients/$id" -r $R -s enabled=false && echo "client desativado: $c"; fi
done
# client scopes sem uso (telefone/endereço/SAML/organizações/microprofile)
for s in phone address microprofile-jwt role_list saml_organization organization; do
  id=$($K get client-scopes -r $R --fields id,name --format csv --noquotes | grep ",$s\$" | cut -d, -f1 | head -1)
  [ -n "$id" ] && $K delete "client-scopes/$id" -r $R && echo "scope removido: $s"
done
# required actions que não existem no app
for a in webauthn-register webauthn-register-passwordless CONFIGURE_RECOVERY_AUTHN_CODES delete_account delete_credential TERMS_AND_CONDITIONS CONFIGURE_TOTP UPDATE_EMAIL; do
  $K update "authentication/required-actions/$a" -r $R -s enabled=false -s defaultAction=false >/dev/null 2>&1 && echo "required action off: $a"
done
# eventos: só erros de login, guardados 30 dias; sem eventos de admin
$K update "realms/$R" -s eventsEnabled=true -s 'enabledEventTypes=["LOGIN_ERROR","REGISTER_ERROR","SEND_VERIFY_EMAIL_ERROR","SEND_RESET_PASSWORD_ERROR"]' \
  -s eventsExpiration=2592000 -s adminEventsEnabled=false -s adminEventsDetailsEnabled=false
echo "== depois =="
$K get clients -r $R --fields clientId --format csv --noquotes | sed 's/^/client: /'
$K get client-scopes -r $R --fields name --format csv --noquotes | sed 's/^/scope: /'
