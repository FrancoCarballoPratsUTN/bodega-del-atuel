from fastapi.testclient import TestClient

from bodega_api.main import app
from bodega_api.services.errors import NotFoundError


def test_create_transferencia_returns_created(monkeypatch):
    monkeypatch.setattr(
        "bodega_api.services.movimientos.create_transferencia",
        lambda id_sala: {"codigo": 42, "id_sala": id_sala, "estado": "en_confeccion"},
    )
    with TestClient(app) as client:
        response = client.post("/transferencias", json={"id_sala": 1})
    assert response.status_code == 201
    assert response.json()["codigo"] == 42


def test_add_transferencia_line_returns_no_content(monkeypatch):
    called = []
    monkeypatch.setattr(
        "bodega_api.services.movimientos.add_transferencia_line",
        lambda codigo, cod_vino, cantidad: called.append((codigo, cod_vino, cantidad)),
    )
    with TestClient(app) as client:
        response = client.post(
            "/transferencias/42/renglones", json={"cod_vino": 1, "cantidad": 5}
        )
    assert response.status_code == 204
    assert called == [(42, 1, 5)]


def test_finish_transferencia_success(monkeypatch):
    monkeypatch.setattr(
        "bodega_api.services.movimientos.finish_transferencia",
        lambda codigo: None,
    )
    with TestClient(app) as client:
        response = client.post("/transferencias/42/terminar")
    assert response.status_code == 204


def test_finish_transferencia_not_found(monkeypatch):
    def _raise(codigo):
        raise NotFoundError("Transferencia no encontrada.")

    monkeypatch.setattr(
        "bodega_api.services.movimientos.finish_transferencia",
        _raise,
    )
    with TestClient(app) as client:
        response = client.post("/transferencias/999/terminar")
    assert response.status_code == 404
    assert response.json() == {"error": "Transferencia no encontrada."}


def test_process_transferencia_success(monkeypatch):
    monkeypatch.setattr(
        "bodega_api.services.movimientos.process_transferencia",
        lambda codigo: None,
    )
    with TestClient(app) as client:
        response = client.post("/transferencias/42/procesar")
    assert response.status_code == 204


def test_create_ingreso_returns_created(monkeypatch):
    monkeypatch.setattr(
        "bodega_api.services.movimientos.create_ingreso",
        lambda cod_transportista, cuit_bodega: {
            "codigo": 10,
            "cod_transportista": cod_transportista,
            "cuit_bodega": cuit_bodega,
            "estado": "en_confeccion",
        },
    )
    with TestClient(app) as client:
        response = client.post(
            "/ingresos",
            json={"cod_transportista": 1, "cuit_bodega": "20123456789"},
        )
    assert response.status_code == 201
    assert response.json()["codigo"] == 10


def test_add_ingreso_line_returns_no_content(monkeypatch):
    called = []
    monkeypatch.setattr(
        "bodega_api.services.movimientos.add_ingreso_line",
        lambda codigo, cod_vino, cantidad: called.append((codigo, cod_vino, cantidad)),
    )
    with TestClient(app) as client:
        response = client.post(
            "/ingresos/10/renglones", json={"cod_vino": 2, "cantidad": 12}
        )
    assert response.status_code == 204
    assert called == [(10, 2, 12)]


def test_finish_ingreso_success(monkeypatch):
    monkeypatch.setattr(
        "bodega_api.services.movimientos.finish_ingreso",
        lambda codigo: None,
    )
    with TestClient(app) as client:
        response = client.post("/ingresos/10/terminar")
    assert response.status_code == 204


def test_finish_ingreso_not_found(monkeypatch):
    def _raise(codigo):
        raise NotFoundError("Ingreso no encontrado.")

    monkeypatch.setattr(
        "bodega_api.services.movimientos.finish_ingreso",
        _raise,
    )
    with TestClient(app) as client:
        response = client.post("/ingresos/999/terminar")
    assert response.status_code == 404
    assert response.json() == {"error": "Ingreso no encontrado."}


def test_process_ingreso_success(monkeypatch):
    monkeypatch.setattr(
        "bodega_api.services.movimientos.process_ingreso",
        lambda codigo: None,
    )
    with TestClient(app) as client:
        response = client.post("/ingresos/10/procesar")
    assert response.status_code == 204
