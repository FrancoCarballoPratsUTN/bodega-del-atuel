import { useEffect, useState } from "react";

import { searchClientes, toApiError, type ApiError } from "../api";
import type { Cliente } from "../types";
import { formatPercent } from "../lib/display";
import { ErrorBanner, ghostButtonClass, inputClass, labelClass } from "./ui";
import { SearchIcon } from "./Icons";

interface ClientSearchProps {
  selected: Cliente | null;
  onSelect: (cliente: Cliente | null) => void;
}

export function ClientSearch({ selected, onSelect }: ClientSearchProps) {
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<Cliente[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<ApiError | null>(null);

  useEffect(() => {
    if (selected || query.trim().length < 2) {
      setResults([]);
      setError(null);
      setLoading(false);
      return;
    }

    const controller = new AbortController();
    const timer = window.setTimeout(() => {
      setLoading(true);
      searchClientes(query.trim(), controller.signal)
        .then((clientes) => {
          if (controller.signal.aborted) return;
          setResults(clientes);
          setError(null);
        })
        .catch((reason: unknown) => {
          if (controller.signal.aborted) return;
          setError(toApiError(reason));
        })
        .finally(() => {
          if (!controller.signal.aborted) setLoading(false);
        });
    }, 350);

    return () => {
      window.clearTimeout(timer);
      controller.abort();
    };
  }, [query, selected]);

  if (selected) {
    return (
      <div className="rounded-xl border border-wine-200 bg-wine-50/70 p-4">
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div>
            <p className="text-sm font-bold text-wine-900">
              {selected.nombre_razon_social}
            </p>
            <p className="mt-1 text-xs text-wine-900/60">
              {selected.tipo_doc} {selected.nro_doc} · {selected.tipo_cliente}
            </p>
            <p className="mt-1 text-xs text-wine-900/60">
              Descuento registrado: {formatPercent(selected.descuento)}
            </p>
            {selected.direccion ? (
              <p className="mt-1 text-xs text-wine-900/45">
                {selected.direccion}
              </p>
            ) : null}
          </div>
          <button
            type="button"
            onClick={() => {
              onSelect(null);
              setQuery("");
            }}
            className={ghostButtonClass}
          >
            Cambiar cliente
          </button>
        </div>
      </div>
    );
  }

  return (
    <div>
      <label htmlFor="cliente-busqueda" className={labelClass}>
        Cliente
      </label>
      <div className="relative">
        <SearchIcon className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-wine-900/40" />
        <input
          id="cliente-busqueda"
          type="search"
          autoComplete="off"
          placeholder="Buscar por razón social o documento"
          value={query}
          onChange={(event) => setQuery(event.target.value)}
          className={`${inputClass} pl-9`}
        />
        {loading ? (
          <span className="absolute right-3 top-1/2 h-4 w-4 -translate-y-1/2 animate-spin rounded-full border-2 border-wine-200 border-t-wine-700" />
        ) : null}
      </div>
      <p className="mt-1.5 text-xs text-wine-900/45">
        Ingresá al menos dos caracteres. Los resultados provienen de la API.
      </p>

      {error ? (
        <div className="mt-3">
          <ErrorBanner
            error={error}
            title="No se pudo buscar el cliente"
          />
        </div>
      ) : null}

      {query.trim().length >= 2 && !loading ? (
        <div className="mt-3 overflow-hidden rounded-xl border border-[#E2D4D7] bg-white">
          {results.length === 0 ? (
            <p className="px-4 py-5 text-sm text-wine-900/50">
              Sin coincidencias para esa búsqueda.
            </p>
          ) : (
            <ul className="divide-y divide-[#F1E7E9]">
              {results.map((cliente) => (
                <li key={cliente.id_cliente}>
                  <button
                    type="button"
                    onClick={() => onSelect(cliente)}
                    className="flex w-full items-center justify-between gap-4 px-4 py-3 text-left transition hover:bg-wine-50 focus:outline-none focus-visible:bg-wine-50"
                  >
                    <span>
                      <span className="block text-sm font-semibold text-wine-900">
                        {cliente.nombre_razon_social}
                      </span>
                      <span className="mt-0.5 block text-xs text-wine-900/50">
                        {cliente.tipo_doc} {cliente.nro_doc} ·{" "}
                        {cliente.tipo_cliente}
                      </span>
                    </span>
                    <span className="shrink-0 text-xs font-bold text-wine-700">
                      {formatPercent(cliente.descuento)}
                    </span>
                  </button>
                </li>
              ))}
            </ul>
          )}
        </div>
      ) : null}
    </div>
  );
}
