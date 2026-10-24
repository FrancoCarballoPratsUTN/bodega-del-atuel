import pytest

pytestmark = pytest.mark.integration


def test_transferencia_workflow_processes_stock(api_client, db):
    stock_deposito_before = db.execute(
        "SELECT cantidad FROM stock_deposito WHERE cod_vino = 1"
    ).fetchone()["cantidad"]
    stock_sala_before = db.execute(
        "SELECT cantidad FROM stock_sala WHERE id_sala = 1 AND cod_vino = 1"
    ).fetchone()["cantidad"]

    created = api_client.post("/transferencias", json={"id_sala": 1})
    assert created.status_code == 201, created.text
    nro_transferencia = created.json()["codigo"]

    line = api_client.post(
        f"/transferencias/{nro_transferencia}/renglones",
        json={"cod_vino": 1, "cantidad": 5},
    )
    assert line.status_code == 204

    finished = api_client.post(f"/transferencias/{nro_transferencia}/terminar")
    assert finished.status_code == 204

    processed = api_client.post(f"/transferencias/{nro_transferencia}/procesar")
    assert processed.status_code == 204

    state = db.execute(
        "SELECT estado FROM transferencia WHERE nro_transferencia = %s",
        (nro_transferencia,),
    ).fetchone()
    assert state["estado"] == "procesado"

    stock_deposito_after = db.execute(
        "SELECT cantidad FROM stock_deposito WHERE cod_vino = 1"
    ).fetchone()["cantidad"]
    stock_sala_after = db.execute(
        "SELECT cantidad FROM stock_sala WHERE id_sala = 1 AND cod_vino = 1"
    ).fetchone()["cantidad"]
    assert stock_deposito_after == stock_deposito_before - 5
    assert stock_sala_after == stock_sala_before + 5

    rejected = api_client.post(
        f"/transferencias/{nro_transferencia}/renglones",
        json={"cod_vino": 2, "cantidad": 1},
    )
    assert rejected.status_code == 409
    assert rejected.json()["codigo_sqlstate"] == "P0001"


def test_ingreso_workflow_processes_stock(api_client, db):
    stock_before = db.execute(
        "SELECT cantidad FROM stock_deposito WHERE cod_vino = 1"
    ).fetchone()["cantidad"]

    created = api_client.post(
        "/ingresos",
        json={
            "cod_transportista": 1,
            "cuit_bodega": "30050000001",
        },
    )
    assert created.status_code == 201, created.text
    cod_ingreso = created.json()["codigo"]

    line = api_client.post(
        f"/ingresos/{cod_ingreso}/renglones",
        json={"cod_vino": 1, "cantidad": 3},
    )
    assert line.status_code == 204

    finished = api_client.post(f"/ingresos/{cod_ingreso}/terminar")
    assert finished.status_code == 204

    processed = api_client.post(f"/ingresos/{cod_ingreso}/procesar")
    assert processed.status_code == 204

    state = db.execute(
        "SELECT estado FROM ingreso WHERE cod_ingreso = %s",
        (cod_ingreso,),
    ).fetchone()
    assert state["estado"] == "procesado"

    stock_after = db.execute(
        "SELECT cantidad FROM stock_deposito WHERE cod_vino = 1"
    ).fetchone()["cantidad"]
    assert stock_after == stock_before + 3


def test_process_transferencia_requires_terminado_state(api_client, db):
    created = api_client.post("/transferencias", json={"id_sala": 1})
    nro_transferencia = created.json()["codigo"]

    response = api_client.post(f"/transferencias/{nro_transferencia}/procesar")

    assert response.status_code == 409
    assert response.json()["codigo_sqlstate"] == "P0001"
    assert "no está en estado" in response.json()["error"]
