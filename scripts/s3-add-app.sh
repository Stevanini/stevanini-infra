#!/usr/bin/env bash
# Cria (ou rotaciona) a access key de UM app no SeaweedFS, com acesso só ao bucket dele.
#
# Uso (na pasta da infra, onde está o .env): bash s3-add-app.sh <app> [bucket]
#   bucket padrão = nome do app. Rodar de novo para o mesmo app gera chaves novas.
#
# As identidades ficam no filer do SeaweedFS (aplicadas na hora, sem reiniciar).
# A chave admin do .env (S3_ACCESS_KEY/S3_SECRET_KEY) é registrada junto, para
# continuar valendo depois que existir qualquer outra identidade.
# INFRA_PREFIX (padrão: infra) precisa ser o mesmo usado no install-infra.sh.

set -euo pipefail

APP="${1:-}"
BUCKET="${2:-$APP}"
[ -n "$APP" ] || { echo "Uso: $0 <app> [bucket]" >&2; exit 1; }
[[ "$APP" =~ ^[a-z0-9][a-z0-9_-]*$ ]] || { echo "Erro: nome do app só aceita a-z, 0-9, '-' e '_'." >&2; exit 1; }
[[ "$BUCKET" =~ ^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$ ]] || { echo "Erro: nome de bucket inválido (3-63 chars, minúsculas, números, '.' e '-')." >&2; exit 1; }

ENV_FILE=".env"
CONTAINER="${INFRA_PREFIX:-infra}_seaweedfs"
get_env_var() { sed -n "s|^$1=||p" "$ENV_FILE" 2>/dev/null | tail -n1; }

ADMIN_KEY="$(get_env_var S3_ACCESS_KEY)"
ADMIN_SECRET="$(get_env_var S3_SECRET_KEY)"
[ -n "$ADMIN_KEY" ] && [ -n "$ADMIN_SECRET" ] || { echo "Erro: S3_ACCESS_KEY/S3_SECRET_KEY não definidos em $ENV_FILE (rode o install-infra.sh)." >&2; exit 1; }
docker inspect "$CONTAINER" >/dev/null 2>&1 || { echo "Erro: container $CONTAINER não encontrado." >&2; exit 1; }

APP_KEY="$(openssl rand -hex 10)"
APP_SECRET="$(openssl rand -hex 24)"

weed_shell() { printf '%s\n' "$@" | docker exec -i "$CONTAINER" weed shell -master=localhost:9333; }

weed_shell \
  "s3.configure -user=admin -access_key=$ADMIN_KEY -secret_key=$ADMIN_SECRET -actions=Admin -apply" \
  "s3.bucket.create -name $BUCKET" \
  "s3.configure -user=$APP -access_key=$APP_KEY -secret_key=$APP_SECRET -buckets=$BUCKET -actions=Read,Write,List,Tagging -apply" >/dev/null

cat <<OUT

✔ App '$APP' com acesso apenas ao bucket '$BUCKET'. Guarde as chaves (não são mostradas de novo):
  S3_ENDPOINT=http://${CONTAINER}:8333   (dentro da shared_net; path-style ligado)
  S3_BUCKET=$BUCKET
  S3_ACCESS_KEY=$APP_KEY
  S3_SECRET_KEY=$APP_SECRET
OUT
