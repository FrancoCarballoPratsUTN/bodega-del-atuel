import pytest

pytestmark = pytest.mark.integration


def test_catalogos_returns_reference_rows(api_client):
    response = api_client.get("/catalogos")

    assert response.status_code == 200
    body = response.json()
    assert body["salas"]
    assert body["cepas"]
    assert body["bodegas"]
    assert {"id_sala", "localidad", "activo"} <= set(body["salas"][0])
    assert {"id_cepa", "nombre", "tipo"} <= set(body["cepas"][0])
    assert {"cuit_bodega", "razon_social", "activo"} <= set(body["bodegas"][0])
