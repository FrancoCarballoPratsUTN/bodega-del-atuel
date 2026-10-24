"""Servicio de verificación de conectividad y estado."""

from bodega_api import db
from bodega_api.dao import healthy as healthy_dao
from bodega_api.services.errors import ServiceUnavailableError


def check_database() -> None:
    try:
        with db.connection() as connection:
            healthy_dao.ping(connection)
    except Exception as error:
        raise ServiceUnavailableError("La base de datos no está disponible.") from error
