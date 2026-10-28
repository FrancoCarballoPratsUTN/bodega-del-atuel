import type { Numeric, Sala } from "./types";

const numberFormat = new Intl.NumberFormat("es-AR", {
  maximumFractionDigits: 2,
});

const moneyFormat = new Intl.NumberFormat("es-AR", {
  style: "currency",
  currency: "ARS",
  minimumFractionDigits: 2,
});

function asNumber(value: Numeric): number {
  const parsed = typeof value === "number" ? value : Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

export function formatNumber(value: Numeric): string {
  return numberFormat.format(asNumber(value));
}

export function formatMoney(value: Numeric): string {
  return moneyFormat.format(asNumber(value));
}

export function formatPercent(value: Numeric): string {
  return `${numberFormat.format(asNumber(value))}%`;
}

function formatDateValue(value: string, options: Intl.DateTimeFormatOptions): string {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return new Intl.DateTimeFormat("es-AR", options).format(date);
}

export function formatDate(value: string): string {
  return formatDateValue(value, { dateStyle: "medium", timeZone: "UTC" });
}

export function formatDateTime(value: string): string {
  return formatDateValue(value, {
    dateStyle: "medium",
    timeStyle: "short",
    timeZone: "America/Argentina/Mendoza",
  });
}

export function tipoLabel(tipo: string): string {
  return tipo ? tipo.charAt(0).toLocaleUpperCase("es-AR") + tipo.slice(1) : tipo;
}

export function tipoBadgeClass(_tipo: string): string {
  return "bg-wine-100 text-wine-800";
}

export function estadoLabel(estado: string): string {
  const label = estado.replace(/_/g, " ");
  return label ? label.charAt(0).toLocaleUpperCase("es-AR") + label.slice(1) : label;
}

export function estadoBadgeClass(_estado: string): string {
  return "bg-wine-100 text-wine-800";
}

export function salaLabel(sala: Sala): string {
  return `${sala.calle} ${sala.numero}, ${sala.localidad}`;
}
