from collections.abc import Sequence
from typing import Any

from bodega_api import db
from bodega_api.dao import clientes as clientes_dao
from bodega_api.services.errors import NotFoundError


def list_clientes(
    limit: int,
    offset: int,
    busqueda: str | None = None,
) -> Sequence[dict[str, Any]]:
    normalized_search = busqueda.strip() if busqueda else None
    with db.connection() as connection:
        return clientes_dao.list_clientes(
            connection,
            limit,
            offset,
            normalized_search or None,
        )


def get_cliente(id_cliente: int) -> dict[str, Any]:
    with db.connection() as connection:
        cliente = clientes_dao.get_cliente(connection, id_cliente)
    if cliente is None:
        raise NotFoundError("Cliente no encontrado.")
    return cliente


def create_cliente(data: dict[str, Any]) -> dict[str, Any]:
    with db.transaction() as connection:
        return clientes_dao.create_cliente(connection, data)


def update_cliente(id_cliente: int, data: dict[str, Any]) -> dict[str, Any]:
    with db.transaction() as connection:
        cliente = clientes_dao.update_cliente(connection, id_cliente, data)
        if cliente is None:
            raise NotFoundError("Cliente no encontrado.")
        return cliente


def delete_cliente(id_cliente: int) -> None:
    with db.transaction() as connection:
        deleted = clientes_dao.deactivate_cliente(connection, id_cliente)
        if not deleted:
            raise NotFoundError("Cliente no encontrado.")
