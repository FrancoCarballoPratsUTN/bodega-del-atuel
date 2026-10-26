from fastapi.testclient import TestClient

from bodega_api.main import app


def test_list_catalogos_returns_reference_data(monkeypatch):
    catalogos = {
        "salas": [
            {
                "id_sala": 1,
                "calle": "San Martín",
                "numero": 100,
                "cp_localidad": 5600,
                "localidad": "San Rafael",
                "dia_cierre": "lunes",
                "activo": True,
            }
        ],
        "cepas": [{"id_cepa": 1, "nombre": "Malbec", "tipo": "Tinta"}],
        "bodegas": [
            {
                "cuit_bodega": "30050000001",
                "razon_social": "Bodega Atuel",
                "activo": True,
            }
        ],
    }
    monkeypatch.setattr(
        "bodega_api.services.catalogos.list_catalogos",
        lambda: catalogos,
    )

    with TestClient(app) as client:
        response = client.get("/catalogos")

    assert response.status_code == 200
    assert response.json() == catalogos
