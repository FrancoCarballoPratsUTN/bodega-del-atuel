#!/usr/bin/env bash
# Ejecuta tests/db_tests.sql sobre una base descartable creada desde cero.
#
# Por defecto levanta un contenedor PostgreSQL temporal con nombre único y lo
# elimina al terminar, así no depende de ningún contenedor en particular.
#
# Para reutilizar un contenedor ya existente:
#   BDA_TEST_DB_CONTAINER=<nombre> BDA_TEST_DB_ADMIN_USER=<usuario> ./tests/run_db_tests.sh
#
# Variables opcionales:
#   BDA_TEST_DB_CONTAINER   Nombre del contenedor a reutilizar (si se omite, se crea uno).
#   BDA_TEST_DB_IMAGE       Imagen a usar al crear el contenedor (default: postgres:17).
#   BDA_TEST_DB_ADMIN_USER  Usuario administrador de la base (default: postgres).
#   BDA_TEST_DB_PASSWORD    Password del usuario administrador (default: test).
#   BDA_TEST_DB_NAME        Nombre de la base de pruebas (default: bodega_db_tests).
#   BDA_TEST_DB_WAIT        Segundos a esperar a que PostgreSQL esté listo (default: 90).
#   BDA_TEST_DB_KEEP=1      Conservar el contenedor temporal al terminar.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTAINER="${BDA_TEST_DB_CONTAINER:-}"
IMAGE="${BDA_TEST_DB_IMAGE:-postgres:17}"
ADMIN_USER="${BDA_TEST_DB_ADMIN_USER:-postgres}"
DB_PASS="${BDA_TEST_DB_PASSWORD:-test}"
DB_NAME="${BDA_TEST_DB_NAME:-bodega_db_tests}"
WAIT_SECONDS="${BDA_TEST_DB_WAIT:-90}"
KEEP_CONTAINER="${BDA_TEST_DB_KEEP:-0}"

# Contraseñas efímeras para la base descartable. No se versionan.
BDA_OWNER_PASSWORD="${BDA_OWNER_PASSWORD:-$(openssl rand -hex 16)}"
BDA_DATABASE_PASSWORD="${BDA_DATABASE_PASSWORD:-$(openssl rand -hex 16)}"
BDA_REPORTES_PASSWORD="${BDA_REPORTES_PASSWORD:-$(openssl rand -hex 16)}"
export BDA_OWNER_PASSWORD BDA_DATABASE_PASSWORD BDA_REPORTES_PASSWORD

OWN_CONTAINER=0
if [[ -z "$CONTAINER" ]]; then
    CONTAINER="bda_test_$$"
    OWN_CONTAINER=1
fi

cleanup() {
    if (( OWN_CONTAINER == 1 )); then
        if [[ "$KEEP_CONTAINER" == "1" ]]; then
            echo "Contenedor conservado: $CONTAINER"
        else
            docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
        fi
    fi
}
trap cleanup EXIT

wait_for_db() {
    local deadline=$((SECONDS + WAIT_SECONDS))
    until docker exec "$CONTAINER" pg_isready -U "$ADMIN_USER" -d postgres >/dev/null 2>&1; do
        if [[ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null || true)" != "true" ]]; then
            echo "El contenedor $CONTAINER no está corriendo. Logs:" >&2
            docker logs "$CONTAINER" >&2 2>&1 || true
            exit 1
        fi
        if (( SECONDS >= deadline )); then
            echo "PostgreSQL no respondió en ${WAIT_SECONDS}s. Logs:" >&2
            docker logs "$CONTAINER" >&2 2>&1 || true
            exit 1
        fi
        sleep 1
    done
}

if (( OWN_CONTAINER == 1 )); then
    docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
    echo "Levantando PostgreSQL temporal ($IMAGE) en $CONTAINER..."
    docker run -d --name "$CONTAINER" \
        -e POSTGRES_USER="$ADMIN_USER" \
        -e POSTGRES_PASSWORD="$DB_PASS" \
        "$IMAGE" >/dev/null
fi

echo "Esperando a que PostgreSQL esté listo..."
wait_for_db

docker exec "$CONTAINER" dropdb -U "$ADMIN_USER" --if-exists "$DB_NAME"
docker exec "$CONTAINER" createdb -U "$ADMIN_USER" "$DB_NAME"

shopt -s nullglob
migrations=("$ROOT"/db/migrations/*.sql)
if (( ${#migrations[@]} == 0 )); then
    echo "No se encontraron migraciones en $ROOT/db/migrations." >&2
    exit 1
fi

echo "Aplicando migraciones..."
for migration in "${migrations[@]}"; do
    name="$(basename "$migration")"
    echo "  -> $name"
    docker exec -i \
        -e BDA_OWNER_PASSWORD="$BDA_OWNER_PASSWORD" \
        -e BDA_DATABASE_PASSWORD="$BDA_DATABASE_PASSWORD" \
        -e BDA_REPORTES_PASSWORD="$BDA_REPORTES_PASSWORD" \
        "$CONTAINER" psql \
        -U "$ADMIN_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 -q < "$migration"
done

# Verificar que los roles se crearon correctamente.
echo "Verificando roles..."
for rol in propietario_base_datos rol_api_lectura_escritura rol_reportes_solo_lectura; do
    if ! docker exec "$CONTAINER" psql -U "$ADMIN_USER" -d "$DB_NAME" -tAc \
        "SELECT 1 FROM pg_roles WHERE rolname = '$rol'" | grep -q 1; then
        echo "ERROR: el rol $rol no se creó." >&2
        exit 1
    fi
done
echo "Roles verificados: propietario_base_datos, rol_api_lectura_escritura, rol_reportes_solo_lectura."

echo "Ejecutando tests/db_tests.sql..."
docker exec -i "$CONTAINER" psql \
    -U "$ADMIN_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 < "$ROOT/tests/db_tests.sql"