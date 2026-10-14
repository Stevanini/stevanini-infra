<#
.SYNOPSIS
  Equivalente PowerShell do s3-add-app.sh — cria (ou rotaciona) a access key de UM app
  no SeaweedFS, com acesso só ao bucket dele.
.DESCRIPTION
  Rode na pasta da infra (onde está o .env). INFRA_PREFIX (padrão infra) deve ser o mesmo do install-infra.ps1.
.EXAMPLE
  .\s3-add-app.ps1 -App loja1 -Bucket loja1-media
#>
param(
  [Parameter(Mandatory)][string]$App,
  [string]$Bucket = ""
)
$ErrorActionPreference = "Stop"
if (-not $Bucket) { $Bucket = $App }
if ($App -notmatch '^[a-z0-9][a-z0-9_-]*$') { throw "Nome do app só aceita a-z, 0-9, '-' e '_'." }
if ($Bucket -notmatch '^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$') { throw "Nome de bucket inválido (3-63 chars, minúsculas, números, '.' e '-')." }

function Get-EnvVar($key) {
  $line = Get-Content ".env" -ErrorAction SilentlyContinue | Where-Object { $_ -like "$key=*" } | Select-Object -Last 1
  if ($line) { $line.Substring($key.Length + 1) } else { "" }
}
function New-Hex($bytes) { -join ((1..$bytes) | ForEach-Object { '{0:x2}' -f (Get-Random -Maximum 256) }) }

$prefix = if ($env:INFRA_PREFIX) { $env:INFRA_PREFIX } else { "infra" }
$container = "${prefix}_seaweedfs"
$adminKey = Get-EnvVar "S3_ACCESS_KEY"; $adminSecret = Get-EnvVar "S3_SECRET_KEY"
if (-not $adminKey -or -not $adminSecret) { throw "S3_ACCESS_KEY/S3_SECRET_KEY não definidos em .env (rode o install-infra.ps1)." }
docker inspect $container *> $null
if ($LASTEXITCODE -ne 0) { throw "Container $container não encontrado." }

$appKey = New-Hex 10; $appSecret = New-Hex 24
$cmds = @(
  "s3.configure -user=admin -access_key=$adminKey -secret_key=$adminSecret -actions=Admin -apply",
  "s3.bucket.create -name $Bucket",
  "s3.configure -user=$App -access_key=$appKey -secret_key=$appSecret -buckets=$Bucket -actions=Read,Write,List,Tagging -apply"
) -join "`n"
$cmds | docker exec -i $container weed shell -master=localhost:9333 | Out-Null

Write-Host @"

✔ App '$App' com acesso apenas ao bucket '$Bucket'. Guarde as chaves (não são mostradas de novo):
  S3_ENDPOINT=http://${container}:8333   (dentro da shared_net; path-style ligado)
  S3_BUCKET=$Bucket
  S3_ACCESS_KEY=$appKey
  S3_SECRET_KEY=$appSecret
"@
