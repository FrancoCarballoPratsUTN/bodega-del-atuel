from fastapi.testclient import TestClient
from psycopg import errors

from bodega_api.main import app


def test_postgres_unique_error_returns_conflict():
    @app.get("/test-error-unique")
    def raise_unique_error():
        raise errors.UniqueViolation("duplicate")

    with TestClient(app) as client:
        response = client.get("/test-error-unique")

    assert response.status_code == 409
    assert response.json()["codigo_sqlstate"] == "23505"


def test_unknown_route_uses_consistent_error_payload():
    with TestClient(app) as client:
        response = client.get("/ruta-que-no-existe")

    assert response.status_code == 404
    assert response.json() == {"error": "Not Found"}


def test_validation_error_uses_consistent_error_payload():
    with TestClient(app) as client:
        response = client.post(
            "/comprobantes",
            json={"id_cliente": 1, "id_sala": 1, "renglones": []},
        )

    assert response.status_code == 422
    assert response.json()["error"] == "Datos de entrada inválidos."
    assert response.json()["detalles"]
