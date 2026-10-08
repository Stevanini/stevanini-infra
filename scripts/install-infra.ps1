<#
.SYNOPSIS
  Equivalente PowerShell do install-infra.sh — sobe a infra compartilhada
  (Postgres, Redis, SeaweedFS, Keycloak) numa máquina Windows com Docker Desktop.

.DESCRIPTION
  Rode uma vez por máquina, numa pasta própria; depois use install-tenant.ps1
  em uma pasta por loja. Gera .env, docker-compose.infra.yml e .\data\* na
  pasta ATUAL. INFRA_PREFIX (variável de ambiente, padrão infra) define os nomes dos containers e precisa ser
  o mesmo no install-tenant.ps1. Idempotente.

.EXAMPLE
  mkdir C:\infra; cd C:\infra
  & D:\workspace\stevanini-infra\install-infra.ps1 -DbPort 5432
#>
param(
  [string]$DbPort = "",
  [string]$RedisPort = "",
  [string]$S3Port = "",
  [string]$KeycloakPort = "",
  [string]$KeycloakHostname = ""
)

$ErrorActionPreference = "Stop"

$InfraPrefix = if ($env:INFRA_PREFIX) { $env:INFRA_PREFIX } else { "infra" }

# Não rode dentro do checkout do repo: .env e docker-compose*.yml gerados aqui
# se misturam com os de outra instalação (infra x loja). Use uma pasta própria.
if ((Test-Path "./tenant/backend") -and (Test-Path "./package.json")) {
  throw "Esta pasta é o checkout do repositório. Crie uma pasta própria (ex.: mkdir C:\<nome>; cd C:\<nome>) e rode de lá."
}

$EnvFile = ".env"
$InfraCompose = "docker-compose.infra.yml"
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Log($msg) { Write-Host "==> $msg" }

function Write-LfFile($path, $text) {
  $full = Join-Path (Get-Location).Path $path
  [IO.File]::WriteAllText($full, ($text -replace "`r`n", "`n"), $Utf8NoBom)
}

function Get-EnvVar($key) {
  if (-not (Test-Path $EnvFile)) { return "" }
  $line = Get-Content $EnvFile | Where-Object { $_ -like "$key=*" } | Select-Object -Last 1
  if ($line) { return $line.Substring($key.Length + 1) }
  return ""
}

function Test-EnvVar($key) {
  (Test-Path $EnvFile) -and [bool](Get-Content $EnvFile | Where-Object { $_ -like "$key=*" })
}

function Set-EnvVar($key, $value) {
  $lines = @()
  if (Test-Path $EnvFile) { $lines = @(Get-Content $EnvFile) }
  $found = $false
  $lines = @($lines | ForEach-Object {
    if ($_ -like "$key=*") { $found = $true; "$key=$value" } else { $_ }
  })
  if (-not $found) { $lines += "$key=$value" }
  Write-LfFile $EnvFile (($lines -join "`n") + "`n")
}

function Set-EnvDefault($key, $value) {
  if (-not (Test-EnvVar $key)) { Set-EnvVar $key $value }
}

function New-Secret {
  $bytes = New-Object byte[] 32
  [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
  -join ($bytes | ForEach-Object { $_.ToString("x2") })
}

function Test-ContainerExists($name) {
  docker inspect -f "{{.Id}}" $name *> $null
  $LASTEXITCODE -eq 0
}

function Test-ContainerRunning($name) {
  (docker inspect -f "{{.State.Running}}" $name 2>$null) -eq "true"
}

# Evita "docker compose up" recriar (e dar Conflict) um container que já existe.
function Initialize-InfraContainer($service, $container) {
  if (Test-ContainerExists $container) {
    if (-not (Test-ContainerRunning $container)) { docker start $container | Out-Null }
  } else {
    docker compose --env-file $EnvFile -f $InfraCompose up -d $service
    if ($LASTEXITCODE -ne 0) { throw "Falha ao subir $service" }
  }
}

# Cria (ou atualiza a senha do) usuário e o banco do Keycloak no Postgres compartilhado.
# Idempotente; usa o socket local do container, sem senha admin.
function Initialize-KeycloakDatabase {
  $db = Get-EnvVar "KEYCLOAK_DB_NAME"; $user = Get-EnvVar "KEYCLOAK_DB_USER"
  $pass = Get-EnvVar "KEYCLOAK_DB_PASSWORD"; $admin = Get-EnvVar "POSTGRES_ADMIN_USER"
  $pg = "${InfraPrefix}_postgres"
  Log "Garantindo banco '$db' e usuário '$user' no Postgres"
  $role = @"
DO `$`$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '$user') THEN
    CREATE ROLE "$user" LOGIN PASSWORD '$pass';
  ELSE
    ALTER ROLE "$user" PASSWORD '$pass';
  END IF;
END `$`$;
"@
  $role | docker exec -i $pg psql -v ON_ERROR_STOP=1 -U $admin -d postgres
  if ($LASTEXITCODE -ne 0) { throw "Falha ao criar usuário do Keycloak" }
  $exists = docker exec $pg psql -U $admin -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='$db'"
  if ($exists -notmatch "1") {
    docker exec $pg psql -U $admin -d postgres -c "CREATE DATABASE `"$db`" OWNER `"$user`""
    if ($LASTEXITCODE -ne 0) { throw "Falha ao criar banco do Keycloak" }
  }
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { throw "'docker' não encontrado. Instale o Docker Desktop." }
docker compose version *> $null
if ($LASTEXITCODE -ne 0) { throw "plugin 'docker compose' não encontrado." }

if (-not (Test-Path $EnvFile)) { New-Item -ItemType File -Path $EnvFile | Out-Null }

if (-not $DbPort) { $DbPort = Get-EnvVar "DB_PORT" }
if (-not $DbPort) { $DbPort = "5432" }
if (-not $RedisPort) { $RedisPort = Get-EnvVar "REDIS_PORT" }
if (-not $RedisPort) { $RedisPort = "6379" }
if (-not $S3Port) { $S3Port = Get-EnvVar "S3_PORT" }
if (-not $S3Port) { $S3Port = "8333" }
if (-not $KeycloakPort) { $KeycloakPort = Get-EnvVar "KEYCLOAK_PORT" }
if (-not $KeycloakPort) { $KeycloakPort = "8080" }
if (-not $KeycloakHostname) { $KeycloakHostname = Get-EnvVar "KEYCLOAK_HOSTNAME" }

Log "Gerando/atualizando $EnvFile"
Set-EnvVar "DB_PORT" $DbPort
Set-EnvVar "REDIS_PORT" $RedisPort
Set-EnvVar "S3_PORT" $S3Port
Set-EnvVar "KEYCLOAK_PORT" $KeycloakPort
Set-EnvVar "KEYCLOAK_HOSTNAME" $KeycloakHostname
Set-EnvDefault "POSTGRES_ADMIN_USER" "postgres"
if (-not (Test-EnvVar "POSTGRES_ADMIN_PASSWORD")) { Set-EnvVar "POSTGRES_ADMIN_PASSWORD" (New-Secret) }
Set-EnvDefault "KEYCLOAK_ADMIN_USER" "admin"
if (-not (Test-EnvVar "KEYCLOAK_ADMIN_PASSWORD")) { Set-EnvVar "KEYCLOAK_ADMIN_PASSWORD" (New-Secret) }
Set-EnvDefault "KEYCLOAK_DB_NAME" "keycloak"
Set-EnvDefault "KEYCLOAK_DB_USER" "keycloak"
if (-not (Test-EnvVar "KEYCLOAK_DB_PASSWORD")) { Set-EnvVar "KEYCLOAK_DB_PASSWORD" (New-Secret) }

Log "Gerando $InfraCompose"
$compose = @'
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
'@
Write-LfFile $InfraCompose ($compose -replace "__PREFIX__", $InfraPrefix)

Log "Criando rede shared_net (se ainda não existir)"
docker network inspect shared_net *> $null
if ($LASTEXITCODE -ne 0) { docker network create shared_net | Out-Null }

Log "Subindo infra (Postgres, Redis, SeaweedFS, Keycloak)"
Initialize-InfraContainer "postgres" "${InfraPrefix}_postgres"
Initialize-InfraContainer "redis" "${InfraPrefix}_redis"
Initialize-InfraContainer "seaweedfs" "${InfraPrefix}_seaweedfs"

Log "Aguardando Postgres aceitar conexões"
$status = "starting"
for ($i = 0; $i -lt 60; $i++) {
  $status = docker inspect -f "{{.State.Health.Status}}" "${InfraPrefix}_postgres" 2>$null
  if ($status -eq "healthy") { break }
  Start-Sleep -Seconds 1
}
if ($status -ne "healthy") { throw "Postgres não ficou saudável a tempo (status: $status)." }

Initialize-KeycloakDatabase
Initialize-InfraContainer "keycloak" "${InfraPrefix}_keycloak"

Write-Host @"

✔ Infra pronta (${InfraPrefix}_postgres, ${InfraPrefix}_redis, ${InfraPrefix}_seaweedfs, ${InfraPrefix}_keycloak).
  Keycloak: http://localhost:$KeycloakPort (admin em KEYCLOAK_ADMIN_USER/KEYCLOAK_ADMIN_PASSWORD no .env; leva ~1 min pra subir).
  Agora instale cada loja com install-tenant.ps1, numa pasta própria por loja.
"@
