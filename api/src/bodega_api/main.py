from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.exceptions import RequestValidationError
from psycopg import Error as PostgresError
from starlette.exceptions import HTTPException as StarletteHTTPException

from bodega_api.db import close_pool
from bodega_api.errors import (
    http_exception_handler,
    postgres_error_handler,
    service_error_handler,
    validation_exception_handler,
)
from bodega_api.routers.catalogos import router as catalogos_router
from bodega_api.routers.clientes import router as clientes_router
from bodega_api.routers.comprobantes import router as comprobantes_router
from bodega_api.routers.healthy import router as healthy_router
from bodega_api.routers.movimientos import ingresos_router, transferencias_router
from bodega_api.routers.reportes import router as reportes_router
from bodega_api.routers.vinos import router as vinos_router
from bodega_api.services.errors import (
    NotFoundError,
    ServiceUnavailableError,
    ValidationError,
)


@asynccontextmanager
async def lifespan(_: FastAPI):
    yield
    close_pool()


app = FastAPI(
    title="Bodegas del Atuel API",
    version="0.1.0",
    description="API REST sobre la base PostgreSQL de Bodegas del Atuel.",
    lifespan=lifespan,
)
app.add_exception_handler(PostgresError, postgres_error_handler())
app.add_exception_handler(StarletteHTTPException, http_exception_handler)
app.add_exception_handler(RequestValidationError, validation_exception_handler)
app.add_exception_handler(NotFoundError, service_error_handler(404))
app.add_exception_handler(ValidationError, service_error_handler(422))
app.add_exception_handler(ServiceUnavailableError, service_error_handler(503))

app.include_router(healthy_router)
app.include_router(catalogos_router)
app.include_router(vinos_router)
app.include_router(clientes_router)
app.include_router(comprobantes_router)
app.include_router(transferencias_router)
app.include_router(ingresos_router)
app.include_router(reportes_router)
