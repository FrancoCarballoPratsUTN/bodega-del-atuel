from collections.abc import Sequence
from typing import Any

from bodega_api import db
from bodega_api.dao import reportes as reportes_dao
from bodega_api.services.errors import NotFoundError


def top_vinos() -> Sequence[dict[str, Any]]:
    with db.connection() as connection:
        return reportes_dao.top_vinos(connection)


def ventas_por_sala() -> Sequence[dict[str, Any]]:
    with db.connection() as connection:
        return reportes_dao.ventas_por_sala(connection)


def vinos_sin_stock(id_sala: int) -> Sequence[dict[str, Any]]:
    with db.connection() as connection:
        return reportes_dao.vinos_sin_stock(connection, id_sala)


def transportista_activo() -> Sequence[dict[str, Any]]:
    with db.connection() as connection:
        return reportes_dao.transportista_activo(connection)


def trazabilidad(cod_vino: int) -> dict[str, Any]:
    with db.connection() as connection:
        result = reportes_dao.trazabilidad(connection, cod_vino)
    if result is None:
        raise NotFoundError("Vino no encontrado.")
    return result
