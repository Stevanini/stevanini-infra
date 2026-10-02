# stevanini-infra

Infra **compartilhada** da VPS: Postgres 16, Redis 7 e SeaweedFS (S3). Roda uma vez por servidor; cada loja/app é instalada depois com o `install-tenant.sh` do respectivo repositório.

| Serviço   | Container (`INFRA_PREFIX=infra`) | Porta padrão |
|-----------|----------------------------------|--------------|
| Postgres  | `infra_postgres`                 | 5432         |
| Redis     | `infra_redis`                    | 6379         |
| SeaweedFS | `infra_seaweedfs` (S3)           | 8333         |

Todos entram na rede Docker `shared_net`, que o script cria se não existir.

## Arquivos

- `install-infra.sh` — instalador para Linux (VPS).
- `install-infra.ps1` — equivalente para Windows (desenvolvimento local).
- `docker-compose.infra.yml` — compose gerado pelo instalador.
- `.env` — credenciais admin do Postgres e portas (gerado; **não versionar**).
- `data/` — volumes persistentes (**não versionar**).

## Pré-requisitos na VPS

`docker`, plugin `docker compose` e `openssl`.

```bash
apt update && apt install -y docker.io docker-compose-plugin openssl
```

## Instalação na VPS

Rode de uma pasta própria e vazia (ex.: `/opt/infra`). O script recusa rodar dentro do checkout do repositório.

### A) `gh` logado no seu PC (token não vai para a VPS)

PowerShell, no PC:

```powershell
$t = gh auth token
ssh root@IP_DA_VPS "mkdir -p /opt/infra && cd /opt/infra && curl -fsSL -H 'Authorization: token $t' https://raw.githubusercontent.com/Stevanini/stevanini-infra/master/install-infra.sh | bash -s --"
```

### B) `gh` instalado e logado na VPS

```bash
gh auth status || gh auth login
mkdir -p /opt/infra && cd /opt/infra
gh api repos/Stevanini/stevanini-infra/contents/install-infra.sh?ref=master \
  -H "Accept: application/vnd.github.raw" | bash -s --
```


## Opções

```bash
bash -s -- --db-port=5433 --redis-port=6380 --s3-port=8334
INFRA_PREFIX=minha bash -s --      # container_name: minha_postgres, ...
```

- `INFRA_PREFIX` (padrão `infra`) deve ser o **mesmo valor** usado no `install-tenant.sh`.
- As portas ficam salvas no `.env` e são reaproveitadas nas próximas execuções.

## O que o script faz

1. Gera/atualiza o `.env` (senha admin do Postgres aleatória, só na primeira vez).
2. Gera o `docker-compose.infra.yml`.
3. Cria a rede `shared_net` (se não existir).
4. Corrige o dono de `data/postgres` (uid 70) e `data/redis` (uid 999).
5. Sobe Postgres, Redis e SeaweedFS e espera o Postgres ficar saudável.

É idempotente: pode rodar de novo com segurança (atualizar, mudar porta, religar container parado).

## Verificação

```bash
cd /opt/infra
docker compose --env-file .env -f docker-compose.infra.yml ps
docker exec infra_redis redis-cli ping
docker network inspect shared_net
```

## Segurança

As portas são publicadas em `0.0.0.0` e o Redis não tem senha. Na VPS, restrinja o acesso:

- firewall (`ufw allow from SEU_IP to any port 5432`) ou
- trocar o bind no compose para `127.0.0.1:${DB_PORT:-5432}:5432` (idem Redis e S3), ou
- remover `ports:` dos serviços acessados só por containers da `shared_net`.

Nunca commite `.env` nem `data/`.

## Backup

Os dados ficam em `./data/*`. Para um backup consistente do Postgres:

```bash
docker exec infra_postgres pg_dumpall -U postgres | gzip > backup-$(date +%F).sql.gz
```
