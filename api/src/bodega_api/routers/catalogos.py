from typing import Any

from fastapi import APIRouter

from bodega_api.services import catalogos as catalogo_service

router = APIRouter(prefix="/catalogos", tags=["Catálogos"])


@router.get("")
def list_catalogos_endpoint() -> dict[str, Any]:
    return catalogo_service.list_catalogos()
