#!/usr/bin/env bash
# Cria/atualiza o realm "marketplace" e o client do app (idempotente).
# Uso: ssh server@192.168.0.200 'docker exec -i infra_keycloak bash -s' < setup-realm-marketplace.sh
# Usa KC_BOOTSTRAP_ADMIN_* do container; se a senha do admin foi trocada, passe KC_ADMIN_USER/KC_ADMIN_PASSWORD (docker exec -e ...). Google/Facebook: ver README (precisam de credenciais próprias).
set -euo pipefail
K=/opt/keycloak/bin/kcadm.sh
R=marketplace
CLIENT=marketplace-app
$K config credentials --server http://localhost:8080 --realm master \
  --user "${KC_ADMIN_USER:-$KC_BOOTSTRAP_ADMIN_USERNAME}" --password "${KC_ADMIN_PASSWORD:-$KC_BOOTSTRAP_ADMIN_PASSWORD}" >/dev/null

SETTINGS=(
  -s enabled=true -s displayName=Marketplace
  -s registrationAllowed=true -s registrationEmailAsUsername=true -s loginWithEmailAllowed=true
  -s duplicateEmailsAllowed=false -s resetPasswordAllowed=true -s rememberMe=true
  # Exige SMTP funcionando no realm (Realm settings > Email); sem ele o cadastro trava na verificação.
  -s verifyEmail=true
  -s loginTheme=marketplace
  -s internationalizationEnabled=true -s 'supportedLocales=["pt-BR","en"]' -s defaultLocale=pt-BR
  -s bruteForceProtected=true
  # Sessão: refresh token gira a cada uso (o app já serializa o refresh); ocioso 30 dias, máximo 90; access token 5 min.
  -s revokeRefreshToken=true -s refreshTokenMaxReuse=0
  -s accessTokenLifespan=300 -s ssoSessionIdleTimeout=2592000 -s ssoSessionMaxLifespan=7776000
  -s offlineSessionIdleTimeout=2592000
)
if $K get "realms/$R" >/dev/null 2>&1; then $K update "realms/$R" "${SETTINGS[@]}"; else $K create realms -s realm=$R "${SETTINGS[@]}"; fi

CLIENT_SETTINGS=(
  -s name=Marketplace -s enabled=true -s publicClient=true
  -s standardFlowEnabled=true -s directAccessGrantsEnabled=false -s implicitFlowEnabled=false -s serviceAccountsEnabled=false
  -s 'redirectUris=["marketplace://auth","marketplace:///auth"]'
  -s 'webOrigins=[]'
  -s 'attributes."pkce.code.challenge.method"=S256'
  -s 'attributes."post.logout.redirect.uris"=marketplace://auth##marketplace:///auth'
)
ID=$($K get clients -r $R -q clientId=$CLIENT --fields id --format csv --noquotes | head -1)
if [ -n "$ID" ]; then $K update "clients/$ID" -r $R "${CLIENT_SETTINGS[@]}"; else $K create clients -r $R -s clientId=$CLIENT "${CLIENT_SETTINGS[@]}"; fi
echo "ok: realm=$R client=$CLIENT"
