from collections.abc import Sequence
from typing import Any

from bodega_api import db
from bodega_api.dao import comprobantes as comprobantes_dao
from bodega_api.services.errors import NotFoundError, ValidationError


def create_comprobante(
    *,
    id_cliente: int,
    id_sala: int,
    renglones: Sequence[dict[str, int]],
) -> dict[str, Any]:
    with db.transaction() as connection:
        try:
            return comprobantes_dao.create_comprobante(
                connection,
                id_cliente=id_cliente,
                id_sala=id_sala,
                renglones=renglones,
            )
        except ValueError as error:
            raise ValidationError(str(error)) from error


def get_comprobante(nro_comprobante: int) -> dict[str, Any]:
    with db.connection() as connection:
        comprobante = comprobantes_dao.get_comprobante(connection, nro_comprobante)
    if comprobante is None:
        raise NotFoundError("Comprobante no encontrado.")
    return comprobante
