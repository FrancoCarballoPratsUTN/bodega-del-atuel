from collections.abc import Sequence
from typing import Any

from psycopg import Connection
from psycopg.rows import dict_row


def list_vinos(
    connection: Connection,
    *,
    tipo: str | None,
    cepa: str | None,
    bodega: str | None,
    aniada: int | None,
    limit: int,
    offset: int,
) -> Sequence[dict[str, Any]]:
    filters = ["v.activo = TRUE"]
    parameters: list[Any] = []

    if tipo is not None:
        filters.append("lower(v.tipo) = lower(%s)")
        parameters.append(tipo)
    if cepa is not None:
        filters.append(
            "EXISTS ("
            "SELECT 1 FROM composicion c "
            "JOIN cepa ce ON ce.id_cepa = c.id_cepa "
            "WHERE c.cod_vino = v.cod_vino AND lower(ce.nombre) = lower(%s))"
        )
        parameters.append(cepa)
    if bodega is not None:
        filters.append("lower(b.razon_social) = lower(%s)")
        parameters.append(bodega)
    if aniada is not None:
        filters.append("v.aniada = %s")
        parameters.append(aniada)

    query = f"""
        SELECT v.cod_vino, v.nombre, v.tipo, v.aniada, v.volumen,
               v.graduacion, v.precio, b.razon_social AS bodega
          FROM vino v
          JOIN bodega b ON b.cuit_bodega = v.cuit_bodega
         WHERE {" AND ".join(filters)}
         ORDER BY v.cod_vino
         LIMIT %s OFFSET %s
    """
    parameters.extend([limit, offset])
    with connection.cursor(row_factory=dict_row) as cursor:
        cursor.execute(query, parameters)
        return cursor.fetchall()


def get_vino(connection: Connection, cod_vino: int) -> dict[str, Any] | None:
    query = """
        SELECT v.cod_vino, v.nombre, v.tipo, v.aniada, v.volumen,
               v.graduacion, v.precio, b.razon_social AS bodega,
               COALESCE(
                   json_agg(
                       DISTINCT jsonb_build_object(
                           'nombre', ce.nombre,
                           'tipo', ce.tipo,
                           'porcentaje', c.porcentaje
                       )
                   ) FILTER (WHERE ce.id_cepa IS NOT NULL),
                   '[]'::json
               ) AS cepas,
               COALESCE(
                   json_agg(
                       DISTINCT jsonb_build_object(
                           'nombre', m.nombre,
                           'temperatura_servicio', m.temp_servicio
                       )
                   ) FILTER (WHERE m.id_maridaje IS NOT NULL),
                   '[]'::json
               ) AS maridajes
          FROM vino v
          JOIN bodega b ON b.cuit_bodega = v.cuit_bodega
          LEFT JOIN composicion c ON c.cod_vino = v.cod_vino
          LEFT JOIN cepa ce ON ce.id_cepa = c.id_cepa
          LEFT JOIN vino_maridaje vm ON vm.cod_vino = v.cod_vino
          LEFT JOIN maridaje m ON m.id_maridaje = vm.id_maridaje
         WHERE v.cod_vino = %s AND v.activo = TRUE
         GROUP BY v.cod_vino, b.razon_social
    """
    with connection.cursor(row_factory=dict_row) as cursor:
        cursor.execute(query, (cod_vino,))
        return cursor.fetchone()


def create_vino(connection: Connection, data: dict[str, Any]) -> dict[str, Any]:
    with connection.cursor(row_factory=dict_row) as cursor:
        cursor.execute(
            """
            INSERT INTO vino (
                cuit_bodega, nombre, tipo, aniada,
                volumen, graduacion, precio
            ) VALUES (%s, %s, %s, %s, %s, %s, %s)
            RETURNING cod_vino
            """,
            (
                data["cuit_bodega"],
                data["nombre"],
                data["tipo"],
                data["aniada"],
                data["volumen"],
                data["graduacion"],
                data["precio"],
            ),
        )
        cod_vino = cursor.fetchone()["cod_vino"]

    _replace_composicion(connection, cod_vino, data["cepas"])
    _replace_maridajes(connection, cod_vino, data["maridajes"])
    _validate_deferred_constraints(connection)
    return get_vino(connection, cod_vino)


def update_vino(
    connection: Connection,
    cod_vino: int,
    data: dict[str, Any],
) -> dict[str, Any] | None:
    with connection.cursor() as cursor:
        cursor.execute(
            """
            UPDATE vino
               SET cuit_bodega = %s,
                   nombre = %s,
                   tipo = %s,
                   aniada = %s,
                   volumen = %s,
                   graduacion = %s,
                   precio = %s
             WHERE cod_vino = %s AND activo = TRUE
            RETURNING cod_vino
            """,
            (
                data["cuit_bodega"],
                data["nombre"],
                data["tipo"],
                data["aniada"],
                data["volumen"],
                data["graduacion"],
                data["precio"],
                cod_vino,
            ),
        )
        updated = cursor.fetchone()

    if updated is None:
        return None

    if data["cepas"] is not None:
        _replace_composicion(connection, cod_vino, data["cepas"])
    if data["maridajes"] is not None:
        _replace_maridajes(connection, cod_vino, data["maridajes"])
    _validate_deferred_constraints(connection)
    return get_vino(connection, cod_vino)


def deactivate_vino(connection: Connection, cod_vino: int) -> bool:
    with connection.cursor() as cursor:
        cursor.execute(
            "UPDATE vino SET activo = FALSE WHERE cod_vino = %s AND activo = TRUE",
            (cod_vino,),
        )
        return cursor.rowcount == 1


def _validate_deferred_constraints(connection: Connection) -> None:
    with connection.cursor() as cursor:
        cursor.execute("SET CONSTRAINTS ALL IMMEDIATE")
        cursor.execute("SET CONSTRAINTS ALL DEFERRED")


def _replace_composicion(
    connection: Connection,
    cod_vino: int,
    cepas: Sequence[dict[str, Any]],
) -> None:
    with connection.cursor() as cursor:
        cursor.execute("DELETE FROM composicion WHERE cod_vino = %s", (cod_vino,))
        if cepas:
            cursor.executemany(
                """
                INSERT INTO composicion (cod_vino, id_cepa, porcentaje)
                VALUES (%s, %s, %s)
                """,
                [(cod_vino, cepa["id_cepa"], cepa["porcentaje"]) for cepa in cepas],
            )


def _replace_maridajes(
    connection: Connection,
    cod_vino: int,
    maridajes: Sequence[int],
) -> None:
    with connection.cursor() as cursor:
        cursor.execute("DELETE FROM vino_maridaje WHERE cod_vino = %s", (cod_vino,))
        if maridajes:
            cursor.executemany(
                "INSERT INTO vino_maridaje (cod_vino, id_maridaje) VALUES (%s, %s)",
                [(cod_vino, id_maridaje) for id_maridaje in maridajes],
            )
