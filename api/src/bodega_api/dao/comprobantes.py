from collections.abc import Sequence
from typing import Any

from psycopg import Connection
from psycopg.rows import dict_row


def create_comprobante(
    connection: Connection,
    *,
    id_cliente: int,
    id_sala: int,
    renglones: Sequence[dict[str, int]],
) -> dict[str, Any]:
    with connection.cursor(row_factory=dict_row) as cursor:
        cursor.execute(
            """
            INSERT INTO comprobante
                (id_cliente, id_sala, fecha, subtotal, descuento, total)
            VALUES (%s, %s, CURRENT_TIMESTAMP, 0, 0, 0)
            RETURNING nro_comprobante
            """,
            (id_cliente, id_sala),
        )
        nro_comprobante = cursor.fetchone()["nro_comprobante"]
        for renglon in renglones:
            cursor.execute(
                """
                INSERT INTO renglon_comprobante
                    (nro_comprobante, cod_vino, cantidad,
                     precio_unitario, descuento, subtotal)
                SELECT %s, cod_vino, %s, precio, 0, 0
                  FROM vino
                 WHERE cod_vino = %s AND activo = TRUE
                RETURNING cod_vino, cantidad, precio_unitario, descuento, subtotal
                """,
                (nro_comprobante, renglon["cantidad"], renglon["cod_vino"]),
            )
            if cursor.fetchone() is None:
                raise ValueError(f"El vino {renglon['cod_vino']} no existe.")
        return get_comprobante(connection, nro_comprobante)


def get_comprobante(
    connection: Connection,
    nro_comprobante: int,
) -> dict[str, Any] | None:
    with connection.cursor(row_factory=dict_row) as cursor:
        cursor.execute(
            """
            SELECT nro_comprobante, id_cliente, id_sala, fecha,
                   subtotal, descuento, total
              FROM comprobante
             WHERE nro_comprobante = %s
            """,
            (nro_comprobante,),
        )
        header = cursor.fetchone()
        if header is None:
            return None
        cursor.execute(
            """
            SELECT cod_vino, cantidad, precio_unitario, descuento, subtotal
              FROM renglon_comprobante
             WHERE nro_comprobante = %s
             ORDER BY cod_vino
            """,
            (nro_comprobante,),
        )
        header["renglones"] = cursor.fetchall()
        return header
