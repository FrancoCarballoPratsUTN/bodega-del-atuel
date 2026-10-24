from fastapi.testclient import TestClient

from bodega_api.main import app


def test_openapi_contains_all_delivered_routes():
    with TestClient(app) as client:
        schema = client.get("/openapi.json").json()

    expected_paths = {
        "/healthy",
        "/vinos",
        "/vinos/{cod_vino}",
        "/clientes",
        "/clientes/{id_cliente}",
        "/comprobantes",
        "/comprobantes/{nro_comprobante}",
        "/transferencias",
        "/transferencias/{codigo}/renglones",
        "/transferencias/{codigo}/terminar",
        "/transferencias/{codigo}/procesar",
        "/ingresos",
        "/ingresos/{codigo}/renglones",
        "/ingresos/{codigo}/terminar",
        "/ingresos/{codigo}/procesar",
        "/reportes/top-vinos",
        "/reportes/ventas-por-sala",
        "/reportes/vinos-sin-stock",
        "/reportes/transportista-activo",
        "/reportes/trazabilidad/{cod_vino}",
    }
    assert expected_paths <= set(schema["paths"])
