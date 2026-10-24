from typing import Any

from bodega_api import db
from bodega_api.dao import movimientos as movimientos_dao
from bodega_api.services.errors import NotFoundError


def create_transferencia(id_sala: int) -> dict[str, Any]:
    with db.transaction() as connection:
        return movimientos_dao.create_transferencia(connection, id_sala)


def add_transferencia_line(codigo: int, cod_vino: int, cantidad: int) -> None:
    with db.transaction() as connection:
        movimientos_dao.add_transferencia_line(connection, codigo, cod_vino, cantidad)


def finish_transferencia(codigo: int) -> None:
    with db.transaction() as connection:
        finished = movimientos_dao.finish_transferencia(connection, codigo)
        if not finished:
            raise NotFoundError("Transferencia no encontrada.")


def process_transferencia(codigo: int) -> None:
    with db.transaction() as connection:
        movimientos_dao.process_transferencia(connection, codigo)


def create_ingreso(cod_transportista: int, cuit_bodega: str) -> dict[str, Any]:
    with db.transaction() as connection:
        return movimientos_dao.create_ingreso(
            connection,
            cod_transportista,
            cuit_bodega,
        )


def add_ingreso_line(codigo: int, cod_vino: int, cantidad: int) -> None:
    with db.transaction() as connection:
        movimientos_dao.add_ingreso_line(connection, codigo, cod_vino, cantidad)


def finish_ingreso(codigo: int) -> None:
    with db.transaction() as connection:
        finished = movimientos_dao.finish_ingreso(connection, codigo)
        if not finished:
            raise NotFoundError("Ingreso no encontrado.")


def process_ingreso(codigo: int) -> None:
    with db.transaction() as connection:
        movimientos_dao.process_ingreso(connection, codigo)
