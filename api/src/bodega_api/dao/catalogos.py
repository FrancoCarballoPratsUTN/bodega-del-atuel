from collections.abc import Sequence
from typing import Any

from psycopg import Connection
from psycopg.rows import dict_row


def list_salas(connection: Connection) -> Sequence[dict[str, Any]]:
    return _fetch_all(
        connection,
        """
        SELECT s.id_sala, s.calle, s.numero, s.cp_localidad,
               l.nombre AS localidad, s.dia_cierre, s.activo
          FROM sala_venta s
          JOIN localidad l ON l.cp = s.cp_localidad
         ORDER BY s.id_sala
        """,
    )


def list_cepas(connection: Connection) -> Sequence[dict[str, Any]]:
    return _fetch_all(
        connection,
        """
        SELECT id_cepa, nombre, tipo
          FROM cepa
         ORDER BY nombre, id_cepa
        """,
    )


def list_bodegas(connection: Connection) -> Sequence[dict[str, Any]]:
    return _fetch_all(
        connection,
        """
        SELECT cuit_bodega, razon_social, activo
          FROM bodega
         ORDER BY razon_social, cuit_bodega
        """,
    )


def _fetch_all(
    connection: Connection,
    query: str,
) -> Sequence[dict[str, Any]]:
    with connection.cursor(row_factory=dict_row) as cursor:
        cursor.execute(query)
        return cursor.fetchall()
