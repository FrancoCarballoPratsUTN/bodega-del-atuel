from fastapi.testclient import TestClient

from bodega_api.main import app
from bodega_api.services.errors import NotFoundError


def test_comprobante_requires_at_least_one_line():
    with TestClient(app) as client:
        response = client.post(
            "/comprobantes",
            json={"id_cliente": 1, "id_sala": 1, "renglones": []},
        )

    assert response.status_code == 422


def test_create_comprobante_success(monkeypatch):
    monkeypatch.setattr(
        "bodega_api.services.comprobantes.create_comprobante",
        lambda id_cliente, id_sala, renglones: {
            "nro_comprobante": 100,
            "id_cliente": id_cliente,
            "id_sala": id_sala,
            "renglones": renglones,
        },
    )

    with TestClient(app) as client:
        response = client.post(
            "/comprobantes",
            json={
                "id_cliente": 1,
                "id_sala": 1,
                "renglones": [{"cod_vino": 1, "cantidad": 2}],
            },
        )

    assert response.status_code == 201
    assert response.json()["nro_comprobante"] == 100


def test_get_comprobante_found(monkeypatch):
    monkeypatch.setattr(
        "bodega_api.services.comprobantes.get_comprobante",
        lambda nro_comprobante: {
            "nro_comprobante": nro_comprobante,
            "id_cliente": 1,
            "id_sala": 1,
            "renglones": [],
        },
    )

    with TestClient(app) as client:
        response = client.get("/comprobantes/100")

    assert response.status_code == 200
    assert response.json()["nro_comprobante"] == 100


def test_get_comprobante_not_found(monkeypatch):
    def _raise(nro):
        raise NotFoundError("Comprobante no encontrado.")

    monkeypatch.setattr("bodega_api.services.comprobantes.get_comprobante", _raise)

    with TestClient(app) as client:
        response = client.get("/comprobantes/999")

    assert response.status_code == 404
    assert response.json() == {"error": "Comprobante no encontrado."}
