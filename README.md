# stevanini-infra

Infra **compartilhada** para uma VPS: **PostgreSQL 16**, **Redis 7** e **SeaweedFS** (API S3), tudo em Docker Compose e instalado com um único comando. Roda **uma vez por servidor**; cada loja/app é instalada depois pelo `install-tenant.sh` do respectivo repositório, usando a rede `shared_net`.

## Início rápido

Na VPS (Linux com Docker), numa pasta vazia:

```bash
mkdir -p /opt/infra && cd /opt/infra
curl -fsSL https://raw.githubusercontent.com/Stevanini/stevanini-infra/master/install-infra.sh | bash -s --
```

Ao final, Postgres, Redis e SeaweedFS estão no ar e as credenciais admin ficam em `/opt/infra/.env`.

## Serviços

| Serviço   | Container (`INFRA_PREFIX=infra`) | Porta padrão | Imagem                      |
|-----------|----------------------------------|--------------|-----------------------------|
| Postgres  | `infra_postgres`                 | 5432         | `postgres:16-alpine`        |
| Redis     | `infra_redis`                    | 6379         | `redis:7-alpine`            |
| SeaweedFS | `infra_seaweedfs` (S3)           | 8333         | `chrislusf/seaweedfs:latest`|

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
ssh root@IP_DA_VPS "mkdir -p /opt/infra && cd /opt/infra && curl -fsSL -H 'Authorization: token $t' https://raw.githubusercontent.com/Stevanini/stevanini-infra/master/install-infra.sh | bash -s --"
```

**B) `gh` na VPS:**

```bash
gh auth status || gh auth login
mkdir -p /opt/infra && cd /opt/infra
gh api "repos/Stevanini/stevanini-infra/contents/install-infra.sh?ref=master" \
  -H "Accept: application/vnd.github.raw" | bash -s --
```

**Windows (desenvolvimento local):** use `install-infra.ps1`.

## Opções

Passe flags após `bash -s --` ou use variáveis de ambiente:

```bash
curl -fsSL https://raw.githubusercontent.com/Stevanini/stevanini-infra/master/install-infra.sh \
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
| `install-infra.sh`          | Instalador para Linux (VPS)                                    |
| `install-infra.ps1`         | Equivalente para Windows                                       |
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

## Solução de problemas

| Sintoma                                   | Causa provável / solução                                              |
|-------------------------------------------|-----------------------------------------------------------------------|
| Script recusa rodar                       | Está dentro do checkout do repo; use uma pasta vazia (`/opt/infra`)   |
| `port is already allocated`               | Porta em uso; reexecute com `--db-port=`, `--redis-port=` ou `--s3-port=` |
| Postgres reinicia com erro de permissão   | Rode o script de novo (ele corrige o dono de `data/postgres`)         |
| App não alcança `infra_postgres`          | O container do app precisa estar na rede `shared_net`                 |
