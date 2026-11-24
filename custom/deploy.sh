#!/usr/bin/env bash
# Publica as customizações Stevanini (login igual nos 4 apps) no servidor.
# Uso: ./deploy.sh [keycloak|paperless|stirling|immich|all]   (padrão: all)
# Edite os arquivos desta pasta e rode de novo; cada app é reiniciado só se for publicado.
set -euo pipefail
SERVER="${SERVER:-server@192.168.0.200}"
HERE="$(cd "$(dirname "$0")" && pwd)"
FONT="$HERE/shared/GoogleSans.ttf"
what="${1:-all}"
want() { [ "$what" = all ] || [ "$what" = "$1" ]; }

if want keycloak; then
  echo "==> keycloak"
  rsync -a --delete "$HERE/keycloak/themes/stevanini/" "$SERVER:infra/themes/stevanini/"
  ssh "$SERVER" 'mkdir -p ~/infra/themes/stevanini/login/resources/fonts'
  scp -q "$FONT" "$SERVER:infra/themes/stevanini/login/resources/fonts/GoogleSans.ttf"
  # o Keycloak cacheia o tema: reiniciar. Se mudar o CSS, troque o nome do arquivo (stevanini-auth-N.css)
  # e o valor de "styles=" em theme.properties, senão o navegador mantém a versão antiga.
  rsync -a --delete "$HERE/keycloak/themes/marketplace/" "$SERVER:infra/themes/marketplace/"
  ssh "$SERVER" 'docker restart infra_keycloak >/dev/null'
fi
if want paperless; then
  echo "==> paperless"
  rsync -a "$HERE/paperless/" "$SERVER:workspace/paperless/stevanini/" --exclude docker-compose.diff
  scp -q "$FONT" "$SERVER:workspace/paperless/stevanini/GoogleSans.ttf"
  ssh "$SERVER" 'docker restart paperless-brand >/dev/null'   # troque ?v=N do CSS no nginx.conf p/ furar cache
fi
if want stirling; then
  echo "==> stirling-pdf"
  rsync -a "$HERE/stirling-pdf/" "$SERVER:workspace/stirling-pdf/stevanini/" --exclude docker-compose.diff
  scp -q "$FONT" "$SERVER:workspace/stirling-pdf/stevanini/GoogleSans.ttf"
  ssh "$SERVER" 'docker restart stirling-brand >/dev/null'
fi
if want immich; then
  echo "==> immich"
  rsync -a "$HERE/immich/" "$SERVER:workspace/immich/stevanini/" --exclude docker-compose.diff
  scp -q "$FONT" "$SERVER:workspace/immich/stevanini/GoogleSans.ttf"
  ssh "$SERVER" 'docker restart immich-server >/dev/null'    # o patch.js reaplica a marca a cada start
fi
echo "ok"
