from fastapi.testclient import TestClient

from bodega_api.main import app
from bodega_api.services.errors import NotFoundError


def test_top_vinos_report_returns_items(monkeypatch):
    monkeypatch.setattr(
        "bodega_api.services.reportes.top_vinos",
        lambda: [{"cod_vino": 1, "nombre": "Malbec", "botellas_vendidas": 10}],
    )

    with TestClient(app) as client:
        response = client.get("/reportes/top-vinos")

    assert response.status_code == 200
    assert response.json()[0]["cod_vino"] == 1


def test_ventas_por_sala_report(monkeypatch):
    monkeypatch.setattr(
        "bodega_api.services.reportes.ventas_por_sala",
        lambda: [{"id_sala": 1, "monto_total_ventas": 50000}],
    )

    with TestClient(app) as client:
        response = client.get("/reportes/ventas-por-sala")

    assert response.status_code == 200
    assert response.json()[0]["id_sala"] == 1


def test_vinos_sin_stock_report(monkeypatch):
    monkeypatch.setattr(
        "bodega_api.services.reportes.vinos_sin_stock",
        lambda id_sala: [{"cod_vino": 1, "stock_sala": 0, "stock_deposito": 15}],
    )

    with TestClient(app) as client:
        response = client.get("/reportes/vinos-sin-stock?id_sala=1")

    assert response.status_code == 200
    assert response.json()[0]["stock_deposito"] == 15


def test_transportista_activo_report(monkeypatch):
    monkeypatch.setattr(
        "bodega_api.services.reportes.transportista_activo",
        lambda: [{"cod_transportista": 1, "razon_social": "Transportes SA"}],
    )

    with TestClient(app) as client:
        response = client.get("/reportes/transportista-activo")

    assert response.status_code == 200
    assert response.json()[0]["cod_transportista"] == 1


def test_trazabilidad_report_found(monkeypatch):
    monkeypatch.setattr(
        "bodega_api.services.reportes.trazabilidad",
        lambda cod_vino: {"codigo_vino": cod_vino, "nombre_vino": "Malbec"},
    )

    with TestClient(app) as client:
        response = client.get("/reportes/trazabilidad/1")

    assert response.status_code == 200
    assert response.json()["codigo_vino"] == 1


def test_trazabilidad_report_not_found(monkeypatch):
    def _raise(cod_vino):
        raise NotFoundError("Vino no encontrado.")

    monkeypatch.setattr("bodega_api.services.reportes.trazabilidad", _raise)

    with TestClient(app) as client:
        response = client.get("/reportes/trazabilidad/999")

    assert response.status_code == 404
    assert response.json() == {"error": "Vino no encontrado."}
