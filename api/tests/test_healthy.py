from fastapi.testclient import TestClient

from bodega_api.main import app


def test_healthy_reports_database_status(monkeypatch):
    class HealthyConnection:
        def execute(self, query):
            assert query == "SELECT 1"

    class HealthyPool:
        def close(self):
            pass

        def connection(self):
            class ConnectionContext:
                def __enter__(self):
                    return HealthyConnection()

                def __exit__(self, exc_type, exc_value, traceback):
                    return False

            return ConnectionContext()

    monkeypatch.setattr("bodega_api.db._pool", HealthyPool())

    with TestClient(app) as client:
        response = client.get("/healthy")

    assert response.status_code == 200
    assert response.json() == {"status": "ok", "database": "available"}


def test_healthy_reports_database_unavailable(monkeypatch):
    class FailingPool:
        def close(self):
            pass

        def connection(self):
            raise RuntimeError("Database connection failed")

    monkeypatch.setattr("bodega_api.db._pool", FailingPool())

    with TestClient(app) as client:
        response = client.get("/healthy")

    assert response.status_code == 503
    assert response.json() == {"error": "La base de datos no está disponible."}
