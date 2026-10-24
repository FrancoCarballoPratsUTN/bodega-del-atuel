from decimal import Decimal

import pytest

pytestmark = pytest.mark.integration


def test_create_comprobante_calculates_totals_and_updates_stock(api_client, db):
    stock_before = db.execute(
        "SELECT cantidad FROM stock_sala WHERE id_sala = 1 AND cod_vino = 1"
    ).fetchone()["cantidad"]

    response = api_client.post(
        "/comprobantes",
        json={
            "id_cliente": 3,
            "id_sala": 1,
            "renglones": [
                {"cod_vino": 1, "cantidad": 2},
                {"cod_vino": 2, "cantidad": 1},
            ],
        },
    )

    assert response.status_code == 201, response.text
    comprobante = response.json()
    assert Decimal(str(comprobante["subtotal"])) == Decimal("3628.00")
    assert Decimal(str(comprobante["descuento"])) == Decimal("362.80")
    assert Decimal(str(comprobante["total"])) == Decimal("3265.20")
    assert len(comprobante["renglones"]) == 2

    stock_after = db.execute(
        "SELECT cantidad FROM stock_sala WHERE id_sala = 1 AND cod_vino = 1"
    ).fetchone()["cantidad"]
    assert stock_after == stock_before - 2

    fetched = api_client.get(f"/comprobantes/{comprobante['nro_comprobante']}")
    assert fetched.status_code == 200
    assert fetched.json()["total"] == comprobante["total"]


def test_create_comprobante_without_stock_rolls_back_header_and_lines(api_client, db):
    created_vino = api_client.post(
        "/vinos",
        json={
            "cuit_bodega": db.execute(
                "SELECT cuit_bodega FROM bodega ORDER BY cuit_bodega LIMIT 1"
            ).fetchone()["cuit_bodega"],
            "nombre": "Vino Sin Stock Integración",
            "tipo": "tinto",
            "aniada": 2025,
            "volumen": "750.00",
            "graduacion": "13.50",
            "precio": "900.00",
            "cepas": [{"id_cepa": 1, "porcentaje": "100.00"}],
            "maridajes": [],
        },
    )
    assert created_vino.status_code == 201, created_vino.text
    cod_vino = created_vino.json()["cod_vino"]

    count_before = db.execute(
        "SELECT COUNT(*) AS cantidad FROM comprobante"
    ).fetchone()["cantidad"]

    response = api_client.post(
        "/comprobantes",
        json={
            "id_cliente": 3,
            "id_sala": 1,
            "renglones": [{"cod_vino": cod_vino, "cantidad": 1}],
        },
    )

    assert response.status_code == 409
    assert response.json()["codigo_sqlstate"] == "P0001"
    assert "Stock insuficiente" in response.json()["error"]

    count_after = db.execute("SELECT COUNT(*) AS cantidad FROM comprobante").fetchone()[
        "cantidad"
    ]
    orphan_lines = db.execute(
        """
        SELECT COUNT(*) AS cantidad
          FROM renglon_comprobante r
         WHERE NOT EXISTS (
             SELECT 1 FROM comprobante c
              WHERE c.nro_comprobante = r.nro_comprobante
         )
        """
    ).fetchone()["cantidad"]
    assert count_after == count_before
    assert orphan_lines == 0
