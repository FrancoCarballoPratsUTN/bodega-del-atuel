from typing import Any

from fastapi import APIRouter, Query

from bodega_api.schemas import ClienteInput
from bodega_api.services import clientes as cliente_service

router = APIRouter(prefix="/clientes", tags=["Clientes"])


@router.get("")
def list_clientes_endpoint(
    pagina: int = Query(default=1, ge=1),
    por_pagina: int = Query(default=20, ge=1, le=100),
) -> dict[str, Any]:
    items = cliente_service.list_clientes(
        limit=por_pagina,
        offset=(pagina - 1) * por_pagina,
    )
    return {
        "items": items,
        "pagina": pagina,
        "por_pagina": por_pagina,
        "cantidad": len(items),
    }


@router.get("/{id_cliente}")
def get_cliente_endpoint(id_cliente: int) -> dict[str, Any]:
    return cliente_service.get_cliente(id_cliente)


@router.post("", status_code=201)
def create_cliente_endpoint(data: ClienteInput) -> dict[str, Any]:
    return cliente_service.create_cliente(data.model_dump())


@router.put("/{id_cliente}")
def update_cliente_endpoint(id_cliente: int, data: ClienteInput) -> dict[str, Any]:
    return cliente_service.update_cliente(id_cliente, data.model_dump())


@router.delete("/{id_cliente}", status_code=204)
def delete_cliente_endpoint(id_cliente: int) -> None:
    cliente_service.delete_cliente(id_cliente)
