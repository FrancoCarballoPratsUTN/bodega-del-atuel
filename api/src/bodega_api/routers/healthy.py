"""Router para verificación de estado del servicio."""

from fastapi import APIRouter

from bodega_api.services import healthy as healthy_service

router = APIRouter(tags=["Healthy"])


@router.get("/healthy")
def healthy_check() -> dict[str, str]:
    healthy_service.check_database()
    return {
        "status": "ok",
        "database": "available",
    }
