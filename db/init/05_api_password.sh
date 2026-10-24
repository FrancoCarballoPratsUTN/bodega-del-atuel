#!/usr/bin/env bash
set -euo pipefail

: "${BDA_DATABASE_PASSWORD:?BDA_DATABASE_PASSWORD es obligatoria}"

psql -v ON_ERROR_STOP=1 \
  -U "$POSTGRES_USER" \
  -d "$POSTGRES_DB" \
  -v api_password="$BDA_DATABASE_PASSWORD" <<'SQL'
ALTER ROLE rol_api_lectura_escritura PASSWORD :'api_password';
SQL
