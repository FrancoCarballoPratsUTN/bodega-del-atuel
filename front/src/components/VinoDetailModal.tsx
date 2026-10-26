import type { ReactNode } from "react";

import { getVino } from "../api";
import { useApiResource } from "../hooks/useApiResource";
import {
  formatMoney,
  formatNumber,
  formatPercent,
  tipoBadgeClass,
  tipoLabel,
} from "../lib/display";
import {
  Badge,
  ErrorBanner,
  LoadingBlock,
  Modal,
  primaryButtonClass,
  secondaryButtonClass,
} from "./ui";
import { EditIcon } from "./Icons";

interface VinoDetailModalProps {
  codVino: number;
  onClose: () => void;
  onEdit: (codVino: number) => void;
}

export function VinoDetailModal({
  codVino,
  onClose,
  onEdit,
}: VinoDetailModalProps) {
  const resource = useApiResource(
    (signal) => getVino(codVino, signal),
    [codVino],
  );

  return (
    <Modal
      title={resource.data?.nombre ?? "Detalle de vino"}
      subtitle={
        resource.data
          ? `Código #${resource.data.cod_vino} · ${resource.data.bodega}`
          : "Información obtenida de la API."
      }
      onClose={onClose}
    >
      {resource.error ? (
        <ErrorBanner
          error={resource.error}
          title="No se pudo cargar el detalle"
          onRetry={resource.reload}
        />
      ) : !resource.data ? (
        <LoadingBlock label="Cargando detalle del vino..." />
      ) : (
        <div className="space-y-6">
          <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
            <DetailItem label="Bodega" value={resource.data.bodega} />
            <DetailItem
              label="Tipo"
              value={
                <Badge className={tipoBadgeClass(resource.data.tipo)}>
                  {tipoLabel(resource.data.tipo)}
                </Badge>
              }
            />
            <DetailItem label="Añada" value={String(resource.data.aniada)} />
            <DetailItem
              label="Volumen"
              value={`${formatNumber(resource.data.volumen)} ml`}
            />
            <DetailItem
              label="Graduación"
              value={`${formatNumber(resource.data.graduacion)}°`}
            />
            <DetailItem
              label="Precio"
              value={formatMoney(resource.data.precio)}
            />
          </div>

          <section>
            <h3 className="text-sm font-bold text-wine-900">Composición</h3>
            {resource.data.cepas.length === 0 ? (
              <p className="mt-2 text-sm text-wine-900/50">
                Sin composición registrada.
              </p>
            ) : (
              <ul className="mt-3 space-y-3">
                {resource.data.cepas.map((cepa) => (
                  <li key={cepa.id_cepa}>
                    <div className="flex items-center justify-between gap-3 text-sm">
                      <span className="font-semibold text-wine-900">
                        {cepa.nombre}
                        <span className="ml-2 text-xs font-normal text-wine-900/45">
                          {cepa.tipo}
                        </span>
                      </span>
                      <span className="font-mono text-xs font-bold text-wine-700">
                        {formatPercent(cepa.porcentaje)}
                      </span>
                    </div>
                    <div className="mt-1.5 h-2 overflow-hidden rounded-full bg-wine-100">
                      <div
                        className="h-full rounded-full bg-wine-500"
                        style={{ width: `${Number(cepa.porcentaje)}%` }}
                      />
                    </div>
                  </li>
                ))}
              </ul>
            )}
          </section>

          <section>
            <h3 className="text-sm font-bold text-wine-900">Maridajes</h3>
            {resource.data.maridajes.length === 0 ? (
              <p className="mt-2 text-sm text-wine-900/50">
                Sin maridajes registrados.
              </p>
            ) : (
              <ul className="mt-3 flex flex-wrap gap-2">
                {resource.data.maridajes.map((maridaje) => (
                  <li
                    key={maridaje.id_maridaje}
                    className="rounded-lg border border-gold-300 bg-gold-100 px-3 py-2 text-xs text-gold-600"
                  >
                    <span className="font-bold">{maridaje.nombre}</span>
                    <span className="ml-2 text-gold-600/70">
                      {formatNumber(maridaje.temperatura_servicio)}°C
                    </span>
                  </li>
                ))}
              </ul>
            )}
          </section>

          <div className="flex flex-wrap justify-end gap-2 border-t border-[#E7DADD] pt-4">
            <button
              type="button"
              onClick={onClose}
              className={secondaryButtonClass}
            >
              Cerrar
            </button>
            <button
              type="button"
              onClick={() => onEdit(resource.data!.cod_vino)}
              className={primaryButtonClass}
            >
              <EditIcon className="h-4 w-4" />
              Editar vino
            </button>
          </div>
        </div>
      )}
    </Modal>
  );
}

function DetailItem({
  label,
  value,
}: {
  label: string;
  value: ReactNode;
}) {
  return (
    <div className="rounded-lg border border-[#E7DADD] bg-wine-50/40 px-3 py-2.5">
      <p className="text-[11px] font-bold uppercase tracking-wide text-wine-900/45">
        {label}
      </p>
      <div className="mt-1 text-sm font-semibold text-wine-900">{value}</div>
    </div>
  );
}
