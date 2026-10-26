import pytest

pytestmark = pytest.mark.integration


def _cliente_payload(**overrides):
    payload = {
        "cp_localidad": 5601,
        "nombre_razon_social": "Cliente Integración API",
        "tipo_doc": "DNI",
        "nro_doc": "API-0001",
        "direccion": "Calle Integración 123",
        "fecha_alta": "2024-01-15",
        "descuento": "20.00",
        "tipo_cliente": "Distribuidor",
        "zona_cobertura": "Mendoza",
        "nro_habilitacion": "HAB-API-0001",
    }
    payload.update(overrides)
    return payload


def test_list_clientes_searches_by_name_or_document(api_client):
    reference = api_client.get(
        "/clientes",
        params={"pagina": 1, "por_pagina": 1},
    ).json()["items"][0]

    by_name = api_client.get(
        "/clientes",
        params={"busqueda": reference["nombre_razon_social"], "por_pagina": 10},
    )
    by_document = api_client.get(
        "/clientes",
        params={"busqueda": reference["nro_doc"], "por_pagina": 10},
    )

    assert by_name.status_code == 200
    assert by_document.status_code == 200
    assert any(
        item["id_cliente"] == reference["id_cliente"]
        for item in by_name.json()["items"]
    )
    assert any(
        item["id_cliente"] == reference["id_cliente"]
        for item in by_document.json()["items"]
    )


def test_create_cliente_saves_distribuidor_subtype(api_client, db):
    created = api_client.post("/clientes", json=_cliente_payload())
    assert created.status_code == 201, created.text
    id_cliente = created.json()["id_cliente"]

    detail = api_client.get(f"/clientes/{id_cliente}")
    assert detail.status_code == 200
    assert detail.json()["tipo_cliente"] == "Distribuidor"
    assert detail.json()["zona_cobertura"] == "Mendoza"
    assert detail.json()["nro_habilitacion"] == "HAB-API-0001"

    subtype = db.execute(
        "SELECT zona_cobertura FROM distribuidor WHERE id_cliente = %s",
        (id_cliente,),
    ).fetchone()
    assert subtype["zona_cobertura"] == "Mendoza"


def test_update_cliente_moves_between_subtypes(api_client, db):
    created = api_client.post("/clientes", json=_cliente_payload())
    id_cliente = created.json()["id_cliente"]

    payload = _cliente_payload(
        tipo_cliente="Exportador",
        descuento="30.00",
        pais_destino="Chile",
        zona_cobertura=None,
        nro_habilitacion=None,
    )
    updated = api_client.put(f"/clientes/{id_cliente}", json=payload)

    assert updated.status_code == 200, updated.text
    assert updated.json()["tipo_cliente"] == "Exportador"
    assert updated.json()["pais_destino"] == "Chile"

    distribuidor = db.execute(
        "SELECT COUNT(*) AS cantidad FROM distribuidor WHERE id_cliente = %s",
        (id_cliente,),
    ).fetchone()
    exportador = db.execute(
        "SELECT pais_destino FROM exportador WHERE id_cliente = %s",
        (id_cliente,),
    ).fetchone()
    assert distribuidor["cantidad"] == 0
    assert exportador["pais_destino"] == "Chile"


def test_create_cliente_with_invalid_discount_returns_422(api_client):
    payload = _cliente_payload(
        tipo_cliente="Socio",
        descuento="15.00",
        zona_cobertura=None,
        nro_habilitacion=None,
    )

    response = api_client.post("/clientes", json=payload)

    assert response.status_code == 422
    assert response.json()["codigo_sqlstate"] == "23514"


def test_create_cliente_with_duplicate_document_returns_conflict(api_client):
    existing = api_client.post("/clientes", json=_cliente_payload())
    assert existing.status_code == 201

    response = api_client.post(
        "/clientes",
        json=_cliente_payload(nombre_razon_social="Otro Cliente"),
    )

    assert response.status_code == 409
    assert response.json()["codigo_sqlstate"] == "23505"


def test_delete_cliente_is_a_soft_delete(api_client, db):
    created = api_client.post("/clientes", json=_cliente_payload())
    id_cliente = created.json()["id_cliente"]

    response = api_client.delete(f"/clientes/{id_cliente}")

    assert response.status_code == 204
    assert api_client.get(f"/clientes/{id_cliente}").status_code == 404
    row = db.execute(
        "SELECT activo FROM cliente WHERE id_cliente = %s",
        (id_cliente,),
    ).fetchone()
    assert row["activo"] is False
