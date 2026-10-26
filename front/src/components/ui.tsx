import { useEffect, type ReactNode } from "react";

import type { ApiError } from "../api";
import {
  AlertIcon,
  ChevronLeftIcon,
  ChevronRightIcon,
  CloseIcon,
} from "./Icons";

export const primaryButtonClass =
  "inline-flex items-center justify-center gap-2 rounded-lg bg-wine-700 px-4 py-2.5 text-sm font-semibold text-white shadow-sm transition hover:bg-wine-800 focus:outline-none focus-visible:ring-2 focus-visible:ring-wine-400 focus-visible:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50";

export const secondaryButtonClass =
  "inline-flex items-center justify-center gap-2 rounded-lg border border-[#E2D4D7] bg-white px-4 py-2.5 text-sm font-semibold text-wine-800 shadow-sm transition hover:border-wine-400 hover:bg-wine-50 focus:outline-none focus-visible:ring-2 focus-visible:ring-wine-400 focus-visible:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50";

export const ghostButtonClass =
  "inline-flex items-center justify-center gap-2 rounded-lg px-3 py-2 text-sm font-semibold text-wine-700 transition hover:bg-wine-50 focus:outline-none focus-visible:ring-2 focus-visible:ring-wine-400 disabled:cursor-not-allowed disabled:opacity-50";

export const dangerButtonClass =
  "inline-flex items-center justify-center gap-2 rounded-lg border border-rose-200 bg-white px-4 py-2.5 text-sm font-semibold text-rose-700 shadow-sm transition hover:bg-rose-50 focus:outline-none focus-visible:ring-2 focus-visible:ring-rose-300 focus-visible:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50";

export const inputClass =
  "w-full rounded-lg border border-[#E2D4D7] bg-white px-3 py-2.5 text-sm text-wine-900 shadow-sm outline-none transition placeholder:text-wine-900/35 focus:border-wine-400 focus:ring-2 focus:ring-wine-200 disabled:cursor-not-allowed disabled:bg-slate-50 disabled:text-slate-400";

export const labelClass = "mb-1.5 block text-xs font-bold text-wine-800";

export const cardClass =
  "rounded-xl border border-[#E7DADD] bg-white shadow-[0_8px_24px_rgba(88,24,37,0.05)]";

interface ErrorBannerProps {
  error: ApiError | string | null;
  title?: string;
  onRetry?: () => void;
}

export function ErrorBanner({ error, title, onRetry }: ErrorBannerProps) {
  if (!error) return null;

  const message = typeof error === "string" ? error : error.message;
  const sqlstate = typeof error === "string" ? undefined : error.codigoSqlstate;
  const detalles = typeof error === "string" ? undefined : error.detalles;

  return (
    <div
      role="alert"
      className="rounded-xl border border-rose-200 bg-rose-50/80 p-4 text-rose-900"
    >
      <div className="flex gap-3">
        <AlertIcon className="mt-0.5 h-5 w-5 shrink-0 text-rose-700" />
        <div className="min-w-0 flex-1">
          <p className="text-sm font-bold">{title ?? "Error de la API"}</p>
          <p className="mt-1 break-words text-sm leading-6">{message}</p>
          {sqlstate ? (
            <p className="mt-2 font-mono text-xs text-rose-700">
              codigo_sqlstate: {sqlstate}
            </p>
          ) : null}
          {detalles !== undefined ? (
            <pre className="mt-2 max-h-48 overflow-auto whitespace-pre-wrap rounded-lg bg-white/70 p-3 font-mono text-xs leading-5 text-rose-800">
              {JSON.stringify(detalles, null, 2)}
            </pre>
          ) : null}
          {onRetry ? (
            <button
              type="button"
              onClick={onRetry}
              className="mt-3 rounded-md border border-rose-300 bg-white px-3 py-1.5 text-xs font-bold text-rose-800 transition hover:bg-rose-100"
            >
              Reintentar
            </button>
          ) : null}
        </div>
      </div>
    </div>
  );
}

interface NoticeProps {
  children: ReactNode;
}

export function Notice({ children }: NoticeProps) {
  return (
    <div
      role="status"
      className="rounded-xl border border-emerald-200 bg-emerald-50 px-4 py-3 text-sm font-semibold text-emerald-800"
    >
      {children}
    </div>
  );
}

interface LoadingBlockProps {
  label?: string;
}

export function LoadingBlock({ label = "Cargando datos..." }: LoadingBlockProps) {
  return (
    <div className="flex items-center justify-center gap-3 rounded-xl border border-[#E7DADD] bg-white px-4 py-12 text-sm text-wine-800">
      <span className="h-4 w-4 animate-spin rounded-full border-2 border-wine-200 border-t-wine-700" />
      {label}
    </div>
  );
}

interface EmptyStateProps {
  title: string;
  description?: string;
  action?: ReactNode;
}

export function EmptyState({ title, description, action }: EmptyStateProps) {
  return (
    <div className="flex flex-col items-center justify-center gap-2 rounded-xl border border-dashed border-[#E2D4D7] bg-white px-6 py-12 text-center">
      <p className="text-sm font-bold text-wine-900">{title}</p>
      {description ? (
        <p className="max-w-md text-sm leading-6 text-wine-900/55">
          {description}
        </p>
      ) : null}
      {action ? <div className="mt-2">{action}</div> : null}
    </div>
  );
}

interface BadgeProps {
  children: ReactNode;
  className?: string;
}

export function Badge({ children, className }: BadgeProps) {
  return (
    <span
      className={`inline-flex items-center rounded-full border px-2.5 py-1 text-xs font-bold ${className ?? ""}`}
    >
      {children}
    </span>
  );
}

interface PageHeaderProps {
  title: string;
  subtitle: string;
  actions?: ReactNode;
}

export function PageHeader({ title, subtitle, actions }: PageHeaderProps) {
  return (
    <div className="mb-6 flex flex-wrap items-start justify-between gap-4">
      <div>
        <h1 className="text-2xl font-bold tracking-tight text-wine-900">
          {title}
        </h1>
        <p className="mt-1 max-w-2xl text-sm leading-6 text-wine-900/55">
          {subtitle}
        </p>
      </div>
      {actions ? <div className="flex flex-wrap gap-2">{actions}</div> : null}
    </div>
  );
}

interface ModalProps {
  title: string;
  subtitle?: string;
  onClose: () => void;
  children: ReactNode;
  widthClass?: string;
}

export function Modal({
  title,
  subtitle,
  onClose,
  children,
  widthClass = "max-w-3xl",
}: ModalProps) {
  useEffect(() => {
    function handleKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape") onClose();
    }
    document.addEventListener("keydown", handleKeyDown);
    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      document.removeEventListener("keydown", handleKeyDown);
      document.body.style.overflow = previousOverflow;
    };
  }, [onClose]);

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-wine-950/55 p-4 backdrop-blur-sm"
      onMouseDown={(event) => {
        if (event.target === event.currentTarget) onClose();
      }}
    >
      <div
        role="dialog"
        aria-modal="true"
        aria-label={title}
        className={`flex max-h-[92vh] w-full flex-col overflow-hidden rounded-2xl border border-white/20 bg-white shadow-2xl ${widthClass}`}
      >
        <div className="flex items-start justify-between gap-4 border-b border-[#E7DADD] bg-wine-50/60 px-5 py-4">
          <div>
            <h2 className="text-lg font-bold text-wine-900">{title}</h2>
            {subtitle ? (
              <p className="mt-0.5 text-sm text-wine-900/55">{subtitle}</p>
            ) : null}
          </div>
          <button
            type="button"
            onClick={onClose}
            aria-label="Cerrar"
            className="rounded-lg p-2 text-wine-700 transition hover:bg-wine-100 focus:outline-none focus-visible:ring-2 focus-visible:ring-wine-400"
          >
            <CloseIcon />
          </button>
        </div>
        <div className="overflow-y-auto p-5">{children}</div>
      </div>
    </div>
  );
}

interface PaginationProps {
  page: number;
  hasNext: boolean;
  loading?: boolean;
  onPrevious: () => void;
  onNext: () => void;
}

export function Pagination({
  page,
  hasNext,
  loading = false,
  onPrevious,
  onNext,
}: PaginationProps) {
  return (
    <div className="flex items-center justify-between gap-4 border-t border-[#E7DADD] px-4 py-3">
      <button
        type="button"
        onClick={onPrevious}
        disabled={page <= 1 || loading}
        className={secondaryButtonClass}
      >
        <ChevronLeftIcon className="h-4 w-4" />
        Anterior
      </button>
      <span className="text-xs font-bold text-wine-900/55">Página {page}</span>
      <button
        type="button"
        onClick={onNext}
        disabled={!hasNext || loading}
        className={secondaryButtonClass}
      >
        Siguiente
        <ChevronRightIcon className="h-4 w-4" />
      </button>
    </div>
  );
}

interface FormFieldProps {
  label: string;
  htmlFor: string;
  children: ReactNode;
  hint?: string;
  className?: string;
}

export function FormField({
  label,
  htmlFor,
  children,
  hint,
  className,
}: FormFieldProps) {
  return (
    <div className={className}>
      <label htmlFor={htmlFor} className={labelClass}>
        {label}
      </label>
      {children}
      {hint ? <p className="mt-1.5 text-xs text-wine-900/50">{hint}</p> : null}
    </div>
  );
}
