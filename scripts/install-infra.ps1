<#
.SYNOPSIS
  Equivalente PowerShell do install-infra.sh — sobe a infra compartilhada
  (Postgres, Redis, SeaweedFS) numa máquina Windows com Docker Desktop.

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
  [string]$S3Port = ""
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

Log "Gerando/atualizando $EnvFile"
Set-EnvVar "DB_PORT" $DbPort
Set-EnvVar "REDIS_PORT" $RedisPort
Set-EnvVar "S3_PORT" $S3Port
Set-EnvDefault "POSTGRES_ADMIN_USER" "postgres"
if (-not (Test-EnvVar "POSTGRES_ADMIN_PASSWORD")) { Set-EnvVar "POSTGRES_ADMIN_PASSWORD" (New-Secret) }

Log "Gerando $InfraCompose"
$compose = @'
services:
  postgres:
    image: postgres:16-alpine
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
      - ./data/postgres:/var/lib/postgresql/data
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

networks:
  shared_net:
    external: true
    name: shared_net
'@
Write-LfFile $InfraCompose ($compose -replace "__PREFIX__", $InfraPrefix)

Log "Criando rede shared_net (se ainda não existir)"
docker network inspect shared_net *> $null
if ($LASTEXITCODE -ne 0) { docker network create shared_net | Out-Null }

Log "Subindo infra (Postgres, Redis, SeaweedFS)"
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

Write-Host @"

✔ Infra pronta (${InfraPrefix}_postgres, ${InfraPrefix}_redis, ${InfraPrefix}_seaweedfs).
  Agora instale cada loja com install-tenant.ps1, numa pasta própria por loja.
"@
