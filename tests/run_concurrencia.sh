#!/usr/bin/env bash
# Demuestra el comportamiento de la última botella con y sin FOR UPDATE.
#
# Requiere el compose principal levantado:
#   docker compose up -d
#
# El modo "without-lock" reemplaza temporalmente el trigger real por una
# variante sin bloqueo, ejecuta la prueba y restaura el trigger original.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ ! -f .env ]]; then
    echo "Falta .env. Copiá .env.example y completá las contraseñas." >&2
    exit 1
fi
set -a
# shellcheck disable=SC1091
. ./.env
set +a

DB_SERVICE="${BDA_CONCURRENCIA_DB_SERVICE:-db}"
DB_USER="${BDA_CONCURRENCIA_DB_USER:-postgresql}"
DB_NAME="${BDA_CONCURRENCIA_DB_NAME:-bodega_del_atuel}"
DB_PASSWORD="${POSTGRES_PASSWORD:?Definí POSTGRES_PASSWORD en .env}"

psql_db() {
    docker compose exec -T -e PGPASSWORD="$DB_PASSWORD" "$DB_SERVICE" \
        psql -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 -q "$@"
}

demo() {
    local mode="$1"
    docker compose exec -T api python - "$mode" < tests/concurrencia_demo.py
}

install_variant() {
    psql_db <<'SQL'
CREATE OR REPLACE FUNCTION trg_validar_stock_venta_sin_lock() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_id_sala INTEGER;
    v_stock INTEGER;
BEGIN
    SELECT id_sala INTO v_id_sala
    FROM comprobante
    WHERE nro_comprobante = NEW.nro_comprobante;

    -- Sin FOR UPDATE: ambas sesiones pueden leer el mismo stock.
    SELECT cantidad INTO v_stock
    FROM stock_sala
    WHERE id_sala = v_id_sala AND cod_vino = NEW.cod_vino;

    -- Ventana deliberada para que las dos sesiones lean antes de escribir.
    PERFORM pg_sleep(1.5);

    v_stock := COALESCE(v_stock, 0);
    IF TG_OP = 'INSERT' AND v_stock < NEW.cantidad THEN
        RAISE EXCEPTION 'Stock insuficiente en la sala % para el vino %. Disponible: %, Solicitado: %',
            v_id_sala, NEW.cod_vino, v_stock, NEW.cantidad;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER trg_renglon_validar_stock ON renglon_comprobante;
CREATE TRIGGER trg_renglon_validar_stock
BEFORE INSERT OR UPDATE ON renglon_comprobante
FOR EACH ROW EXECUTE FUNCTION trg_validar_stock_venta_sin_lock();
SQL
}

restore_original() {
    psql_db <<'SQL'
DROP TRIGGER IF EXISTS trg_renglon_validar_stock ON renglon_comprobante;
CREATE TRIGGER trg_renglon_validar_stock
BEFORE INSERT OR UPDATE ON renglon_comprobante
FOR EACH ROW EXECUTE FUNCTION trg_validar_stock_venta();
DROP FUNCTION IF EXISTS trg_validar_stock_venta_sin_lock();
SQL
}

trap restore_original EXIT

echo "== Con FOR UPDATE (implementación real) =="
demo with-lock

echo
echo "== Sin FOR UPDATE (variante de comparación) =="
install_variant
demo without-lock

echo
echo "Trigger original restaurado."
