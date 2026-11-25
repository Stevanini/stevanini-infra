# Backup do medintelect (control-plane + data-plane)

Script: `backup-medintelect-db.sh` (cópia local) → instalado em `/usr/local/bin/backup-medintelect-db.sh` no servidor `stevanini`.

> Não confundir com `medintelect/control-plane/scripts/backup.sh` (do repositório, documentado em `docs/operacao.md`). Aquele não está instalado no servidor; este cobre também roles, `.env` e MinIO.

## O que cada backup contém

Pasta `/var/backups/medintelect/AAAAMMDD-HHMMSS/` no servidor (permissão 700, arquivos 600):

| Arquivo | Conteúdo |
|---|---|
| `<banco>.dump` | um por banco: `control_plane_medintelect`, `medintelect`, `clinica_renova`, `clinicaintegrar`, `catianesousa` (formato custom do `pg_dump`) |
| `globals.sql` | roles e senhas do Postgres (usuários `t_...` dos tenants) |
| `env.tar.gz` | `.env` + `docker-compose*.yml` das 4 stacks (inclui `ENCRYPTION_KEY`) |
| `minio.tar.gz` | dados do MinIO (bucket `clinical-documents`, config e IAM) |

> `env.tar.gz` tem segredos. Sem o `ENCRYPTION_KEY` as senhas em `tenant_databases` não são recuperáveis.

## Rodar no servidor

Roda sozinho todo dia às 03:00 (`/etc/cron.d/backup-medintelect`, log em `/var/log/backup-medintelect.log`). Backups com mais de 14 dias são apagados.

Rodar na hora:

```bash
ssh stevanini /usr/local/bin/backup-medintelect-db.sh
# saída esperada: OK /var/backups/medintelect/<data-hora> (<tamanho>)
```

Ver os backups existentes:

```bash
ssh stevanini 'ls -lh /var/backups/medintelect/'
```

Se o script falhar, ele apaga a pasta incompleta e sai com erro. Veja o log:

```bash
ssh stevanini 'tail -50 /var/log/backup-medintelect.log'
```

Atualizar o script no servidor depois de editar a cópia local:

```bash
scp backup-medintelect-db.sh stevanini:/usr/local/bin/ && ssh stevanini chmod 755 /usr/local/bin/backup-medintelect-db.sh
```

## Copiar para a sua máquina

Todos os backups (só baixa o que for novo):

```bash
mkdir -p ~/backups/medintelect
rsync -av --chmod=D700,F600 stevanini:/var/backups/medintelect/ ~/backups/medintelect/
```

Só o mais recente:

```bash
L=$(ssh stevanini 'ls -1 /var/backups/medintelect | tail -1')
rsync -av --chmod=D700,F600 "stevanini:/var/backups/medintelect/$L/" ~/backups/medintelect/$L/
```

Sem `rsync`: `scp -r stevanini:/var/backups/medintelect/<pasta> ~/backups/medintelect/`.

Guarde a cópia fora de repositórios git. Se a pasta for sincronizada na nuvem, cifre antes (`age` ou `gpg`).

## Restaurar na sua máquina (para abrir no DBeaver)

Usa o container `infra_postgres` (Postgres 18, porta 5432, usuário `postgres`). Não precisa de `pg_restore` instalado.

> O `infra_postgres` já tem `control_plane_medintelect` e `data_plane_medintelect` (desenvolvimento). **Restaure sempre com outro nome** (`*_bkp`), senão `--clean`/`--create` apagam esses dados.

```bash
cd ~/backups/medintelect/<pasta>

# um tenant (troque clinica_renova pelo banco desejado)
docker exec infra_postgres createdb -U postgres clinica_renova_bkp
docker exec -i infra_postgres pg_restore -U postgres -d clinica_renova_bkp --no-owner --no-privileges < clinica_renova.dump

# control-plane de produção
docker exec infra_postgres createdb -U postgres control_plane_prod_bkp
docker exec -i infra_postgres pg_restore -U postgres -d control_plane_prod_bkp --no-owner --no-privileges < control_plane_medintelect.dump
```

- `--no-owner --no-privileges`: dispensa o `globals.sql` e os roles `t_...`/`medintelect`; tudo fica com o dono `postgres`.
- No DBeaver: conexão `localhost:5432`, usuário `postgres`, **sem túnel SSH**; atualize a lista de bancos (F5) e abra `clinica_renova_bkp`.
- Os dumps têm dados clínicos reais: ao terminar, `docker exec infra_postgres dropdb -U postgres clinica_renova_bkp`.

Sem `infra_postgres`: `docker run -d --name pg-restore -e POSTGRES_PASSWORD=local -p 55432:5432 postgres:16-alpine` e use os mesmos comandos com `pg-restore` no lugar de `infra_postgres` (DBeaver em `localhost:55432`, senha `local`).

## Restaurar no servidor (desastre)

Não testado de ponta a ponta; **apaga os dados atuais do banco**. Suspenda o tenant antes e teste primeiro em outro nome.

```bash
# roles e senhas primeiro (pode dar "already exists", ignore)
docker exec -i medintelect-infra-medintelect-postgres-1 psql -U medintelect -d postgres < globals.sql

# um banco
docker exec -i medintelect-infra-medintelect-postgres-1 pg_restore -U medintelect -d postgres --create --clean --if-exists < clinica_renova.dump
```

Para recuperar `.env`/compose ou MinIO: `tar xzf env.tar.gz` e `tar xzf minio.tar.gz` (o MinIO com o container parado).

## Limites

- O backup fica no mesmo disco do servidor: copie para fora (seção acima) ou agende o `rsync`.
- Não inclui os Postgres de outras apps (gym, oremais, on-classificados, rf-control).
- O MinIO é copiado com `tar` ao vivo: ok para KB; com GBs trocar por `mc mirror`.
