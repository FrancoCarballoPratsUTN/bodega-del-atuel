from typing import Any

from bodega_api import db
from bodega_api.dao import catalogos as catalogos_dao


def list_catalogos() -> dict[str, Any]:
    with db.connection() as connection:
        return {
            "salas": list(catalogos_dao.list_salas(connection)),
            "cepas": list(catalogos_dao.list_cepas(connection)),
            "bodegas": list(catalogos_dao.list_bodegas(connection)),
            "tipos_vino": list(catalogos_dao.list_tipos_vino(connection)),
        }
