#requires -Version 5.1
<#
.SYNOPSIS
    Ejecuta las migraciones y la suite de pruebas SQL de Bodegas del Atuel.
.DESCRIPTION
    Crea un contenedor PostgreSQL limpio, aplica las migraciones db/migrations/,
    ejecuta tests/db_tests.sql y reporta el resultado.
    Devuelve codigo de salida distinto de 0 si hay pruebas fallidas.
.EXAMPLE
    pwsh -File tests/run_tests.ps1
.EXAMPLE
    pwsh -File tests/run_tests.ps1 -KeepContainer
#>
[CmdletBinding()]
param(
    [string]$Container = "bda_test_run",
    [string]$Image = "postgres:16",
    [string]$DbName = "bodega",
    [string]$DbUser = "postgres",
    [string]$DbPass = "test",
    [int]$WaitSeconds = 15,
    [switch]$KeepContainer
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$migDir = Join-Path $repoRoot "db\migrations"
$testFile = Join-Path $repoRoot "tests\db_tests.sql"

Write-Host "=== Bodegas del Atuel - Suite de pruebas SQL ===" -ForegroundColor Cyan
Write-Host "Repo: $repoRoot"
Write-Host "Migraciones: $migDir"
Write-Host "Tests: $testFile"

if (-not (Test-Path $testFile)) { throw "No se encuentra $testFile" }
if (-not (Test-Path $migDir)) { throw "No se encuentra $migDir" }

# Limpiar contenedor previo
$existing = docker ps -a --filter "name=^/$Container$" --format "{{.Names}}" 2>$null
if ($existing) {
    Write-Host "Eliminando contenedor previo $Container..."
    docker rm -f $Container | Out-Null
}

Write-Host "Levantando PostgreSQL ($Image)..."
docker run -d --name $Container -e POSTGRES_PASSWORD=$DbPass -e POSTGRES_DB=$DbName $Image | Out-Null

Write-Host "Esperando a PostgreSQL ($WaitSeconds s)..."
Start-Sleep -Seconds $WaitSeconds

# Verificar que este listo
$ready = $false
for ($i = 0; $i -lt 30; $i++) {
    docker exec $Container pg_isready -U $DbUser 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { $ready = $true; break }
    Start-Sleep -Seconds 2
}
if (-not $ready) { throw "PostgreSQL no respondió a tiempo" }
Write-Host "PostgreSQL listo." -ForegroundColor Green

# Copiar archivos
Write-Host "Copiando migraciones..."
docker exec $Container mkdir -p /mig /tests | Out-Null
docker cp "$migDir/." "${Container}:/mig/" | Out-Null
docker cp "$testFile" "${Container}:/tests/db_tests.sql" | Out-Null

# Aplicar migraciones
$migrations = @('001_esquema.sql','002_constraints.sql','003_funciones.sql','004_procedimientos.sql','005_triggers.sql','006_vistas.sql','007_roles.sql')
Write-Host "`n=== Aplicando migraciones ===" -ForegroundColor Cyan
foreach ($m in $migrations) {
    Write-Host "  -> $m"
    docker exec $Container psql -U $DbUser -d $DbName -v ON_ERROR_STOP=1 -f "/mig/$m" 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "FALLO al aplicar $m" -ForegroundColor Red
        if (-not $KeepContainer) { docker rm -f $Container | Out-Null }
        exit 1
    }
}
Write-Host "Migraciones aplicadas correctamente." -ForegroundColor Green

# Ejecutar pruebas
Write-Host "`n=== Ejecutando suite de pruebas ===" -ForegroundColor Cyan
docker exec $Container psql -U $DbUser -d $DbName -v ON_ERROR_STOP=1 -f "/tests/db_tests.sql"
$testExit = $LASTEXITCODE

Write-Host "`n=== Resultado ===" -ForegroundColor Cyan
if ($testExit -eq 0) {
    Write-Host "TODAS LAS PRUEBAS PASARON" -ForegroundColor Green
} else {
    Write-Host "HAY PRUEBAS FALLIDAS (exit code: $testExit)" -ForegroundColor Red
}

if (-not $KeepContainer) {
    Write-Host "`nEliminando contenedor $Container..."
    docker rm -f $Container | Out-Null
} else {
    Write-Host "`nContenedor $Container mantenido (-KeepContainer). Conectarse con:" -ForegroundColor Yellow
    Write-Host "  docker exec -it $Container psql -U $DbUser -d $DbName"
}

exit $testExit
