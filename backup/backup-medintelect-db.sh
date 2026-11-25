#!/usr/bin/env bash
# Backup do Postgres do medintelect: todos os bancos + roles + .env (ENCRYPTION_KEY).
# Instalado em /usr/local/bin/backup-medintelect-db.sh; cron diário em /etc/cron.d/backup-medintelect.
set -euo pipefail

C=medintelect-infra-medintelect-postgres-1
PGU=medintelect
DEST=/var/backups/medintelect
KEEP_DAYS=14
TS=$(date +%Y%m%d-%H%M%S)
OUT=$DEST/$TS

umask 077
mkdir -p "$OUT"
trap 'rm -rf "$OUT"' ERR  # nunca deixa backup pela metade

# roles e senhas (os usuários t_... dos tenants)
docker exec "$C" pg_dumpall -U "$PGU" --globals-only > "$OUT/globals.sql"

# um dump por banco, formato custom (restauração seletiva com pg_restore)
for db in $(docker exec "$C" psql -U "$PGU" -d postgres -Atc "select datname from pg_database where not datistemplate and datname<>'postgres'"); do
  docker exec "$C" pg_dump -U "$PGU" -Fc "$db" > "$OUT/$db.dump"
  docker exec -i "$C" pg_restore -l < "$OUT/$db.dump" > /dev/null  # valida que o dump é legível
done

# sem o ENCRYPTION_KEY as senhas em tenant_databases não são recuperáveis;
# compose/infra permitem recriar Postgres e MinIO do zero
tar czf "$OUT/env.tar.gz" -C /var/www/medintelect \
  control-plane/.env control-plane/docker-compose.yml control-plane/docker-compose.infra.yml \
  control-plane-web/.env control-plane-web/docker-compose.yml \
  data-plane/.env data-plane/docker-compose.yml \
  data-plane-web/.env data-plane-web/docker-compose.yml

# MinIO (bucket clinical-documents, data-plane). Inclui .minio.sys (config/IAM).
# shortcut: tar do diretório vivo, ok para o volume atual (KB); com GBs ou escrita intensa trocar por `mc mirror`
tar czf "$OUT/minio.tar.gz" -C /var/www/medintelect/control-plane/data minio-dp

# retenção
find "$DEST" -mindepth 1 -maxdepth 1 -type d -mtime +"$KEEP_DAYS" -exec rm -rf {} +

echo "OK $OUT ($(du -sh "$OUT" | cut -f1))"
