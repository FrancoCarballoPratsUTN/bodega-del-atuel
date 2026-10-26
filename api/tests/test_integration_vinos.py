import pytest

pytestmark = pytest.mark.integration


def _vino_payload(db, **overrides):
    bodega = db.execute(
        "SELECT cuit_bodega FROM bodega ORDER BY cuit_bodega LIMIT 1"
    ).fetchone()
    payload = {
        "cuit_bodega": bodega["cuit_bodega"],
        "nombre": "Vino Integración API",
        "tipo": "tinto",
        "aniada": 2025,
        "volumen": "750.00",
        "graduacion": "13.50",
        "precio": "1234.50",
        "cepas": [{"id_cepa": 1, "porcentaje": "100.00"}],
        "maridajes": [1],
    }
    payload.update(overrides)
    return payload


def test_list_vinos_filters_by_type_and_paginates(api_client):
    response = api_client.get(
        "/vinos",
        params={"tipo": "tinto", "pagina": 1, "por_pagina": 5},
    )

    assert response.status_code == 200
    body = response.json()
    assert body["pagina"] == 1
    assert body["por_pagina"] == 5
    assert len(body["items"]) == 5
    assert all(item["tipo"] == "tinto" for item in body["items"])


def test_list_vinos_filters_by_cepa_bodega_and_aniada(api_client, db):
    reference = db.execute(
        """
        SELECT v.aniada, b.razon_social AS bodega, ce.nombre AS cepa
          FROM vino v
          JOIN bodega b ON b.cuit_bodega = v.cuit_bodega
          JOIN composicion co ON co.cod_vino = v.cod_vino
          JOIN cepa ce ON ce.id_cepa = co.id_cepa
         WHERE v.cod_vino = 1
        """
    ).fetchone()

    response = api_client.get(
        "/vinos",
        params={
            "cepa": reference["cepa"],
            "bodega": reference["bodega"],
            "aniada": reference["aniada"],
        },
    )

    assert response.status_code == 200
    items = response.json()["items"]
    assert items
    assert all(item["aniada"] == reference["aniada"] for item in items)


def test_get_vino_detail_includes_composition_and_pairings(api_client):
    response = api_client.get("/vinos/1")

    assert response.status_code == 200
    vino = response.json()
    assert vino["cod_vino"] == 1
    assert vino["cuit_bodega"]
    assert vino["cepas"][0]["id_cepa"] == 1
    assert vino["cepas"][0]["nombre"] == "Malbec"
    assert float(vino["cepas"][0]["porcentaje"]) == 100.0
    assert vino["maridajes"][0]["id_maridaje"]
    assert vino["maridajes"][0]["nombre"] == "Carnes rojas"


def test_create_update_and_deactivate_vino(api_client, db):
    payload = _vino_payload(db)

    created = api_client.post("/vinos", json=payload)
    assert created.status_code == 201, created.text
    cod_vino = created.json()["cod_vino"]

    detail = api_client.get(f"/vinos/{cod_vino}")
    assert detail.status_code == 200
    assert detail.json()["nombre"] == payload["nombre"]
    assert detail.json()["cepas"][0]["nombre"] == "Malbec"

    payload["precio"] = "1500.00"
    payload["cepas"] = [{"id_cepa": 2, "porcentaje": "100.00"}]
    updated = api_client.put(f"/vinos/{cod_vino}", json=payload)

    assert updated.status_code == 200, updated.text
    assert float(updated.json()["precio"]) == 1500.0
    assert updated.json()["cepas"][0]["nombre"] == "Cabernet Sauvignon"

    deleted = api_client.delete(f"/vinos/{cod_vino}")
    assert deleted.status_code == 204
    assert api_client.get(f"/vinos/{cod_vino}").status_code == 404

    active = db.execute(
        "SELECT activo FROM vino WHERE cod_vino = %s",
        (cod_vino,),
    ).fetchone()
    assert active["activo"] is False


def test_create_vino_rejects_composition_not_summing_100(api_client, db):
    payload = _vino_payload(
        db,
        cepas=[{"id_cepa": 1, "porcentaje": "99.00"}],
    )

    response = api_client.post("/vinos", json=payload)

    assert response.status_code == 409
    assert response.json()["codigo_sqlstate"] == "P0001"
    assert "exactamente 100" in response.json()["error"]

    persisted = db.execute(
        "SELECT COUNT(*) AS cantidad FROM vino WHERE nombre = %s",
        (payload["nombre"],),
    ).fetchone()
    assert persisted["cantidad"] == 0


def test_create_vino_duplicate_identity_returns_conflict(api_client, db):
    existing = db.execute(
        """
        SELECT nombre, aniada, volumen, cuit_bodega
          FROM vino
         WHERE cod_vino = 1
        """
    ).fetchone()
    payload = _vino_payload(
        db,
        nombre=existing["nombre"],
        aniada=existing["aniada"],
        volumen=str(existing["volumen"]),
        cuit_bodega=existing["cuit_bodega"],
    )

    response = api_client.post("/vinos", json=payload)

    assert response.status_code == 409
    assert response.json()["codigo_sqlstate"] == "23505"


def test_get_unknown_vino_returns_not_found(api_client):
    assert api_client.get("/vinos/99999999").status_code == 404
