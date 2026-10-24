"""Acceso a datos para verificación de estado de la base de datos."""

from psycopg import Connection


def ping(connection: Connection) -> None:
    connection.execute("SELECT 1")
