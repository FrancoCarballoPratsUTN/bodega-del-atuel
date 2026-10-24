import os
from contextlib import contextmanager

import psycopg
import pytest
from fastapi.testclient import TestClient
from psycopg.rows import dict_row

from bodega_api import db as db_module
from bodega_api.main import app

TEST_DATABASE = {
    "host": os.getenv("BDA_DATABASE_HOST", "localhost"),
    "port": int(os.getenv("BDA_DATABASE_PORT", "5432")),
    "dbname": os.getenv("BDA_DATABASE_NAME", "bodega_del_atuel"),
    "user": os.getenv("BDA_DATABASE_USER", "rol_api_lectura_escritura"),
    "password": os.getenv("BDA_DATABASE_PASSWORD", "api_password_secreta"),
    "connect_timeout": 5,
}


class StaticPool:
    """Pool mínimo que entrega siempre la conexión de prueba."""

    def __init__(self, connection):
        self._connection = connection

    @contextmanager
    def connection(self):
        yield self._connection

    def close(self):
        pass


@pytest.fixture(scope="session")
def database_connection():
    try:
        connection = psycopg.connect(
            **TEST_DATABASE,
            autocommit=False,
            row_factory=dict_row,
        )
        connection.execute("SELECT 1")
    except Exception as error:  # pragma: no cover - depende del entorno
        pytest.skip(f"PostgreSQL no disponible para pruebas de integración: {error}")

    yield connection
    connection.rollback()
    connection.close()


@pytest.fixture
def db(database_connection):
    database_connection.rollback()
    database_connection.execute("SELECT 1")
    yield database_connection
    database_connection.rollback()


@pytest.fixture
def api_client(db, monkeypatch):
    monkeypatch.setattr(db_module, "_pool", StaticPool(db))
    with TestClient(app) as client:
        yield client
