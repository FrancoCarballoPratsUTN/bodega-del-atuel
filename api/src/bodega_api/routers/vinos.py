from typing import Any

from fastapi import APIRouter, Query

from bodega_api.schemas import VinoCreate, VinoUpdate
from bodega_api.services import vinos as vino_service

router = APIRouter(prefix="/vinos", tags=["Vinos"])


@router.get("")
def list_vinos(
    pagina: int = Query(default=1, ge=1),
    por_pagina: int = Query(default=20, ge=1, le=100),
    tipo: str | None = None,
    cepa: str | None = None,
    bodega: str | None = None,
    aniada: int | None = Query(default=None, ge=1900, le=2100),
) -> dict[str, Any]:
    items = vino_service.list_vinos(
        tipo=tipo,
        cepa=cepa,
        bodega=bodega,
        aniada=aniada,
        limit=por_pagina,
        offset=(pagina - 1) * por_pagina,
    )
    return {
        "items": items,
        "pagina": pagina,
        "por_pagina": por_pagina,
        "cantidad": len(items),
    }


@router.get("/{cod_vino}")
def get_vino_endpoint(cod_vino: int) -> dict[str, Any]:
    return vino_service.get_vino(cod_vino)


@router.post("", status_code=201)
def create_vino_endpoint(data: VinoCreate) -> dict[str, Any]:
    return vino_service.create_vino(data.model_dump())


@router.put("/{cod_vino}")
def update_vino_endpoint(cod_vino: int, data: VinoUpdate) -> dict[str, Any]:
    return vino_service.update_vino(cod_vino, data.model_dump())


@router.delete("/{cod_vino}", status_code=204)
def delete_vino_endpoint(cod_vino: int) -> None:
    vino_service.delete_vino(cod_vino)
