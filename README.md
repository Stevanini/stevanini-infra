# stevanini-infra

Infra **compartilhada** para uma VPS: **PostgreSQL 18**, **Redis 7** e **SeaweedFS** (API S3), tudo em Docker Compose e instalado com um único comando. Roda **uma vez por servidor**; cada loja/app é instalada depois pelo `install-tenant.sh` do respectivo repositório, usando a rede `shared_net`.

## Início rápido

Na VPS (Linux com Docker), numa pasta vazia:

```bash
mkdir -p /opt/infra && cd /opt/infra
curl -fsSL https://raw.githubusercontent.com/Stevanini/stevanini-infra/master/scripts/install-infra.sh | bash -s --
```

Ao final, Postgres, Redis e SeaweedFS estão no ar e as credenciais admin ficam em `/opt/infra/.env`.

## Serviços

| Serviço   | Container (`INFRA_PREFIX=infra`) | Porta padrão | Imagem                      |
|-----------|----------------------------------|--------------|-----------------------------|
| Postgres  | `infra_postgres`                 | 5432         | `postgres:18-alpine`        |
| Redis     | `infra_redis`                    | 6379         | `redis:7-alpine`            |
| SeaweedFS | `infra_seaweedfs` (S3)           | 8333         | `chrislusf/seaweedfs:latest`|
| Keycloak  | `infra_keycloak`                 | 8080         | `quay.io/keycloak/keycloak:26.0` (usa o `infra_postgres`, banco `keycloak`) |

Todos entram na rede Docker externa `shared_net` (criada pelo script se não existir). Apps de outros stacks acessam os serviços pelo nome do container, ex.: `infra_postgres:5432`.

## Pré-requisitos

`docker`, plugin `docker compose` e `openssl`:

```bash
apt update && apt install -y docker.io docker-compose-plugin openssl
```

## Instalação

Rode sempre de uma pasta própria e vazia (ex.: `/opt/infra`). O script recusa rodar dentro do checkout do repositório.

| Cenário                               | Como                                   |
|---------------------------------------|----------------------------------------|
| Repo público (caso atual)             | `curl` direto, como no início rápido   |
| Repo privado, `gh` logado no seu PC   | opção A (o token não vai para a VPS)   |
| Repo privado, `gh` logado na VPS      | opção B                                |

**A) `gh` no seu PC** (PowerShell):

```powershell
$t = gh auth token
ssh root@IP_DA_VPS "mkdir -p /opt/infra && cd /opt/infra && curl -fsSL -H 'Authorization: token $t' https://raw.githubusercontent.com/Stevanini/stevanini-infra/master/scripts/install-infra.sh | bash -s --"
```

**B) `gh` na VPS:**

```bash
gh auth status || gh auth login
mkdir -p /opt/infra && cd /opt/infra
gh api "repos/Stevanini/stevanini-infra/contents/scripts/install-infra.sh?ref=master" \
  -H "Accept: application/vnd.github.raw" | bash -s --
```

**Windows (desenvolvimento local):** use `scripts/install-infra.ps1`.

## Opções

Passe flags após `bash -s --` ou use variáveis de ambiente:

```bash
curl -fsSL https://raw.githubusercontent.com/Stevanini/stevanini-infra/master/scripts/install-infra.sh \
  | INFRA_PREFIX=minha bash -s -- --db-port=5433 --redis-port=6380 --s3-port=8334
```

| Opção                     | Padrão  | Descrição                                             |
|---------------------------|---------|-------------------------------------------------------|
| `--db-port=N`             | `5432`  | Porta publicada do Postgres                           |
| `--redis-port=N`          | `6379`  | Porta publicada do Redis                              |
| `--s3-port=N`             | `8333`  | Porta publicada do S3 (SeaweedFS)                     |
| `INFRA_PREFIX` (env)      | `infra` | Prefixo dos containers (`minha_postgres`, ...)        |

- `INFRA_PREFIX` deve ser o **mesmo valor** usado no `install-tenant.sh`.
- As portas ficam salvas no `.env` e são reaproveitadas nas próximas execuções.

## O que o script faz

1. Gera/atualiza o `.env` (senha admin do Postgres aleatória, só na primeira vez).
2. Gera o `docker-compose.infra.yml`.
3. Cria a rede `shared_net` (se não existir).
4. Ajusta o dono de `data/postgres` (uid 70) e `data/redis` (uid 999).
5. Sobe os três serviços e espera o Postgres ficar saudável.

É **idempotente**: pode rodar de novo para atualizar, trocar porta ou religar um container parado.

## Arquivos

| Arquivo                     | Função                                                         |
|-----------------------------|----------------------------------------------------------------|
| `scripts/install-infra.sh`          | Instalador para Linux (VPS)                                    |
| `scripts/install-infra.ps1`         | Equivalente para Windows                                       |
| `docker-compose.infra.yml`  | Compose dos serviços (regenerado pelo instalador)              |
| `.env.example`              | Modelo do `.env`                                               |
| `.env` *(gerado)*           | Credenciais admin e portas. **Nunca versionar**                |
| `data/` *(gerado)*          | Volumes persistentes. **Nunca versionar**                      |

## Operação

```bash
cd /opt/infra
docker compose --env-file .env -f docker-compose.infra.yml ps          # status
docker compose --env-file .env -f docker-compose.infra.yml logs -f     # logs
docker compose --env-file .env -f docker-compose.infra.yml pull && \
docker compose --env-file .env -f docker-compose.infra.yml up -d       # atualizar imagens

docker exec infra_redis redis-cli ping                                  # deve responder PONG
docker network inspect shared_net                                       # containers conectados
```

### Subir serviços individualmente

```bash
docker compose -f docker-compose.infra.yml up -d postgres   # só o Postgres (idem redis, seaweedfs)
docker compose -f docker-compose.infra.yml up -d keycloak   # Keycloak (sobe o Postgres junto, se preciso)
```

O Keycloak usa o `infra_postgres` e precisa que o banco `keycloak` já exista. Os scripts de instalação criam o banco; ao subir só pelo compose num servidor novo, crie-o uma vez:

```bash
set -a; . ./.env; set +a
docker exec -i infra_postgres psql -U "$POSTGRES_ADMIN_USER" -d postgres   -c "CREATE ROLE keycloak LOGIN PASSWORD '$KEYCLOAK_DB_PASSWORD'"   -c "CREATE DATABASE keycloak OWNER keycloak"
```

Sem o banco ou com senha diferente da do `.env`, o Keycloak reinicia em loop; veja o motivo em `docker logs infra_keycloak`.

## Segurança

> Este repositório é **público**: nunca commite `.env`, senhas ou o conteúdo de `data/`.

Por padrão as portas são publicadas em `0.0.0.0` e o Redis não tem senha. Na VPS, restrinja o acesso:

- firewall: `ufw allow from SEU_IP to any port 5432`; ou
- bind local no compose: `127.0.0.1:${DB_PORT:-5432}:5432` (idem Redis e S3); ou
- remova `ports:` dos serviços acessados apenas por containers da `shared_net`.

## Backup e restauração

Os dados ficam em `./data/*`. Backup consistente do Postgres:

```bash
docker exec infra_postgres pg_dumpall -U postgres | gzip > backup-$(date +%F).sql.gz
```

Restaurar:

```bash
gunzip -c backup-AAAA-MM-DD.sql.gz | docker exec -i infra_postgres psql -U postgres
```

### Atualizar a versão major do Postgres (dump e restore)

Trocar só a imagem (ex.: 16 → 18) **não funciona** com dados já existentes: o Postgres não sobe com o diretório de dados de outra major. Migre com dump e restore:

```bash
cd /opt/infra
mkdir -p data/backup-pg
# 1. dump completo (todos os bancos e usuários) com o Postgres antigo ainda no ar
docker exec infra_postgres pg_dumpall -U postgres --quote-all-identifiers > data/backup-pg/dumpall.sql

# 2. parar, guardar os dados antigos como backup e criar a pasta vazia
docker compose -f docker-compose.infra.yml stop keycloak postgres
mv data/postgres data/backup-pg/postgres-data && mkdir data/postgres

# 3. trocar a imagem no compose (postgres:18-alpine) e subir o Postgres novo
docker compose -f docker-compose.infra.yml up -d postgres

# 4. restaurar (o aviso 'role "postgres" already exists' é esperado)
docker exec -i infra_postgres psql -U postgres -d postgres < data/backup-pg/dumpall.sql

# 5. subir o restante
docker compose -f docker-compose.infra.yml up -d
```

A partir do Postgres 18, o volume é montado em `/var/lib/postgresql` (e não `/var/lib/postgresql/data`). Confirme os bancos com `docker exec infra_postgres psql -U postgres -c '\l'` e só apague `data/backup-pg/postgres-data` depois de validar os apps.

## Solução de problemas

| Sintoma                                   | Causa provável / solução                                              |
|-------------------------------------------|-----------------------------------------------------------------------|
| Script recusa rodar                       | Está dentro do checkout do repo; use uma pasta vazia (`/opt/infra`)   |
| `port is already allocated`               | Porta em uso; reexecute com `--db-port=`, `--redis-port=` ou `--s3-port=` |
| Postgres reinicia com erro de permissão   | Rode o script de novo (ele corrige o dono de `data/postgres`)         |
| App não alcança `infra_postgres`          | O container do app precisa estar na rede `shared_net`                 |
