from typing import Any

from fastapi import APIRouter

from bodega_api.schemas import (
    IngresoInput,
    RenglonMovimientoInput,
    TransferenciaInput,
)
from bodega_api.services import movimientos as movimiento_service

transferencias_router = APIRouter(prefix="/transferencias", tags=["Transferencias"])
ingresos_router = APIRouter(prefix="/ingresos", tags=["Ingresos"])


@transferencias_router.post("", status_code=201)
def create_transferencia_endpoint(data: TransferenciaInput) -> dict[str, Any]:
    return movimiento_service.create_transferencia(data.id_sala)


@transferencias_router.post("/{codigo}/renglones", status_code=204)
def add_transferencia_line_endpoint(
    codigo: int,
    data: RenglonMovimientoInput,
) -> None:
    movimiento_service.add_transferencia_line(codigo, data.cod_vino, data.cantidad)


@transferencias_router.post("/{codigo}/terminar", status_code=204)
def finish_transferencia_endpoint(codigo: int) -> None:
    movimiento_service.finish_transferencia(codigo)


@transferencias_router.post("/{codigo}/procesar", status_code=204)
def process_transferencia_endpoint(codigo: int) -> None:
    movimiento_service.process_transferencia(codigo)


@ingresos_router.post("", status_code=201)
def create_ingreso_endpoint(data: IngresoInput) -> dict[str, Any]:
    return movimiento_service.create_ingreso(
        data.cod_transportista,
        data.cuit_bodega,
    )


@ingresos_router.post("/{codigo}/renglones", status_code=204)
def add_ingreso_line_endpoint(codigo: int, data: RenglonMovimientoInput) -> None:
    movimiento_service.add_ingreso_line(codigo, data.cod_vino, data.cantidad)


@ingresos_router.post("/{codigo}/terminar", status_code=204)
def finish_ingreso_endpoint(codigo: int) -> None:
    movimiento_service.finish_ingreso(codigo)


@ingresos_router.post("/{codigo}/procesar", status_code=204)
def process_ingreso_endpoint(codigo: int) -> None:
    movimiento_service.process_ingreso(codigo)
