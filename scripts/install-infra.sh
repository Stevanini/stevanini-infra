#!/usr/bin/env bash
# Sobe a infra COMPARTILHADA da VPS (Postgres, Redis, SeaweedFS, Keycloak). Rode uma vez
# por servidor; depois use install-tenant.sh pra cada loja.
#
# Uso: mkdir -p /opt/infra && cd /opt/infra && \
#      curl -fsSL .../install-infra.sh | bash -s -- [opções]
# (baixar de repo privado: ver o cabeçalho de install-tenant.sh)
#
# Opções: [--db-port=5432] [--redis-port=6379] [--s3-port=8333]
#         [--keycloak-port=8080] [--keycloak-hostname=auth.exemplo.com]
# INFRA_PREFIX (padrão: infra) define os nomes dos containers
# (<INFRA_PREFIX>_postgres, _redis, _seaweedfs, _keycloak) — nomes genéricos, a infra serve
# qualquer app; precisa ser o MESMO valor usado no install-tenant.sh.
#
# Gera .env (credenciais admin do Postgres), docker-compose.infra.yml e
# ./data/* na pasta atual. O install-tenant.sh lê a senha admin direto do
# container do Postgres, então não precisa apontar pra esta pasta.
#
# Idempotente — pode rodar de novo com segurança.

if [ -z "${BASH_VERSION:-}" ]; then
  exec bash "$0" "$@"
fi

set -euo pipefail
[ -n "${BASH_SOURCE[0]:-}" ] && cd "$(dirname "${BASH_SOURCE[0]}")/.."

INFRA_PREFIX="${INFRA_PREFIX:-infra}"

# Não rode dentro do checkout do repo: .env e docker-compose*.yml gerados aqui
# se misturam com os de outra instalação (infra x loja). Use uma pasta própria.
if [ -d "./tenant/backend" ] && [ -f "./package.json" ]; then
  echo "Erro: esta pasta é o checkout do repositório. Crie uma pasta própria (ex.: mkdir -p /opt/<nome> && cd /opt/<nome>) e rode de lá." >&2
  exit 1
fi

ENV_FILE=".env"
INFRA_COMPOSE="docker-compose.infra.yml"

DB_PORT="5432"
REDIS_PORT="6379"
S3_PORT="8333"
KEYCLOAK_PORT="8080"
KEYCLOAK_HOSTNAME=""

log() { echo "==> $*"; }

get_env_var() { sed -n "s|^$2=||p" "$1" 2>/dev/null | tail -n1; }

set_env_var() {
  local file="$1" key="$2" value="$3"
  if grep -q "^${key}=" "$file" 2>/dev/null; then
    sed -i "s|^${key}=.*|${key}=${value}|" "$file"
  else
    printf '%s=%s\n' "$key" "$value" >> "$file"
  fi
}

default_env_var() {
  grep -q "^$1=" "$ENV_FILE" 2>/dev/null || set_env_var "$ENV_FILE" "$1" "$2"
}

generate_secret_if_missing() {
  grep -q "^$1=" "$ENV_FILE" 2>/dev/null || set_env_var "$ENV_FILE" "$1" "$(openssl rand -hex 32)"
}

container_running() {
  [ "$(docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null)" = "true" ]
}

container_exists() {
  docker inspect -f '{{.Id}}' "$1" >/dev/null 2>&1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "Erro: '$1' não encontrado. Instale antes de continuar." >&2; exit 1; }
}

# Sobe (ou só inicia, se já existir) um container de infra sem passar por
# "docker compose up", que tenta CRIAR um container novo com aquele nome e
# dá "Conflict" quando já existe um parado que o compose não reconhece como
# seu (ex.: criado antes de existir esse compose file, ou por outro comando).
ensure_infra_container_up() {
  local service="$1" container="$2"
  if container_exists "$container"; then
    container_running "$container" || docker start "$container" >/dev/null
  else
    docker compose --env-file "$ENV_FILE" -f "$INFRA_COMPOSE" up -d "$service"
  fi
}

# Manutenção "na mão" (ex.: "chown -R" numa pasta pai) pode trocar o dono dos
# volumes dos serviços que rodam com usuário próprio no container (Postgres
# uid 70, Redis uid 999): o processo segue rodando mas perde acesso aos
# próprios arquivos e nunca mais volta sozinho. Corrige a cada execução, sem
# apagar dado. SeaweedFS roda como root, então não sofre disso.
ensure_data_dir_ownership() {
  local dir="$1" uid="$2" gid="$3" owner
  [ -d "$dir" ] || return 0
  owner="$(stat -c '%u' "$dir" 2>/dev/null || echo "")"
  [ "$owner" = "$uid" ] && return 0
  log "Corrigindo dono de $dir (uid $owner -> $uid)"
  # "-n" faz o sudo falhar na hora em vez de esperar senha (script não-interativo).
  chown -R "$uid:$gid" "$dir" 2>/dev/null || sudo -n chown -R "$uid:$gid" "$dir" 2>/dev/null || \
    echo "Aviso: não foi possível corrigir o dono de $dir (sem permissão). Rode manualmente: sudo chown -R $uid:$gid $dir" >&2
}

# Cria (ou atualiza a senha do) usuário e o banco do Keycloak dentro do
# Postgres compartilhado. Idempotente; usa o socket local do container, sem senha admin.
ensure_keycloak_database() {
  local db user pass pg_admin
  db="$(get_env_var "$ENV_FILE" KEYCLOAK_DB_NAME)"
  user="$(get_env_var "$ENV_FILE" KEYCLOAK_DB_USER)"
  pass="$(get_env_var "$ENV_FILE" KEYCLOAK_DB_PASSWORD)"
  pg_admin="$(get_env_var "$ENV_FILE" POSTGRES_ADMIN_USER)"
  log "Garantindo banco '$db' e usuário '$user' no Postgres"
  docker exec -i "${INFRA_PREFIX}_postgres" psql -v ON_ERROR_STOP=1 -U "$pg_admin" -d postgres <<SQL
DO \$\$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '$user') THEN
    CREATE ROLE "$user" LOGIN PASSWORD '$pass';
  ELSE
    ALTER ROLE "$user" PASSWORD '$pass';
  END IF;
END \$\$;
SQL
  docker exec "${INFRA_PREFIX}_postgres" psql -U "$pg_admin" -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='$db'" | grep -q 1     || docker exec "${INFRA_PREFIX}_postgres" psql -U "$pg_admin" -d postgres -c "CREATE DATABASE \"$db\" OWNER \"$user\""
}

touch "$ENV_FILE"
v="$(get_env_var "$ENV_FILE" DB_PORT)"; [ -n "$v" ] && DB_PORT="$v"
v="$(get_env_var "$ENV_FILE" REDIS_PORT)"; [ -n "$v" ] && REDIS_PORT="$v"
v="$(get_env_var "$ENV_FILE" S3_PORT)"; [ -n "$v" ] && S3_PORT="$v"
v="$(get_env_var "$ENV_FILE" KEYCLOAK_PORT)"; [ -n "$v" ] && KEYCLOAK_PORT="$v"
v="$(get_env_var "$ENV_FILE" KEYCLOAK_HOSTNAME)"; [ -n "$v" ] && KEYCLOAK_HOSTNAME="$v"

for arg in "$@"; do
  case "$arg" in
    --db-port=*) DB_PORT="${arg#*=}" ;;
    --redis-port=*) REDIS_PORT="${arg#*=}" ;;
    --s3-port=*) S3_PORT="${arg#*=}" ;;
    --keycloak-port=*) KEYCLOAK_PORT="${arg#*=}" ;;
    --keycloak-hostname=*) KEYCLOAK_HOSTNAME="${arg#*=}" ;;
    *) echo "Argumento desconhecido: $arg" >&2; exit 1 ;;
  esac
done

require_cmd docker
require_cmd openssl
docker compose version >/dev/null 2>&1 || { echo "Erro: plugin 'docker compose' não encontrado." >&2; exit 1; }

log "Gerando/atualizando $ENV_FILE"
set_env_var "$ENV_FILE" DB_PORT "$DB_PORT"
set_env_var "$ENV_FILE" REDIS_PORT "$REDIS_PORT"
set_env_var "$ENV_FILE" S3_PORT "$S3_PORT"
set_env_var "$ENV_FILE" KEYCLOAK_PORT "$KEYCLOAK_PORT"
set_env_var "$ENV_FILE" KEYCLOAK_HOSTNAME "$KEYCLOAK_HOSTNAME"
default_env_var POSTGRES_ADMIN_USER "postgres"
generate_secret_if_missing POSTGRES_ADMIN_PASSWORD
default_env_var KEYCLOAK_ADMIN_USER "admin"
generate_secret_if_missing KEYCLOAK_ADMIN_PASSWORD
default_env_var KEYCLOAK_DB_NAME "keycloak"
default_env_var KEYCLOAK_DB_USER "keycloak"
generate_secret_if_missing KEYCLOAK_DB_PASSWORD

log "Gerando $INFRA_COMPOSE"
cat > "$INFRA_COMPOSE" <<'YAML'
services:
  postgres:
    image: postgres:18-alpine
    container_name: __PREFIX___postgres
    restart: unless-stopped
    environment:
      POSTGRES_USER: ${POSTGRES_ADMIN_USER:-postgres}
      POSTGRES_PASSWORD: ${POSTGRES_ADMIN_PASSWORD:?defina POSTGRES_ADMIN_PASSWORD no .env}
      POSTGRES_DB: postgres
      POSTGRES_INITDB_ARGS: "--encoding=UTF8 --lc-collate=C --lc-ctype=C"
    ports:
      - "${DB_PORT:-5432}:5432"
    volumes:
      - ./data/postgres:/var/lib/postgresql
    networks:
      - shared_net
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_ADMIN_USER:-postgres} -d postgres"]
      interval: 10s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    container_name: __PREFIX___redis
    restart: unless-stopped
    ports:
      - "${REDIS_PORT:-6379}:6379"
    volumes:
      - ./data/redis:/data
    networks:
      - shared_net
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

  seaweedfs:
    image: chrislusf/seaweedfs:latest
    container_name: __PREFIX___seaweedfs
    restart: unless-stopped
    command: server -dir=/data -s3 -ip.bind=0.0.0.0
    ports:
      - "${S3_PORT:-8333}:8333"
    volumes:
      - ./data/seaweedfs:/data
    networks:
      - shared_net

  keycloak:
    image: quay.io/keycloak/keycloak:26.0
    container_name: __PREFIX___keycloak
    restart: unless-stopped
    command: start
    depends_on:
      postgres:
        condition: service_healthy
    environment:
      KC_DB: postgres
      KC_DB_URL: jdbc:postgresql://__PREFIX___postgres:5432/${KEYCLOAK_DB_NAME:-keycloak}
      KC_DB_USERNAME: ${KEYCLOAK_DB_USER:-keycloak}
      KC_DB_PASSWORD: ${KEYCLOAK_DB_PASSWORD}
      KC_BOOTSTRAP_ADMIN_USERNAME: ${KEYCLOAK_ADMIN_USER:-admin}
      KC_BOOTSTRAP_ADMIN_PASSWORD: ${KEYCLOAK_ADMIN_PASSWORD:?defina KEYCLOAK_ADMIN_PASSWORD no .env}
      KC_HOSTNAME: ${KEYCLOAK_HOSTNAME:-}
      KC_HOSTNAME_STRICT: "false"
      KC_HTTP_ENABLED: "true"
      KC_PROXY_HEADERS: xforwarded
    ports:
      - "${KEYCLOAK_PORT:-8080}:8080"
    networks:
      - shared_net

networks:
  shared_net:
    external: true
    name: shared_net
YAML
# Heredoc literal acima — aplica o prefixo da infra (INFRA_PREFIX) nos container_name.
sed -i "s/__PREFIX__/${INFRA_PREFIX}/g" "$INFRA_COMPOSE"

log "Criando rede shared_net (se ainda não existir)"
docker network inspect shared_net >/dev/null 2>&1 || docker network create shared_net

ensure_data_dir_ownership "./data/postgres" 70 70   # usuário "postgres" em postgres:18-alpine
ensure_data_dir_ownership "./data/redis" 999 1000   # usuário "redis" em redis:7-alpine

log "Subindo infra (Postgres, Redis, SeaweedFS, Keycloak)"
ensure_infra_container_up postgres "${INFRA_PREFIX}_postgres"
ensure_infra_container_up redis "${INFRA_PREFIX}_redis"
ensure_infra_container_up seaweedfs "${INFRA_PREFIX}_seaweedfs"

log "Aguardando Postgres aceitar conexões"
for i in $(seq 1 60); do
  status="$(docker inspect -f '{{.State.Health.Status}}' "${INFRA_PREFIX}_postgres" 2>/dev/null || echo starting)"
  [ "$status" = "healthy" ] && break
  sleep 1
  if [ "$i" -eq 60 ]; then
    echo "Erro: Postgres não ficou saudável a tempo (status: $status)." >&2
    exit 1
  fi
done

ensure_keycloak_database
ensure_infra_container_up keycloak "${INFRA_PREFIX}_keycloak"

cat <<EOF

✔ Infra pronta (${INFRA_PREFIX}_postgres, ${INFRA_PREFIX}_redis, ${INFRA_PREFIX}_seaweedfs, ${INFRA_PREFIX}_keycloak).
  Keycloak: http://localhost:${KEYCLOAK_PORT} (admin em KEYCLOAK_ADMIN_USER/KEYCLOAK_ADMIN_PASSWORD no .env; leva ~1 min pra subir).
  Agora instale cada loja com install-tenant.sh, numa pasta própria por loja.
EOF
