from fastapi.testclient import TestClient

from bodega_api.main import app
from bodega_api.services.errors import NotFoundError


class FakeCursor:
    def __init__(self, rows):
        self.rows = rows

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        return False

    def execute(self, query, parameters):
        self.query = query
        self.parameters = parameters

    def fetchall(self):
        return self.rows

    def fetchone(self):
        return self.rows[0] if self.rows else None


class FakeConnection:
    def __init__(self, rows):
        self.rows = rows

    def cursor(self, **kwargs):
        return FakeCursor(self.rows)


class FakePool:
    def __init__(self, rows):
        self.rows = rows

    def close(self):
        pass

    def connection(self):
        pool = self

        class ConnectionContext:
            def __enter__(self):
                return FakeConnection(pool.rows)

            def __exit__(self, exc_type, exc_value, traceback):
                return False

        return ConnectionContext()


def test_list_vinos_returns_paginated_catalog(monkeypatch):
    monkeypatch.setattr(
        "bodega_api.db._pool",
        FakePool(
            [
                {
                    "cod_vino": 1,
                    "nombre": "Malbec Reserva",
                    "tipo": "Tinto",
                    "aniada": 2022,
                    "volumen": 750,
                    "graduacion": 14,
                    "precio": 1000,
                    "bodega": "Bodega Atuel",
                }
            ]
        ),
    )

    with TestClient(app) as client:
        response = client.get("/vinos?pagina=1&por_pagina=10&tipo=Tinto")

    assert response.status_code == 200
    assert response.json()["pagina"] == 1
    assert response.json()["items"][0]["nombre"] == "Malbec Reserva"


def test_get_vino_returns_not_found_for_unknown_code(monkeypatch):
    monkeypatch.setattr(
        "bodega_api.db._pool",
        FakePool([]),
    )

    with TestClient(app) as client:
        response = client.get("/vinos/999999")

    assert response.status_code == 404


def test_create_vino_success(monkeypatch):
    monkeypatch.setattr(
        "bodega_api.services.vinos.create_vino",
        lambda data: {"cod_vino": 10, **data},
    )

    payload = {
        "cuit_bodega": "30123456789",
        "nombre": "Cabernet Sauvignon",
        "tipo": "Tinto",
        "aniada": 2023,
        "volumen": 750.0,
        "graduacion": 13.5,
        "precio": 1500.0,
        "cepas": [{"id_cepa": 1, "porcentaje": 100.0}],
        "maridajes": [1],
    }
    with TestClient(app) as client:
        response = client.post("/vinos", json=payload)

    assert response.status_code == 201
    assert response.json()["cod_vino"] == 10


def test_delete_vino_success(monkeypatch):
    monkeypatch.setattr("bodega_api.services.vinos.delete_vino", lambda cod_v: None)

    with TestClient(app) as client:
        response = client.delete("/vinos/10")

    assert response.status_code == 204


def test_delete_vino_not_found(monkeypatch):
    def _raise(cod_v):
        raise NotFoundError("Vino no encontrado.")

    monkeypatch.setattr("bodega_api.services.vinos.delete_vino", _raise)

    with TestClient(app) as client:
        response = client.delete("/vinos/999")

    assert response.status_code == 404
    assert response.json() == {"error": "Vino no encontrado."}
