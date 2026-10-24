from pathlib import Path

PACKAGE = Path(__file__).parents[1] / "src" / "bodega_api"


def _sources(directory: Path) -> dict[str, str]:
    return {
        path.name: path.read_text(encoding="utf-8")
        for path in sorted(directory.glob("*.py"))
        if path.name != "__init__.py"
    }


def test_routers_only_depend_on_service_layer():
    for name, source in _sources(PACKAGE / "routers").items():
        assert "bodega_api.services" in source, name
        assert "bodega_api.dao" not in source, name
        assert "bodega_api.db" not in source, name
        assert "get_pool" not in source, name


def test_services_own_connection_and_transaction_boundaries():
    for name, source in _sources(PACKAGE / "services").items():
        if name == "errors.py":
            continue
        assert "from bodega_api import db" in source, name
        assert "db.connection()" in source or "db.transaction()" in source, name


def test_services_do_not_depend_on_presentation_layer():
    for name, source in _sources(PACKAGE / "services").items():
        assert "bodega_api.routers" not in source, name
        assert "fastapi" not in source, name
        assert "starlette" not in source, name


def test_services_do_not_execute_direct_sql():
    for name, source in _sources(PACKAGE / "services").items():
        if name == "errors.py":
            continue
        assert "cursor(" not in source, name
        assert "execute(" not in source, name


def test_dao_does_not_manage_transactions():
    for name, source in _sources(PACKAGE / "dao").items():
        assert ".transaction(" not in source, name
        assert ".commit(" not in source, name
        assert ".rollback(" not in source, name


def test_dao_does_not_depend_on_upper_layers_or_db():
    for name, source in _sources(PACKAGE / "dao").items():
        assert "bodega_api.routers" not in source, name
        assert "bodega_api.services" not in source, name
        assert "bodega_api.db" not in source, name
        assert "fastapi" not in source, name


def test_dao_does_not_execute_interpolated_sql():
    for name, source in _sources(PACKAGE / "dao").items():
        assert 'execute(f"' not in source, name
        assert "execute(f'" not in source, name
        assert "execute(query %" not in source, name
        assert "execute(query +" not in source, name
