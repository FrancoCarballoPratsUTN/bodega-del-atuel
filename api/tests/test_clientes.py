from fastapi.testclient import TestClient

from bodega_api.main import app
from bodega_api.services.errors import NotFoundError


class ClientCursor:
    def __init__(self, row):
        self.row = row

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        return False

    def execute(self, query, parameters):
        self.query = query
        self.parameters = parameters

    def fetchall(self):
        return [self.row] if self.row else []

    def fetchone(self):
        return self.row


class ClientConnection:
    def __init__(self, row):
        self.row = row

    def cursor(self, **kwargs):
        return ClientCursor(self.row)

    def transaction(self):
        class TransactionContext:
            def __enter__(self):
                return self

            def __exit__(self, exc_type, exc_value, traceback):
                return False

        return TransactionContext()


class ClientPool:
    def __init__(self, row):
        self.row = row

    def close(self):
        pass

    def connection(self):
        pool = self

        class ConnectionContext:
            def __enter__(self):
                return ClientConnection(pool.row)

            def __exit__(self, exc_type, exc_value, traceback):
                return False

        return ConnectionContext()


def test_list_clientes_returns_items(monkeypatch):
    monkeypatch.setattr(
        "bodega_api.db._pool",
        ClientPool({"id_cliente": 1, "nombre_razon_social": "Cliente 1"}),
    )

    with TestClient(app) as client:
        response = client.get("/clientes")

    assert response.status_code == 200
    assert response.json()["items"][0]["id_cliente"] == 1


def test_list_clientes_forwards_search_term(monkeypatch):
    captured: dict[str, object] = {}

    def fake_list_clientes(limit, offset, busqueda=None):
        captured.update(limit=limit, offset=offset, busqueda=busqueda)
        return []

    monkeypatch.setattr(
        "bodega_api.services.clientes.list_clientes",
        fake_list_clientes,
    )

    with TestClient(app) as client:
        response = client.get(
            "/clientes",
            params={"busqueda": "Atuel", "pagina": 2, "por_pagina": 10},
        )

    assert response.status_code == 200
    assert captured == {"limit": 10, "offset": 10, "busqueda": "Atuel"}


def test_get_cliente_not_found(monkeypatch):
    def _raise(id_cliente):
        raise NotFoundError("Cliente no encontrado.")

    monkeypatch.setattr("bodega_api.services.clientes.get_cliente", _raise)

    with TestClient(app) as client:
        response = client.get("/clientes/999")

    assert response.status_code == 404
    assert response.json() == {"error": "Cliente no encontrado."}


def test_create_cliente_success(monkeypatch):
    monkeypatch.setattr(
        "bodega_api.services.clientes.create_cliente",
        lambda data: {"id_cliente": 10, **data},
    )

    payload = {
        "cp_localidad": 5500,
        "nombre_razon_social": "Nuevo Cliente",
        "tipo_doc": "CUIT",
        "nro_doc": "30123456789",
        "direccion": "Av San Martin 123",
        "fecha_alta": "2026-01-01",
        "descuento": 10.0,
        "tipo_cliente": "Socio",
    }
    with TestClient(app) as client:
        response = client.post("/clientes", json=payload)

    assert response.status_code == 201
    assert response.json()["id_cliente"] == 10


def test_delete_cliente_success(monkeypatch):
    monkeypatch.setattr(
        "bodega_api.services.clientes.delete_cliente", lambda id_c: None
    )

    with TestClient(app) as client:
        response = client.delete("/clientes/10")

    assert response.status_code == 204


def test_delete_cliente_not_found(monkeypatch):
    def _raise(id_c):
        raise NotFoundError("Cliente no encontrado.")

    monkeypatch.setattr("bodega_api.services.clientes.delete_cliente", _raise)

    with TestClient(app) as client:
        response = client.delete("/clientes/999")

    assert response.status_code == 404
    assert response.json() == {"error": "Cliente no encontrado."}
