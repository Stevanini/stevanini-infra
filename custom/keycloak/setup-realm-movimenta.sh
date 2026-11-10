#!/usr/bin/env bash
# Cria/atualiza o realm "movimenta" e o client do app (idempotente).
# Uso: ssh server@192.168.0.200 'docker exec -i infra_keycloak bash -s' < setup-realm-movimenta.sh
# Usa KC_BOOTSTRAP_ADMIN_* do container; se a senha do admin foi trocada, passe KC_ADMIN_USER/KC_ADMIN_PASSWORD (docker exec -e ...). Google/Facebook: ver README (precisam de credenciais próprias).
set -euo pipefail
K=/opt/keycloak/bin/kcadm.sh
R=movimenta
CLIENT=movimenta-app
$K config credentials --server http://localhost:8080 --realm master \
  --user "${KC_ADMIN_USER:-$KC_BOOTSTRAP_ADMIN_USERNAME}" --password "${KC_ADMIN_PASSWORD:-$KC_BOOTSTRAP_ADMIN_PASSWORD}" >/dev/null

SETTINGS=(
  -s enabled=true -s displayName=Movimenta
  -s registrationAllowed=true -s registrationEmailAsUsername=true -s loginWithEmailAllowed=true
  -s duplicateEmailsAllowed=false -s resetPasswordAllowed=true -s rememberMe=true
  # shortcut: sem SMTP configurado não dá para verificar e-mail; ligue verifyEmail=true depois de configurar o SMTP do realm.
  -s verifyEmail=false
  -s loginTheme=stevanini
  -s internationalizationEnabled=true -s 'supportedLocales=["pt-BR","en"]' -s defaultLocale=pt-BR
  -s bruteForceProtected=true
)
if $K get "realms/$R" >/dev/null 2>&1; then $K update "realms/$R" "${SETTINGS[@]}"; else $K create realms -s realm=$R "${SETTINGS[@]}"; fi

CLIENT_SETTINGS=(
  -s name=Movimenta -s enabled=true -s publicClient=true
  -s standardFlowEnabled=true -s directAccessGrantsEnabled=false -s implicitFlowEnabled=false -s serviceAccountsEnabled=false
  -s 'redirectUris=["marketplace://*","br.com.stevanini.marketplace://*","https://giro.stevanini.com.br/*"]'
  -s 'webOrigins=["+"]'
  -s 'attributes."pkce.code.challenge.method"=S256'
  -s 'attributes."post.logout.redirect.uris"=marketplace://*##https://giro.stevanini.com.br/*'
)
ID=$($K get clients -r $R -q clientId=$CLIENT --fields id --format csv --noquotes | head -1)
if [ -n "$ID" ]; then $K update "clients/$ID" -r $R "${CLIENT_SETTINGS[@]}"; else $K create clients -r $R -s clientId=$CLIENT "${CLIENT_SETTINGS[@]}"; fi
echo "ok: realm=$R client=$CLIENT"
