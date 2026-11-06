"""Demostración de concurrencia sobre la última botella de una sala.

Dos conexiones intentan vender simultáneamente la única unidad disponible del
vino 1 en la sala 1. El script sirve para comparar el comportamiento real del
trigger `trg_renglon_validar_stock` (que usa `FOR UPDATE`) contra una variante
sin bloqueo.

Uso dentro del contenedor de la API:

    docker compose exec -T api python - with-lock < tests/concurrencia_demo.py
    docker compose exec -T api python - without-lock < tests/concurrencia_demo.py

La variante `without-lock` requiere que el runner haya reemplazado el trigger
por `trg_validar_stock_venta_sin_lock`. Ver `tests/run_concurrencia.sh`.
"""

import os
import sys
import threading

import psycopg

SALA = 1
VINO = 1
CLIENTE_A = 1
CLIENTE_B = 3
MODE = sys.argv[1] if len(sys.argv) > 1 else "with-lock"

CONNINFO = (
    f"host={os.environ['BDA_DATABASE_HOST']} "
    f"port={os.environ['BDA_DATABASE_PORT']} "
    f"dbname={os.environ['BDA_DATABASE_NAME']} "
    f"user={os.environ['BDA_DATABASE_USER']} "
    f"password={os.environ['BDA_DATABASE_PASSWORD']}"
)

barrier = threading.Barrier(2)
results: dict[str, tuple] = {}


def worker(name: str, id_cliente: int) -> None:
    connection = psycopg.connect(CONNINFO, autocommit=False)
    try:
        barrier.wait()
        with connection.transaction():
            precio = connection.execute(
                "SELECT precio FROM vino WHERE cod_vino = %s", (VINO,)
            ).fetchone()[0]
            nro = connection.execute(
                """
                INSERT INTO comprobante
                    (id_cliente, id_sala, fecha, subtotal, descuento, total)
                VALUES (%s, %s, CURRENT_TIMESTAMP, 0, 0, 0)
                RETURNING nro_comprobante
                """,
                (id_cliente, SALA),
            ).fetchone()[0]
            connection.execute(
                """
                INSERT INTO renglon_comprobante
                    (nro_comprobante, cod_vino, cantidad,
                     precio_unitario, descuento, subtotal)
                VALUES (%s, %s, 1, %s, 0, 0)
                """,
                (nro, VINO, precio),
            )
        results[name] = ("COMMIT", f"comprobante={nro}")
    except Exception as error:  # noqa: BLE001 - se informa el error real
        results[name] = (
            "ROLLBACK",
            f"SQLSTATE={getattr(error, 'sqlstate', '?')}",
            str(error).splitlines()[0],
        )
    finally:
        connection.close()


def setup(connection: psycopg.Connection) -> tuple[int, int]:
    original = connection.execute(
        "SELECT cantidad FROM stock_sala WHERE id_sala = %s AND cod_vino = %s",
        (SALA, VINO),
    ).fetchone()
    baseline = connection.execute(
        "SELECT COALESCE(MAX(nro_comprobante), 0) FROM comprobante"
    ).fetchone()[0]
    connection.execute(
        """
        INSERT INTO stock_sala (id_sala, cod_vino, cantidad)
        VALUES (%s, %s, 1)
        ON CONFLICT (id_sala, cod_vino) DO UPDATE SET cantidad = 1
        """,
        (SALA, VINO),
    )
    connection.commit()
    return (original[0] if original else 0), baseline


def cleanup(connection: psycopg.Connection, original: int, baseline: int) -> None:
    # Primero los renglones: el trigger de venta necesita la cabecera viva
    # para saber a qué sala restituir el stock.
    connection.execute(
        "DELETE FROM renglon_comprobante WHERE nro_comprobante > %s", (baseline,)
    )
    connection.execute(
        "DELETE FROM comprobante WHERE nro_comprobante > %s", (baseline,)
    )
    connection.execute(
        """
        INSERT INTO stock_sala (id_sala, cod_vino, cantidad)
        VALUES (%s, %s, %s)
        ON CONFLICT (id_sala, cod_vino) DO UPDATE SET cantidad = EXCLUDED.cantidad
        """,
        (SALA, VINO, original),
    )
    connection.commit()


def main() -> None:
    admin = psycopg.connect(CONNINFO, autocommit=False)
    original, baseline = setup(admin)

    print(f"modo={MODE} sala={SALA} vino={VINO} stock_inicial=1")
    thread_a = threading.Thread(target=worker, args=("sesion_A", CLIENTE_A))
    thread_b = threading.Thread(target=worker, args=("sesion_B", CLIENTE_B))
    thread_a.start()
    thread_b.start()
    thread_a.join()
    thread_b.join()

    for name in ("sesion_A", "sesion_B"):
        print(f"{name}: {' | '.join(results[name])}")

    stock_final = admin.execute(
        "SELECT cantidad FROM stock_sala WHERE id_sala = %s AND cod_vino = %s",
        (SALA, VINO),
    ).fetchone()[0]
    ventas = admin.execute(
        "SELECT count(*) FROM comprobante WHERE nro_comprobante > %s", (baseline,)
    ).fetchone()[0]
    print(f"stock_final={stock_final} comprobantes_confirmados={ventas}")

    cleanup(admin, original, baseline)
    admin.close()


if __name__ == "__main__":
    main()
