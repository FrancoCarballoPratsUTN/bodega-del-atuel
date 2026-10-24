from collections.abc import Sequence
from typing import Any

from psycopg import Connection
from psycopg.rows import dict_row


def list_clientes(
    connection: Connection,
    limit: int,
    offset: int,
) -> Sequence[dict[str, Any]]:
    query = """
        SELECT c.id_cliente, c.cp_localidad, c.nombre_razon_social, c.tipo_doc,
               c.nro_doc, c.direccion, c.fecha_alta, c.descuento,
               c.tipo_cliente, c.activo,
               d.zona_cobertura, d.nro_habilitacion, e.pais_destino
          FROM cliente c
          LEFT JOIN distribuidor d ON d.id_cliente = c.id_cliente
          LEFT JOIN exportador e ON e.id_cliente = c.id_cliente
         WHERE c.activo = TRUE
         ORDER BY c.id_cliente
         LIMIT %s OFFSET %s
    """
    with connection.cursor(row_factory=dict_row) as cursor:
        cursor.execute(query, (limit, offset))
        return cursor.fetchall()


def get_cliente(connection: Connection, id_cliente: int) -> dict[str, Any] | None:
    query = """
        SELECT c.id_cliente, c.cp_localidad, c.nombre_razon_social, c.tipo_doc,
               c.nro_doc, c.direccion, c.fecha_alta, c.descuento,
               c.tipo_cliente, c.activo,
               d.zona_cobertura, d.nro_habilitacion, e.pais_destino
          FROM cliente c
          LEFT JOIN distribuidor d ON d.id_cliente = c.id_cliente
          LEFT JOIN exportador e ON e.id_cliente = c.id_cliente
         WHERE c.id_cliente = %s AND c.activo = TRUE
    """
    with connection.cursor(row_factory=dict_row) as cursor:
        cursor.execute(query, (id_cliente,))
        return cursor.fetchone()


def create_cliente(connection: Connection, data: dict[str, Any]) -> dict[str, Any]:
    with connection.cursor(row_factory=dict_row) as cursor:
        cursor.execute(
            """
            INSERT INTO cliente (
                cp_localidad, nombre_razon_social, tipo_doc, nro_doc,
                direccion, fecha_alta, descuento, tipo_cliente
            ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
            RETURNING id_cliente
            """,
            (
                data["cp_localidad"],
                data["nombre_razon_social"],
                data["tipo_doc"],
                data["nro_doc"],
                data["direccion"],
                data["fecha_alta"],
                data["descuento"],
                data["tipo_cliente"],
            ),
        )
        id_cliente = cursor.fetchone()["id_cliente"]

    _insert_subtype(connection, id_cliente, data)
    return get_cliente(connection, id_cliente)


def update_cliente(
    connection: Connection,
    id_cliente: int,
    data: dict[str, Any],
) -> dict[str, Any] | None:
    with connection.cursor(row_factory=dict_row) as cursor:
        cursor.execute(
            "SELECT tipo_cliente FROM cliente "
            "WHERE id_cliente = %s AND activo = TRUE FOR UPDATE",
            (id_cliente,),
        )
        current = cursor.fetchone()
        if current is None:
            return None
        previous_type = current["tipo_cliente"]

        cursor.execute(
            """
            UPDATE cliente
               SET cp_localidad = %s,
                   nombre_razon_social = %s,
                   tipo_doc = %s,
                   nro_doc = %s,
                   direccion = %s,
                   fecha_alta = %s,
                   descuento = %s,
                   tipo_cliente = %s
             WHERE id_cliente = %s AND activo = TRUE
            """,
            (
                data["cp_localidad"],
                data["nombre_razon_social"],
                data["tipo_doc"],
                data["nro_doc"],
                data["direccion"],
                data["fecha_alta"],
                data["descuento"],
                data["tipo_cliente"],
                id_cliente,
            ),
        )

    if previous_type != data["tipo_cliente"]:
        _delete_subtype(connection, id_cliente, previous_type)
        _insert_subtype(connection, id_cliente, data)
    else:
        _update_subtype(connection, id_cliente, data)

    return get_cliente(connection, id_cliente)


def deactivate_cliente(connection: Connection, id_cliente: int) -> bool:
    with connection.cursor() as cursor:
        cursor.execute(
            "UPDATE cliente SET activo = FALSE WHERE id_cliente = %s AND activo = TRUE",
            (id_cliente,),
        )
        return cursor.rowcount == 1


def _insert_subtype(
    connection: Connection,
    id_cliente: int,
    data: dict[str, Any],
) -> None:
    with connection.cursor() as cursor:
        if data["tipo_cliente"] == "Distribuidor":
            cursor.execute(
                "INSERT INTO distribuidor "
                "(id_cliente, zona_cobertura, nro_habilitacion) "
                "VALUES (%s, %s, %s)",
                (
                    id_cliente,
                    data["zona_cobertura"],
                    data["nro_habilitacion"],
                ),
            )
        elif data["tipo_cliente"] == "Exportador":
            cursor.execute(
                "INSERT INTO exportador (id_cliente, pais_destino) VALUES (%s, %s)",
                (id_cliente, data["pais_destino"]),
            )


def _update_subtype(
    connection: Connection,
    id_cliente: int,
    data: dict[str, Any],
) -> None:
    with connection.cursor() as cursor:
        if data["tipo_cliente"] == "Distribuidor":
            cursor.execute(
                "INSERT INTO distribuidor "
                "(id_cliente, zona_cobertura, nro_habilitacion) "
                "VALUES (%s, %s, %s) "
                "ON CONFLICT (id_cliente) DO UPDATE SET "
                "zona_cobertura = EXCLUDED.zona_cobertura, "
                "nro_habilitacion = EXCLUDED.nro_habilitacion",
                (
                    id_cliente,
                    data["zona_cobertura"],
                    data["nro_habilitacion"],
                ),
            )
        elif data["tipo_cliente"] == "Exportador":
            cursor.execute(
                "INSERT INTO exportador (id_cliente, pais_destino) VALUES (%s, %s) "
                "ON CONFLICT (id_cliente) DO UPDATE SET "
                "pais_destino = EXCLUDED.pais_destino",
                (id_cliente, data["pais_destino"]),
            )


def _delete_subtype(
    connection: Connection,
    id_cliente: int,
    tipo_cliente: str,
) -> None:
    with connection.cursor() as cursor:
        if tipo_cliente == "Distribuidor":
            cursor.execute(
                "DELETE FROM distribuidor WHERE id_cliente = %s",
                (id_cliente,),
            )
        elif tipo_cliente == "Exportador":
            cursor.execute(
                "DELETE FROM exportador WHERE id_cliente = %s",
                (id_cliente,),
            )
