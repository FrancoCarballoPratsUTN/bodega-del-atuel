from datetime import date
from decimal import Decimal
from typing import Literal

from pydantic import BaseModel, Field, model_validator


class ComposicionInput(BaseModel):
    id_cepa: int = Field(gt=0)
    porcentaje: Decimal = Field(gt=0, le=100)


class VinoBase(BaseModel):
    cuit_bodega: str = Field(min_length=11, max_length=11, pattern=r"^\d{11}$")
    nombre: str = Field(min_length=1, max_length=150)
    tipo: str = Field(min_length=1, max_length=50)
    aniada: int = Field(ge=1900, le=2100)
    volumen: Decimal = Field(gt=0)
    graduacion: Decimal = Field(ge=0, le=100)
    precio: Decimal = Field(gt=0)


class VinoCreate(VinoBase):
    cepas: list[ComposicionInput] = Field(min_length=1)
    maridajes: list[int] = Field(default_factory=list)


class VinoUpdate(VinoBase):
    cepas: list[ComposicionInput] | None = None
    maridajes: list[int] | None = None


class ClienteInput(BaseModel):
    cp_localidad: int
    nombre_razon_social: str = Field(min_length=1, max_length=150)
    tipo_doc: str = Field(min_length=1, max_length=20)
    nro_doc: str = Field(min_length=1, max_length=50)
    direccion: str = Field(min_length=1, max_length=200)
    fecha_alta: date
    descuento: Decimal = Field(ge=0, le=100)
    tipo_cliente: Literal["Socio", "Distribuidor", "Exportador"]
    zona_cobertura: str | None = Field(default=None, max_length=150)
    nro_habilitacion: str | None = Field(default=None, max_length=50)
    pais_destino: str | None = Field(default=None, max_length=100)

    @model_validator(mode="after")
    def validate_subtype_fields(self):
        if self.tipo_cliente == "Distribuidor":
            missing = not self.zona_cobertura or not self.nro_habilitacion
            if missing:
                raise ValueError(
                    "Un distribuidor requiere zona_cobertura y nro_habilitacion."
                )
        elif self.tipo_cliente == "Exportador" and not self.pais_destino:
            raise ValueError("Un exportador requiere pais_destino.")
        return self


class RenglonComprobanteInput(BaseModel):
    cod_vino: int = Field(gt=0)
    cantidad: int = Field(gt=0)


class ComprobanteInput(BaseModel):
    id_cliente: int = Field(gt=0)
    id_sala: int = Field(gt=0)
    renglones: list[RenglonComprobanteInput] = Field(min_length=1)


class TransferenciaInput(BaseModel):
    id_sala: int = Field(gt=0)


class IngresoInput(BaseModel):
    cod_transportista: int = Field(gt=0)
    cuit_bodega: str = Field(min_length=11, max_length=11)


class RenglonMovimientoInput(BaseModel):
    cod_vino: int = Field(gt=0)
    cantidad: int = Field(gt=0)
