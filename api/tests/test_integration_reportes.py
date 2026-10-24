from pathlib import Path

import pytest

pytestmark = pytest.mark.integration


def test_top_vinos_report_returns_ranking(api_client):
    response = api_client.get("/reportes/top-vinos")

    assert response.status_code == 200
    rows = response.json()
    assert len(rows) == 10
    assert {"cod_vino", "nombre", "botellas_vendidas"} <= set(rows[0])


def test_ventas_por_sala_report_matches_s8_aliases(api_client):
    response = api_client.get("/reportes/ventas-por-sala")

    assert response.status_code == 200
    rows = response.json()
    assert rows
    assert {"id_sala", "monto_total_ventas"} <= set(rows[0])


def test_vinos_sin_stock_report_matches_s6_aliases(api_client, db):
    created = api_client.post(
        "/vinos",
        json={
            "cuit_bodega": db.execute(
                "SELECT cuit_bodega FROM bodega ORDER BY cuit_bodega LIMIT 1"
            ).fetchone()["cuit_bodega"],
            "nombre": "Vino Reporte Sin Stock",
            "tipo": "tinto",
            "aniada": 2025,
            "volumen": "750.00",
            "graduacion": "13.50",
            "precio": "1000.00",
            "cepas": [{"id_cepa": 1, "porcentaje": "100.00"}],
            "maridajes": [],
        },
    )
    cod_vino = created.json()["cod_vino"]
    db.execute(
        "INSERT INTO stock_deposito (cod_vino, cantidad) VALUES (%s, 7)",
        (cod_vino,),
    )

    response = api_client.get(
        "/reportes/vinos-sin-stock",
        params={"id_sala": 1},
    )

    assert response.status_code == 200
    row = next(item for item in response.json() if item["cod_vino"] == cod_vino)
    assert row["stock_sala"] == 0
    assert row["stock_deposito"] == 7


def test_transportista_activo_report_matches_s7_aliases(api_client):
    created = api_client.post(
        "/ingresos",
        json={"cod_transportista": 1, "cuit_bodega": "30050000001"},
    )
    assert created.status_code == 201

    response = api_client.get("/reportes/transportista-activo")

    assert response.status_code == 200
    rows = response.json()
    assert rows
    assert {"cod_transportista", "razon_social", "ingresos_trasladados"} <= set(rows[0])


def test_trazabilidad_report_matches_s9(api_client):
    response = api_client.get("/reportes/trazabilidad/1")

    assert response.status_code == 200
    row = response.json()
    assert row["codigo_vino"] == 1
    assert row["nombre_vino"] == "Vino Atuel 1"
    assert "Malbec (100.00%)" in row["cepas"]
    assert row["maridajes"] == "Carnes rojas"
    assert row["stock_total"] > 0


def test_sql_injection_in_filter_is_treated_as_text(api_client):
    response = api_client.get(
        "/vinos",
        params={"tipo": "tinto' OR 1=1 --", "por_pagina": 10},
    )

    assert response.status_code == 200
    assert response.json()["items"] == []


def test_dao_source_does_not_execute_interpolated_sql():
    dao_directory = Path(__file__).parents[1] / "src" / "bodega_api" / "dao"

    for source_file in dao_directory.glob("*.py"):
        source = source_file.read_text(encoding="utf-8")
        assert 'execute(f"' not in source
        assert "execute(f'" not in source
        assert "execute(query %" not in source
        assert "execute(query +" not in source
