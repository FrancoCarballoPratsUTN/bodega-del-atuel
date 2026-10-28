import type {
  Catalogos,
  Cliente,
  ClientesPage,
  Comprobante,
  ComprobantePayload,
  TopVino,
  Transferencia,
  VentaSala,
  VinoCreatePayload,
  VinoDetalle,
  VinoPayload,
  VinoSinStock,
  VinosPage,
} from "./types";

const API_BASE =
  (import.meta.env.VITE_API_URL as string | undefined)?.replace(/\/$/, "") ||
  "/api";

interface ErrorPayload {
  error?: string;
  codigo_sqlstate?: string;
  detalles?: unknown;
}

export class ApiError extends Error {
  readonly status: number;
  readonly codigoSqlstate?: string;
  readonly detalles?: unknown;

  constructor(
    message: string,
    status: number,
    codigoSqlstate?: string,
    detalles?: unknown,
  ) {
    super(message);
    this.name = "ApiError";
    this.status = status;
    this.codigoSqlstate = codigoSqlstate;
    this.detalles = detalles;
  }
}

export function toApiError(error: unknown): ApiError {
  if (error instanceof ApiError) return error;
  if (error instanceof Error) return new ApiError(error.message, 0);
  return new ApiError("Error desconocido al comunicarse con la API.", 0);
}

export function humanizeApiError(error: ApiError | string): string {
  if (typeof error === "string") return error;

  const backendMessage = error.message.trim();
  const normalized = backendMessage.toLowerCase();

  if (error.status === 0) {
    return "No pudimos conectar con el servidor. Revisá tu conexión e intentá de nuevo.";
  }

  switch (error.codigoSqlstate) {
    case "23505":
      return "Ya existe un registro con esos datos. Revisá si ya fue cargado.";
    case "23503":
      return "No se puede completar la operación porque faltan datos relacionados o están en uso.";
    case "23514":
      return "Alguno de los datos no cumple las reglas permitidas. Revisalo e intentá de nuevo.";
    case "23502":
      return "Faltan completar datos obligatorios.";
    case "22P02":
      return "Hay un dato con un formato inválido. Revisalo e intentá de nuevo.";
  }

  if (normalized.includes("duplicate key") || normalized.includes("unique constraint")) {
    return "Ya existe un registro con esos datos. Revisá si ya fue cargado.";
  }
  if (normalized.includes("stock insuficiente")) return backendMessage;
  if (normalized.includes("composición") && normalized.includes("sumar")) {
    return "La composición de cepas debe sumar exactamente 100%.";
  }
  if (normalized.includes("transición inválida")) {
    return "No se puede avanzar la transferencia desde su estado actual.";
  }
  if (normalized.includes("en_confeccion") && normalized.includes("renglones")) {
    return "Solo se pueden modificar los productos mientras la transferencia está en confección.";
  }

  if (error.status === 409) {
    return "No se pudo completar porque los datos entran en conflicto con un registro existente.";
  }
  if (error.status === 422 || error.status === 400) {
    return backendMessage || "Revisá los datos ingresados e intentá de nuevo.";
  }
  if (error.status >= 500) {
    return "Ocurrió un problema en el servidor. Intentá de nuevo en unos minutos.";
  }

  return backendMessage || "No se pudo completar la operación. Intentá de nuevo.";
}

type QueryValue = string | number | undefined | null;

function withQuery(path: string, values: Record<string, QueryValue>): string {
  const search = new URLSearchParams();
  for (const [key, value] of Object.entries(values)) {
    if (value === undefined || value === null || value === "") continue;
    search.set(key, String(value));
  }
  const query = search.toString();
  return query ? `${path}?${query}` : path;
}

async function request<T>(
  path: string,
  options: RequestInit = {},
): Promise<T> {
  const response = await fetch(`${API_BASE}${path}`, {
    ...options,
    headers: {
      ...(options.body ? { "Content-Type": "application/json" } : {}),
      ...options.headers,
    },
  });

  if (response.status === 204) return undefined as T;

  const contentType = response.headers.get("content-type") ?? "";
  const body: unknown = contentType.includes("application/json")
    ? await response.json().catch(() => null)
    : await response.text();

  if (!response.ok) {
    const payload =
      body && typeof body === "object" ? (body as ErrorPayload) : null;
    const message =
      payload?.error ??
      (typeof body === "string" && body.trim()
        ? body
        : `Error HTTP ${response.status}`);
    throw new ApiError(
      message,
      response.status,
      payload?.codigo_sqlstate,
      payload?.detalles,
    );
  }

  return body as T;
}

export interface VinoListFilters {
  pagina: number;
  porPagina: number;
  tipo?: string;
  cepa?: string;
  bodega?: string;
  aniada?: number;
}

export function listVinos(
  filters: VinoListFilters,
  signal?: AbortSignal,
): Promise<VinosPage> {
  const path = withQuery("/vinos", {
    pagina: filters.pagina,
    por_pagina: filters.porPagina,
    tipo: filters.tipo,
    cepa: filters.cepa,
    bodega: filters.bodega,
    aniada: filters.aniada,
  });
  return request<VinosPage>(path, { signal });
}

export function getVino(
  codVino: number,
  signal?: AbortSignal,
): Promise<VinoDetalle> {
  return request<VinoDetalle>(`/vinos/${codVino}`, { signal });
}

export function createVino(payload: VinoCreatePayload): Promise<VinoDetalle> {
  return request<VinoDetalle>("/vinos", {
    method: "POST",
    body: JSON.stringify(payload),
  });
}

export function updateVino(
  codVino: number,
  payload: VinoPayload,
): Promise<VinoDetalle> {
  return request<VinoDetalle>(`/vinos/${codVino}`, {
    method: "PUT",
    body: JSON.stringify(payload),
  });
}

export function searchClientes(
  busqueda: string,
  signal?: AbortSignal,
): Promise<Cliente[]> {
  const path = withQuery("/clientes", {
    busqueda,
    pagina: 1,
    por_pagina: 10,
  });
  return request<ClientesPage>(path, { signal }).then((page) => page.items);
}

export function getCatalogos(signal?: AbortSignal): Promise<Catalogos> {
  return request<Catalogos>("/catalogos", { signal });
}

export function createComprobante(
  payload: ComprobantePayload,
): Promise<Comprobante> {
  return request<Comprobante>("/comprobantes", {
    method: "POST",
    body: JSON.stringify(payload),
  });
}

export function createTransferencia(idSala: number): Promise<Transferencia> {
  return request<Transferencia>("/transferencias", {
    method: "POST",
    body: JSON.stringify({ id_sala: idSala }),
  });
}

export function addTransferenciaRenglon(
  codigo: number,
  codVino: number,
  cantidad: number,
): Promise<void> {
  return request<void>(`/transferencias/${codigo}/renglones`, {
    method: "POST",
    body: JSON.stringify({ cod_vino: codVino, cantidad }),
  });
}

export function terminarTransferencia(codigo: number): Promise<void> {
  return request<void>(`/transferencias/${codigo}/terminar`, {
    method: "POST",
  });
}

export function procesarTransferencia(codigo: number): Promise<void> {
  return request<void>(`/transferencias/${codigo}/procesar`, {
    method: "POST",
  });
}

export function getTopVinos(signal?: AbortSignal): Promise<TopVino[]> {
  return request<TopVino[]>("/reportes/top-vinos", { signal });
}

export function getVentasPorSala(signal?: AbortSignal): Promise<VentaSala[]> {
  return request<VentaSala[]>("/reportes/ventas-por-sala", { signal });
}

export function getVinosSinStock(
  idSala: number,
  signal?: AbortSignal,
): Promise<VinoSinStock[]> {
  return request<VinoSinStock[]>(
    withQuery("/reportes/vinos-sin-stock", { id_sala: idSala }),
    { signal },
  );
}
