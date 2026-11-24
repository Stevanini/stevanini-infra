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
  -s loginTheme=marketplace -s emailTheme=marketplace
  # links dos e-mails/redirects saem com a URL pública, não com o IP do servidor
  -s 'attributes.frontendUrl=https://gateway.stevanini.com.br'
  -s internationalizationEnabled=true -s 'supportedLocales=["pt-BR","en"]' -s defaultLocale=pt-BR
  -s bruteForceProtected=true
  # Sessão: refresh token gira a cada uso (o app já serializa o refresh); ocioso 24h, máximo 24h; access token 1h.
  -s revokeRefreshToken=true -s refreshTokenMaxReuse=0
  -s accessTokenLifespan=3600 -s ssoSessionIdleTimeout=86400 -s ssoSessionMaxLifespan=86400
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

# Data de nascimento obrigatória no cadastro (User Profile do Keycloak 26) + mapper p/ o token do app.
if ! $K get users/profile -r $R | grep -q '"name" : "birthdate"'; then
  $K get users/profile -r $R > /tmp/up.json
  sed -i '0,/"attributes" : \[/s//"attributes" : [ {"name":"birthdate","displayName":"${birthdate}","required":{"roles":["user"]},"permissions":{"view":["admin","user"],"edit":["admin","user"]},"annotations":{"inputType":"html5-date"}},/' /tmp/up.json
  $K update users/profile -r $R -f /tmp/up.json
fi
ID=$($K get clients -r $R -q clientId=$CLIENT --fields id --format csv --noquotes | head -1)
$K get "clients/$ID/protocol-mappers/models" -r $R | grep -q '"name" : "birthdate"' || \
  $K create "clients/$ID/protocol-mappers/models" -r $R -s name=birthdate -s protocol=openid-connect -s protocolMapper=oidc-usermodel-attribute-mapper \
    -s 'config."user.attribute"=birthdate' -s 'config."claim.name"=birthdate' -s 'config."jsonType.label"=String' \
    -s 'config."id.token.claim"=true' -s 'config."access.token.claim"=true' -s 'config."userinfo.token.claim"=true'

# Client só p/ testes no Bruno (OAuth2 Authorization Code + PKCE); o de produção não ganha redirect público.
BRUNO_SETTINGS=(
  -s name="Marketplace (Bruno)" -s enabled=true -s publicClient=true
  -s standardFlowEnabled=true -s directAccessGrantsEnabled=false -s implicitFlowEnabled=false -s serviceAccountsEnabled=false
  -s 'redirectUris=["https://oauth.usebruno.com/callback","https://auth.usebruno.com/callback"]'
  -s 'webOrigins=[]'
  -s 'attributes."pkce.code.challenge.method"=S256'
)
BID=$($K get clients -r $R -q clientId=marketplace-bruno --fields id --format csv --noquotes | head -1)
if [ -n "$BID" ]; then $K update "clients/$BID" -r $R "${BRUNO_SETTINGS[@]}"; else $K create clients -r $R -s clientId=marketplace-bruno "${BRUNO_SETTINGS[@]}"; fi

# KC_FEATURES_DISABLED tem "organization", mas o fluxo browser do realm referencia o authenticator dele:
# o login falha ("Unable to find factory for AuthenticatorFactory: organization"). Desliga essa execução.
# (sem awk/jq no container: só grep/sed/bash; o alias do fluxo pode ter espaço, então vai com %20)
$K get authentication/flows -r $R | grep '"alias"' | sed -E 's/.*: "(.*)",?/\1/' | while read -r FLOW; do
  $K get "authentication/flows/${FLOW// /%20}/executions" -r $R 2>/dev/null | grep -E '"id" :|"providerId" : "organization"' \
    | grep -B1 organization | grep '"id"' | sed -E 's/.*: "(.*)",?/\1/' | while read -r EID; do
      $K update "authentication/flows/${FLOW// /%20}/executions" -r $R -b "{\"id\":\"$EID\",\"requirement\":\"DISABLED\"}" && echo "organization desativado em '$FLOW'"
    done || true
done
echo "ok: realm=$R client=$CLIENT"
