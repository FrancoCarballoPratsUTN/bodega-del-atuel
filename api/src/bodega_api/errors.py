from collections.abc import Awaitable, Callable

from fastapi import Request
from fastapi.encoders import jsonable_encoder
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from psycopg import Error as PostgresError
from starlette.exceptions import HTTPException

from bodega_api.services.errors import ServiceError

_SQLSTATE_STATUS = {
    "23502": 422,
    "23503": 409,
    "23505": 409,
    "23514": 422,
    "22P02": 400,
    "P0001": 409,
    "40001": 503,
    "40P01": 503,
}


def http_status_for_sqlstate(sqlstate: str | None) -> int:
    return _SQLSTATE_STATUS.get(sqlstate or "", 500)


async def http_exception_handler(
    _: Request,
    error: HTTPException,
) -> JSONResponse:
    return JSONResponse(
        status_code=error.status_code,
        content={"error": error.detail},
        headers=error.headers,
    )


async def validation_exception_handler(
    _: Request,
    error: RequestValidationError,
) -> JSONResponse:
    return JSONResponse(
        status_code=422,
        content={
            "error": "Datos de entrada inválidos.",
            "detalles": jsonable_encoder(error.errors()),
        },
    )


def postgres_error_handler() -> Callable[
    [Request, PostgresError], Awaitable[JSONResponse]
]:
    async def handle(_: Request, error: PostgresError) -> JSONResponse:
        status_code = http_status_for_sqlstate(error.sqlstate)
        detail = error.diag.message_primary or str(error)
        response: dict[str, object] = {
            "error": detail,
            "codigo_sqlstate": error.sqlstate,
        }
        if status_code == 503:
            response["reintentar"] = True
        return JSONResponse(status_code=status_code, content=response)

    return handle


def service_error_handler(
    status_code: int,
) -> Callable[[Request, ServiceError], Awaitable[JSONResponse]]:
    async def handle(_: Request, error: ServiceError) -> JSONResponse:
        return JSONResponse(status_code=status_code, content={"error": str(error)})

    return handle
