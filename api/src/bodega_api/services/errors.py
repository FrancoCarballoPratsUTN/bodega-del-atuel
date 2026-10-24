"""Errores de la capa de negocio, independientes de HTTP."""


class ServiceError(Exception):
    """Error controlado de un caso de uso."""


class NotFoundError(ServiceError):
    """El recurso solicitado no existe o está inactivo."""


class ValidationError(ServiceError):
    """La entrada es válida para HTTP pero rechazada por el caso de uso."""


class ServiceUnavailableError(ServiceError):
    """Una dependencia externa, como PostgreSQL, no está disponible."""
