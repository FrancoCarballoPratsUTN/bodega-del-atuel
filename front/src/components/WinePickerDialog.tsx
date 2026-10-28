import { useState } from "react";

import { listVinos, toApiError, type ApiError } from "../api";
import { useCatalogos } from "../context/CatalogosContext";
import { useApiResource } from "../hooks/useApiResource";
import {
  formatMoney,
  tipoBadgeClass,
  tipoLabel,
} from "../display";
import type { VinoResumen } from "../types";
import { PAGE_SIZE } from "../types";
import {
  Badge,
  EmptyState,
  ErrorBanner,
  FormField,
  LoadingBlock,
  Modal,
  Pagination,
  inputClass,
  primaryButtonClass,
  secondaryButtonClass,
} from "./ui";
import {
  EMPTY_VINO_FILTERS,
  VinoFilters,
  parseAniadaFilter,
  type VinoFilterValues,
} from "./VinoFilters";
import { PlusIcon } from "./Icons";

interface WinePickerDialogProps {
  title?: string;
  disabledCodes: Set<number>;
  onClose: () => void;
  onAdd: (vino: VinoResumen, cantidad: number) => Promise<void> | void;
}

export function WinePickerDialog({
  title = "Agregar vino",
  disabledCodes,
  onClose,
  onAdd,
}: WinePickerDialogProps) {
  const { data: catalogos } = useCatalogos();
  const [filters, setFilters] = useState<VinoFilterValues>(EMPTY_VINO_FILTERS);
  const [page, setPage] = useState(1);
  const [cantidad, setCantidad] = useState(1);
  const [addingCode, setAddingCode] = useState<number | null>(null);
  const [addError, setAddError] = useState<ApiError | null>(null);

  const aniada = parseAniadaFilter(filters.aniada);
  const resource = useApiResource(
    (signal) =>
      listVinos(
        {
          pagina: page,
          porPagina: PAGE_SIZE,
          tipo: filters.tipo || undefined,
          cepa: filters.cepa || undefined,
          bodega: filters.bodega || undefined,
          aniada,
        },
        signal,
      ),
    [page, filters],
  );

  function updateFilters(next: VinoFilterValues) {
    setFilters(next);
    setPage(1);
  }

  function updateCantidad(value: string) {
    const parsed = Number(value);
    setCantidad(Number.isFinite(parsed) && parsed >= 1 ? Math.trunc(parsed) : 1);
  }

  async function handleAdd(vino: VinoResumen) {
    setAddingCode(vino.cod_vino);
    setAddError(null);
    try {
      await onAdd(vino, cantidad);
      onClose();
    } catch (reason) {
      setAddError(toApiError(reason));
    } finally {
      setAddingCode(null);
    }
  }

  const wines = resource.data?.items ?? [];
  const hasNext = wines.length === PAGE_SIZE;

  return (
    <Modal
      title={title}
      subtitle="Buscá vinos y elegí la cantidad que querés agregar."
      onClose={onClose}
      widthClass="max-w-5xl"
    >
      <VinoFilters
        value={filters}
        catalogos={catalogos}
        idPrefix="picker"
        onChange={updateFilters}
      />

      <div className="mt-4 flex flex-wrap items-end justify-between gap-3 rounded-xl border border-[#E7DADD] bg-wine-50/50 p-4">
        <FormField
          label="Cantidad para el renglón"
          htmlFor="picker-cantidad"
          className="w-40"
        >
          <input
            id="picker-cantidad"
            type="number"
            min={1}
            step={1}
            value={cantidad}
            onChange={(event) => updateCantidad(event.target.value)}
            className={inputClass}
          />
        </FormField>
        <p className="pb-1 text-xs text-wine-900/45">
          Esta pantalla no muestra stock ni calcula importes.
        </p>
      </div>

      {addError ? (
        <div className="mt-4">
          <ErrorBanner error={addError} title="No se pudo agregar el vino" />
        </div>
      ) : null}

      {resource.error ? (
        <div className="mt-4">
          <ErrorBanner
            error={resource.error}
            title="No se pudo cargar el listado de vinos"
            onRetry={resource.reload}
          />
        </div>
      ) : null}

      <div className="mt-4">
        {!resource.data && resource.loading ? (
          <LoadingBlock label="Cargando vinos..." />
        ) : wines.length === 0 ? (
          <EmptyState
            title="No hay vinos con esos filtros"
            description="Probá modificando el tipo, la cepa, la bodega o la añada."
          />
        ) : (
          <div
            className={`overflow-hidden rounded-xl border border-[#E7DADD] ${
              resource.loading ? "opacity-60" : ""
            }`}
          >
            <div className="overflow-x-auto">
              <table className="w-full min-w-[720px] text-left text-sm">
                <thead className="bg-wine-50 text-xs uppercase tracking-wide text-wine-800/60">
                  <tr>
                    <th className="px-4 py-3 font-bold">Código</th>
                    <th className="px-4 py-3 font-bold">Vino</th>
                    <th className="px-4 py-3 font-bold">Bodega</th>
                    <th className="px-4 py-3 font-bold">Tipo</th>
                    <th className="px-4 py-3 font-bold">Añada</th>
                    <th className="px-4 py-3 text-right font-bold">Precio</th>
                    <th className="px-4 py-3 text-right font-bold">Acción</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-[#F1E7E9]">
                  {wines.map((vino) => {
                    const alreadyAdded = disabledCodes.has(vino.cod_vino);
                    return (
                      <tr key={vino.cod_vino} className="hover:bg-wine-50/40">
                        <td className="px-4 py-3 font-mono text-xs text-wine-900/60">
                          #{vino.cod_vino}
                        </td>
                        <td className="px-4 py-3 font-semibold text-wine-900">
                          {vino.nombre}
                        </td>
                        <td className="px-4 py-3 text-wine-900/65">
                          {vino.bodega}
                        </td>
                        <td className="px-4 py-3">
                          <Badge className={tipoBadgeClass(vino.tipo)}>
                            {tipoLabel(vino.tipo)}
                          </Badge>
                        </td>
                        <td className="px-4 py-3 text-wine-900/65">
                          {vino.aniada}
                        </td>
                        <td className="px-4 py-3 text-right font-semibold text-wine-900">
                          {formatMoney(vino.precio)}
                        </td>
                        <td className="px-4 py-3 text-right">
                          <button
                            type="button"
                            onClick={() => handleAdd(vino)}
                            disabled={alreadyAdded || addingCode !== null}
                            className={`${primaryButtonClass} px-3 py-2 text-xs`}
                          >
                            {alreadyAdded ? (
                              "Ya agregado"
                            ) : addingCode === vino.cod_vino ? (
                              "Agregando..."
                            ) : (
                              <>
                                <PlusIcon className="h-4 w-4" />
                                Agregar
                              </>
                            )}
                          </button>
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
            <Pagination
              page={page}
              hasNext={hasNext}
              loading={resource.loading}
              onPrevious={() => setPage((current) => Math.max(1, current - 1))}
              onNext={() => setPage((current) => current + 1)}
            />
          </div>
        )}
      </div>

      <div className="mt-5 flex justify-end">
        <button type="button" onClick={onClose} className={secondaryButtonClass}>
          Cerrar
        </button>
      </div>
    </Modal>
  );
}
