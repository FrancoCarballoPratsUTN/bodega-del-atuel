#!/usr/bin/env bash
# Ejecuta tests/db_tests.sql sobre una base descartable creada desde cero.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTAINER="${BDA_TEST_DB_CONTAINER:-postgresql}"
ADMIN_USER="${BDA_TEST_DB_ADMIN_USER:-postgresql}"
DB_NAME="${BDA_TEST_DB_NAME:-bodega_db_tests}"

cleanup() {
    docker exec "$CONTAINER" dropdb \
        -U "$ADMIN_USER" --if-exists "$DB_NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker exec "$CONTAINER" dropdb -U "$ADMIN_USER" --if-exists "$DB_NAME"
docker exec "$CONTAINER" createdb -U "$ADMIN_USER" "$DB_NAME"

for migration in \
    db/migrations/001_esquema.sql \
    db/migrations/002_constraints.sql \
    db/migrations/003_funciones.sql \
    db/migrations/004_procedimientos.sql \
    db/migrations/005_triggers.sql \
    db/migrations/006_vistas.sql; do
    docker exec -i "$CONTAINER" psql \
        -U "$ADMIN_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 -q < "$ROOT/$migration"
done

docker exec -i "$CONTAINER" psql \
    -U "$ADMIN_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 < "$ROOT/tests/db_tests.sql"
