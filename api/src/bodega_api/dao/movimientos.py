from typing import Any

from psycopg import Connection
from psycopg.rows import dict_row


def create_transferencia(connection: Connection, id_sala: int) -> dict[str, Any]:
    return _create_document(
        connection,
        """
        INSERT INTO transferencia (id_sala, fecha_confeccion, estado)
        VALUES (%s, CURRENT_DATE, 'en_confeccion')
        RETURNING nro_transferencia AS codigo, id_sala, fecha_confeccion, estado
        """,
        (id_sala,),
    )


def create_ingreso(
    connection: Connection,
    cod_transportista: int,
    cuit_bodega: str,
) -> dict[str, Any]:
    return _create_document(
        connection,
        """
        INSERT INTO ingreso (cod_transportista, cuit_bodega, fecha, estado)
        VALUES (%s, %s, CURRENT_TIMESTAMP, 'en_confeccion')
        RETURNING cod_ingreso AS codigo, cod_transportista, cuit_bodega, fecha, estado
        """,
        (cod_transportista, cuit_bodega),
    )


def add_transferencia_line(
    connection: Connection,
    codigo: int,
    cod_vino: int,
    cantidad: int,
) -> None:
    _insert_line(
        connection,
        """
        INSERT INTO renglon_transferencia (nro_transferencia, cod_vino, cantidad)
        VALUES (%s, %s, %s)
        """,
        (codigo, cod_vino, cantidad),
    )


def add_ingreso_line(
    connection: Connection,
    codigo: int,
    cod_vino: int,
    cantidad: int,
) -> None:
    _insert_line(
        connection,
        """
        INSERT INTO renglon_ingreso (cod_ingreso, cod_vino, cantidad)
        VALUES (%s, %s, %s)
        """,
        (codigo, cod_vino, cantidad),
    )


def finish_transferencia(connection: Connection, codigo: int) -> bool:
    return _finish_document(
        connection,
        "UPDATE transferencia SET estado = 'terminado' WHERE nro_transferencia = %s",
        codigo,
    )


def finish_ingreso(connection: Connection, codigo: int) -> bool:
    return _finish_document(
        connection,
        "UPDATE ingreso SET estado = 'terminado' WHERE cod_ingreso = %s",
        codigo,
    )


def process_transferencia(connection: Connection, codigo: int) -> None:
    with connection.cursor() as cursor:
        cursor.execute("CALL sp_procesar_transferencia(%s)", (codigo,))


def process_ingreso(connection: Connection, codigo: int) -> None:
    with connection.cursor() as cursor:
        cursor.execute("CALL sp_procesar_ingreso(%s)", (codigo,))


def _create_document(
    connection: Connection,
    query: str,
    parameters: tuple[Any, ...],
) -> dict[str, Any]:
    with connection.cursor(row_factory=dict_row) as cursor:
        cursor.execute(query, parameters)
        return cursor.fetchone()


def _insert_line(
    connection: Connection,
    query: str,
    parameters: tuple[Any, ...],
) -> None:
    with connection.cursor() as cursor:
        cursor.execute(query, parameters)


def _finish_document(connection: Connection, query: str, codigo: int) -> bool:
    with connection.cursor() as cursor:
        cursor.execute(query, (codigo,))
        return cursor.rowcount == 1
