import { useState } from "react";

import { listVinos } from "../api";
import { useApiResource } from "../hooks/useApiResource";
import { useCatalogos } from "../context/CatalogosContext";
import {
  formatMoney,
  tipoBadgeClass,
  tipoLabel,
} from "../display";
import { PAGE_SIZE } from "../types";
import {
  EMPTY_VINO_FILTERS,
  VinoFilters,
  parseAniadaFilter,
  type VinoFilterValues,
} from "../components/VinoFilters";
import { VinoDetailModal } from "../components/VinoDetailModal";
import {
  Badge,
  EmptyState,
  ErrorBanner,
  LoadingBlock,
  Notice,
  PageHeader,
  Pagination,
  cardClass,
  ghostButtonClass,
  primaryButtonClass,
} from "../components/ui";
import { EyeIcon, EditIcon, PlusIcon } from "../components/Icons";

interface CatalogoScreenProps {
  notice: string | null;
  onNew: () => void;
  onEdit: (codVino: number) => void;
}

export function CatalogoScreen({
  notice,
  onNew,
  onEdit,
}: CatalogoScreenProps) {
  const { data: catalogos } = useCatalogos();
  const [filters, setFilters] = useState<VinoFilterValues>(EMPTY_VINO_FILTERS);
  const [page, setPage] = useState(1);
  const [detailCode, setDetailCode] = useState<number | null>(null);

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

  const wines = resource.data?.items ?? [];
  const hasNext = wines.length === PAGE_SIZE;

  return (
    <div>
      <PageHeader
        title="Catálogo de vinos"
        subtitle="Buscá vinos por tipo, cepa, bodega o añada y consultá sus detalles."
        actions={
          <button type="button" onClick={onNew} className={primaryButtonClass}>
            <PlusIcon className="h-4 w-4" />
            Alta de vino
          </button>
        }
      />

      {notice ? (
        <div className="mb-5">
          <Notice>{notice}</Notice>
        </div>
      ) : null}

      <section className={`${cardClass} p-4 sm:p-5`}>
        <VinoFilters
          value={filters}
          catalogos={catalogos}
          idPrefix="catalogo"
          onChange={updateFilters}
        />
      </section>

      {resource.error ? (
        <div className="mt-5">
          <ErrorBanner
            error={resource.error}
            title="No se pudo cargar el catálogo"
            onRetry={resource.reload}
          />
        </div>
      ) : null}

      <section className={`${cardClass} mt-5 overflow-hidden`}>
        {!resource.data && resource.loading ? (
          <div className="p-4">
            <LoadingBlock label="Cargando vinos..." />
          </div>
        ) : wines.length === 0 ? (
          <div className="p-4">
            <EmptyState
              title="No hay vinos con esos filtros"
              description="Modificá los filtros o registrá un vino nuevo."
              action={
                <button
                  type="button"
                  onClick={onNew}
                  className={primaryButtonClass}
                >
                  <PlusIcon className="h-4 w-4" />
                  Alta de vino
                </button>
              }
            />
          </div>
        ) : (
          <div className={resource.loading ? "opacity-60" : ""}>
            <div className="overflow-x-auto">
              <table className="w-full min-w-[820px] text-left text-sm">
                <thead className="bg-wine-50 text-xs uppercase tracking-wide text-wine-800/60">
                  <tr>
                    <th className="px-4 py-3 font-bold">Código</th>
                    <th className="px-4 py-3 font-bold">Vino</th>
                    <th className="px-4 py-3 font-bold">Bodega</th>
                    <th className="px-4 py-3 font-bold">Tipo</th>
                    <th className="px-4 py-3 font-bold">Añada</th>
                    <th className="px-4 py-3 text-right font-bold">Precio</th>
                    <th className="px-4 py-3 text-right font-bold">Acciones</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-[#F1E7E9]">
                  {wines.map((vino) => (
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
                      <td className="px-4 py-3">
                        <div className="flex justify-end gap-1">
                          <button
                            type="button"
                            onClick={() => setDetailCode(vino.cod_vino)}
                            className={ghostButtonClass}
                            title="Ver detalle"
                          >
                            <EyeIcon className="h-4 w-4" />
                            Ver
                          </button>
                          <button
                            type="button"
                            onClick={() => onEdit(vino.cod_vino)}
                            className={ghostButtonClass}
                            title="Editar vino"
                          >
                            <EditIcon className="h-4 w-4" />
                            Editar
                          </button>
                        </div>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            <div className="flex items-center justify-between gap-3 border-t border-[#E7DADD] px-4 py-2 text-xs text-wine-900/45">
              <span>
                {resource.data?.cantidad ?? 0} vino(s) en esta página
              </span>
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
      </section>

      {detailCode !== null ? (
        <VinoDetailModal
          codVino={detailCode}
          onClose={() => setDetailCode(null)}
          onEdit={(codVino) => {
            setDetailCode(null);
            onEdit(codVino);
          }}
        />
      ) : null}
    </div>
  );
}
