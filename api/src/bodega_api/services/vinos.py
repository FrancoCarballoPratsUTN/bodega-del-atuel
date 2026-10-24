from collections.abc import Sequence
from typing import Any

from bodega_api import db
from bodega_api.dao import vinos as vinos_dao
from bodega_api.services.errors import NotFoundError


def list_vinos(
    *,
    tipo: str | None,
    cepa: str | None,
    bodega: str | None,
    aniada: int | None,
    limit: int,
    offset: int,
) -> Sequence[dict[str, Any]]:
    with db.connection() as connection:
        return vinos_dao.list_vinos(
            connection,
            tipo=tipo,
            cepa=cepa,
            bodega=bodega,
            aniada=aniada,
            limit=limit,
            offset=offset,
        )


def get_vino(cod_vino: int) -> dict[str, Any]:
    with db.connection() as connection:
        vino = vinos_dao.get_vino(connection, cod_vino)
    if vino is None:
        raise NotFoundError("Vino no encontrado.")
    return vino


def create_vino(data: dict[str, Any]) -> dict[str, Any]:
    with db.transaction() as connection:
        return vinos_dao.create_vino(connection, data)


def update_vino(cod_vino: int, data: dict[str, Any]) -> dict[str, Any]:
    with db.transaction() as connection:
        vino = vinos_dao.update_vino(connection, cod_vino, data)
        if vino is None:
            raise NotFoundError("Vino no encontrado.")
        return vino


def delete_vino(cod_vino: int) -> None:
    with db.transaction() as connection:
        deleted = vinos_dao.deactivate_vino(connection, cod_vino)
        if not deleted:
            raise NotFoundError("Vino no encontrado.")
