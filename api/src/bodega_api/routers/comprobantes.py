from typing import Any

from fastapi import APIRouter

from bodega_api.schemas import ComprobanteInput
from bodega_api.services import comprobantes as comprobante_service

router = APIRouter(prefix="/comprobantes", tags=["Comprobantes"])


@router.post("", status_code=201)
def create_comprobante_endpoint(data: ComprobanteInput) -> dict[str, Any]:
    return comprobante_service.create_comprobante(
        id_cliente=data.id_cliente,
        id_sala=data.id_sala,
        renglones=[renglon.model_dump() for renglon in data.renglones],
    )


@router.get("/{nro_comprobante}")
def get_comprobante_endpoint(nro_comprobante: int) -> dict[str, Any]:
    return comprobante_service.get_comprobante(nro_comprobante)
