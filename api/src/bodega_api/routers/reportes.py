from typing import Any

from fastapi import APIRouter, Query

from bodega_api.services import reportes as reporte_service

router = APIRouter(prefix="/reportes", tags=["Reportes"])


@router.get("/top-vinos")
def top_vinos_endpoint() -> Any:
    return reporte_service.top_vinos()


@router.get("/ventas-por-sala")
def ventas_por_sala_endpoint() -> Any:
    return reporte_service.ventas_por_sala()


@router.get("/vinos-sin-stock")
def vinos_sin_stock_endpoint(id_sala: int = Query(gt=0)) -> Any:
    return reporte_service.vinos_sin_stock(id_sala)


@router.get("/transportista-activo")
def transportista_activo_endpoint() -> Any:
    return reporte_service.transportista_activo()


@router.get("/trazabilidad/{cod_vino}")
def trazabilidad_endpoint(cod_vino: int) -> Any:
    return reporte_service.trazabilidad(cod_vino)
