export type Screen =
  | "catalogo"
  | "vino-form"
  | "venta"
  | "transferencias"
  | "tablero";

export type Numeric = number | string;

export interface Sala {
  id_sala: number;
  calle: string;
  numero: number;
  cp_localidad: number;
  localidad: string;
  dia_cierre: string;
  activo: boolean;
}

export interface Cepa {
  id_cepa: number;
  nombre: string;
  tipo: string;
}

export interface Bodega {
  cuit_bodega: string;
  razon_social: string;
  activo: boolean;
}

export interface Catalogos {
  salas: Sala[];
  cepas: Cepa[];
  bodegas: Bodega[];
}

export interface VinoResumen {
  cod_vino: number;
  nombre: string;
  tipo: string;
  aniada: number;
  volumen: Numeric;
  graduacion: Numeric;
  precio: Numeric;
  bodega: string;
}

export interface ComposicionVino {
  id_cepa: number;
  nombre: string;
  tipo: string;
  porcentaje: Numeric;
}

export interface MaridajeVino {
  id_maridaje: number;
  nombre: string;
  temperatura_servicio: Numeric;
}

export interface VinoDetalle extends VinoResumen {
  cuit_bodega: string;
  cepas: ComposicionVino[];
  maridajes: MaridajeVino[];
}

export interface VinosPage {
  items: VinoResumen[];
  pagina: number;
  por_pagina: number;
  cantidad: number;
}

export interface Cliente {
  id_cliente: number;
  cp_localidad: number;
  nombre_razon_social: string;
  tipo_doc: string;
  nro_doc: string;
  direccion: string;
  fecha_alta: string;
  descuento: Numeric;
  tipo_cliente: string;
  activo: boolean;
  zona_cobertura?: string | null;
  nro_habilitacion?: string | null;
  pais_destino?: string | null;
}

export interface ClientesPage {
  items: Cliente[];
  pagina: number;
  por_pagina: number;
  cantidad: number;
}

export interface ComprobanteRenglon {
  cod_vino: number;
  cantidad: number;
  precio_unitario: Numeric;
  descuento: Numeric;
  subtotal: Numeric;
}

export interface Comprobante {
  nro_comprobante: number;
  id_cliente: number;
  id_sala: number;
  fecha: string;
  subtotal: Numeric;
  descuento: Numeric;
  total: Numeric;
  renglones: ComprobanteRenglon[];
}

export interface Transferencia {
  codigo: number;
  id_sala: number;
  fecha_confeccion: string;
  estado: string;
}

export interface TopVino {
  cod_vino: number;
  nombre: string;
  botellas_vendidas: Numeric;
}

export interface VentaSala {
  id_sala: number;
  monto_total_ventas: Numeric;
}

export interface VinoSinStock {
  cod_vino: number;
  nombre: string;
  stock_sala: Numeric;
  stock_deposito: Numeric;
}

export interface ComposicionInput {
  id_cepa: number;
  porcentaje: number;
}

export interface VinoPayload {
  cuit_bodega: string;
  nombre: string;
  tipo: string;
  aniada: number;
  volumen: number;
  graduacion: number;
  precio: number;
  cepas: ComposicionInput[];
}

export interface VinoCreatePayload extends VinoPayload {
  maridajes: number[];
}

export interface ComprobantePayload {
  id_cliente: number;
  id_sala: number;
  renglones: { cod_vino: number; cantidad: number }[];
}

export const TIPOS_VINO = [
  { value: "tinto", label: "Tinto" },
  { value: "blanco", label: "Blanco" },
  { value: "rosado", label: "Rosado" },
  { value: "espumante", label: "Espumante" },
] as const;

export const PAGE_SIZE = 20;
