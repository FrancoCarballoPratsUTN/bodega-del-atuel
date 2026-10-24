from collections.abc import Iterator
from contextlib import contextmanager

from psycopg import Connection
from psycopg_pool import ConnectionPool

from bodega_api.config import get_settings

_pool: ConnectionPool | None = None


def get_pool() -> ConnectionPool:
    global _pool
    if _pool is None:
        settings = get_settings()
        _pool = ConnectionPool(
            conninfo=settings.database_conninfo,
            min_size=settings.database_pool_min_size,
            max_size=settings.database_pool_max_size,
            open=True,
        )
    return _pool


def close_pool() -> None:
    global _pool
    if _pool is not None:
        _pool.close()
        _pool = None


@contextmanager
def connection() -> Iterator[Connection]:
    """Entrega una conexión del pool para una operación de lectura."""
    with get_pool().connection() as current_connection:
        yield current_connection


@contextmanager
def transaction() -> Iterator[Connection]:
    """Entrega una conexión con una transacción explícita."""
    with (
        get_pool().connection() as current_connection,
        current_connection.transaction(),
    ):
        yield current_connection
