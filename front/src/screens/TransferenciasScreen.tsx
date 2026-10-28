import { useState } from "react";

import {
  addTransferenciaRenglon,
  createTransferencia,
  procesarTransferencia,
  terminarTransferencia,
  toApiError,
  type ApiError,
} from "../api";
import { useCatalogos } from "../context/CatalogosContext";
import { WinePickerDialog } from "../components/WinePickerDialog";
import {
  estadoBadgeClass,
  estadoLabel,
  formatDate,
  salaLabel,
  tipoLabel,
} from "../display";
import type { Transferencia, VinoResumen } from "../types";
import {
  Badge,
  EmptyState,
  ErrorBanner,
  FormField,
  Notice,
  PageHeader,
  cardClass,
  inputClass,
  primaryButtonClass,
  secondaryButtonClass,
} from "../components/ui";
import { PlusIcon } from "../components/Icons";

interface TransferLine {
  vino: VinoResumen;
  cantidad: number;
}

type PendingAction = "create" | "finish" | "process" | null;

export function TransferenciasScreen() {
  const { data: catalogos } = useCatalogos();
  const [salaId, setSalaId] = useState<number | null>(null);
  const [transfer, setTransfer] = useState<Transferencia | null>(null);
  const [lines, setLines] = useState<TransferLine[]>([]);
  const [pickerOpen, setPickerOpen] = useState(false);
  const [pendingAction, setPendingAction] = useState<PendingAction>(null);
  const [error, setError] = useState<ApiError | null>(null);
  const [message, setMessage] = useState<string | null>(null);

  const activeSalas = catalogos.salas.filter((sala) => sala.activo);
  const selectedSalaId = salaId ?? activeSalas[0]?.id_sala ?? null;
  const currentSala =
    catalogos.salas.find((sala) => sala.id_sala === transfer?.id_sala) ?? null;
  const disabledCodes = new Set(lines.map((line) => line.vino.cod_vino));

  const canCreate = !transfer || transfer.estado === "procesado";
  const canAdd = transfer?.estado === "en_confeccion";
  const canFinish =
    transfer?.estado === "en_confeccion" && lines.length > 0;
  const canProcess = transfer?.estado === "terminado";
  const busy = pendingAction !== null;

  async function createTransfer() {
    if (!selectedSalaId || !canCreate || busy) return;

    setPendingAction("create");
    setError(null);
    setMessage(null);
    try {
      const created = await createTransferencia(selectedSalaId);
      setTransfer(created);
      setLines([]);
      setMessage("Solicitud de transferencia creada.");
    } catch (reason) {
      setError(toApiError(reason));
    } finally {
      setPendingAction(null);
    }
  }

  async function addLine(vino: VinoResumen, cantidad: number) {
    if (!transfer || !canAdd) return;

    setError(null);
    setMessage(null);
    await addTransferenciaRenglon(transfer.codigo, vino.cod_vino, cantidad);
    setLines((current) => [...current, { vino, cantidad }]);
    setMessage("Renglón agregado a la transferencia.");
  }

  async function finishTransfer() {
    if (!transfer || !canFinish || busy) return;

    setPendingAction("finish");
    setError(null);
    setMessage(null);
    try {
      await terminarTransferencia(transfer.codigo);
      setTransfer({ ...transfer, estado: "terminado" });
      setMessage("Solicitud terminada. Ya se puede procesar.");
    } catch (reason) {
      setError(toApiError(reason));
    } finally {
      setPendingAction(null);
    }
  }

  async function processTransfer() {
    if (!transfer || !canProcess || busy) return;

    setPendingAction("process");
    setError(null);
    setMessage(null);
    try {
      await procesarTransferencia(transfer.codigo);
      setTransfer({ ...transfer, estado: "procesado" });
      setMessage("Transferencia procesada. El stock de la sala fue actualizado.");
    } catch (reason) {
      setError(toApiError(reason));
    } finally {
      setPendingAction(null);
    }
  }

  return (
    <div>
      <PageHeader
        title="Transferencias"
        subtitle="Creá una solicitud, agregá vinos y procesala para actualizar el stock de la sala."
      />

      {error ? (
        <div className="mb-5">
          <ErrorBanner
            error={error}
            title="No se pudo completar la operación"
          />
        </div>
      ) : null}

      {message ? (
        <div className="mb-5">
          <Notice>{message}</Notice>
        </div>
      ) : null}

      <section className={`${cardClass} p-5`}>
        <div className="grid gap-4 md:grid-cols-[1fr_auto] md:items-end">
          <FormField
            label="Sala destino"
            htmlFor="transferencia-sala"
          >
            <select
              id="transferencia-sala"
              value={selectedSalaId ?? ""}
              onChange={(event) => setSalaId(Number(event.target.value))}
              className={inputClass}
              disabled={!canCreate || activeSalas.length === 0}
            >
              {activeSalas.length === 0 ? (
                <option value="">Sin salas activas</option>
              ) : null}
              {activeSalas.map((sala) => (
                <option key={sala.id_sala} value={sala.id_sala}>
                  {salaLabel(sala)}
                </option>
              ))}
            </select>
          </FormField>
          <button
            type="button"
            onClick={createTransfer}
            disabled={!canCreate || !selectedSalaId || busy}
            className={primaryButtonClass}
          >
            <PlusIcon className="h-4 w-4" />
            {pendingAction === "create"
              ? "Creando..."
              : transfer
                ? "Nueva solicitud"
                : "Crear solicitud"}
          </button>
        </div>
        {!canCreate ? (
          <p className="mt-3 text-xs text-wine-900/45">
            Terminá y procesá la solicitud actual antes de crear otra.
          </p>
        ) : null}
      </section>

      {transfer ? (
        <>
          <section className={`${cardClass} mt-5 p-5`}>
            <div className="flex flex-wrap items-start justify-between gap-4">
              <div>
                <p className="text-xs font-bold uppercase tracking-wide text-wine-800/55">
                  Solicitud #{transfer.codigo}
                </p>
                <h2 className="mt-1 text-lg font-bold text-wine-900">
                  {currentSala ? salaLabel(currentSala) : `Sala #${transfer.id_sala}`}
                </h2>
                <p className="mt-1 text-sm text-wine-900/50">
                  Fecha de confección: {formatDate(transfer.fecha_confeccion)}
                </p>
              </div>
              <Badge className={estadoBadgeClass(transfer.estado)}>
                {estadoLabel(transfer.estado)}
              </Badge>
            </div>

            <div className="mt-5 flex flex-wrap gap-2 border-t border-[#E7DADD] pt-4">
              {canAdd ? (
                <button
                  type="button"
                  onClick={() => setPickerOpen(true)}
                  className={secondaryButtonClass}
                >
                  <PlusIcon className="h-4 w-4" />
                  Agregar renglón
                </button>
              ) : null}
              {canAdd ? (
                <button
                  type="button"
                  onClick={finishTransfer}
                  disabled={!canFinish || busy}
                  className={primaryButtonClass}
                >
                  {pendingAction === "finish"
                    ? "Terminando..."
                    : "Terminar solicitud"}
                </button>
              ) : null}
              {canProcess ? (
                <button
                  type="button"
                  onClick={processTransfer}
                  disabled={busy}
                  className={primaryButtonClass}
                >
                  {pendingAction === "process"
                    ? "Procesando..."
                    : "Procesar transferencia"}
                </button>
              ) : null}
              {transfer.estado === "procesado" ? (
                <p className="self-center text-sm font-semibold text-emerald-700">
                  Transferencia procesada. El stock de la sala fue actualizado.
                </p>
              ) : null}
            </div>
            {canAdd && !canFinish ? (
              <p className="mt-3 text-xs text-wine-900/45">
                Agregá al menos un renglón para poder terminar la solicitud.
              </p>
            ) : null}
          </section>

          <section className={`${cardClass} mt-5 overflow-hidden`}>
            <div className="border-b border-[#E7DADD] px-5 py-4">
              <h2 className="text-sm font-bold uppercase tracking-wide text-wine-800/60">
                Renglones cargados
              </h2>
              <p className="mt-1 text-sm text-wine-900/50">
                Productos incluidos en la solicitud.
              </p>
            </div>

            {lines.length === 0 ? (
              <div className="p-5">
                <EmptyState
                  title="La solicitud todavía no tiene renglones"
                  description="Agregá vinos mientras la solicitud está en confección."
                  action={
                    canAdd ? (
                      <button
                        type="button"
                        onClick={() => setPickerOpen(true)}
                        className={primaryButtonClass}
                      >
                        <PlusIcon className="h-4 w-4" />
                        Agregar renglón
                      </button>
                    ) : null
                  }
                />
              </div>
            ) : (
              <div className="overflow-x-auto">
                <table className="w-full min-w-[680px] text-left text-sm">
                  <thead className="bg-wine-50 text-xs uppercase tracking-wide text-wine-800/60">
                    <tr>
                      <th className="px-4 py-3 font-bold">Código</th>
                      <th className="px-4 py-3 font-bold">Vino</th>
                      <th className="px-4 py-3 font-bold">Bodega</th>
                      <th className="px-4 py-3 font-bold">Tipo</th>
                      <th className="px-4 py-3 text-right font-bold">
                        Cantidad
                      </th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-[#F1E7E9]">
                    {lines.map((line) => (
                      <tr key={line.vino.cod_vino}>
                        <td className="px-4 py-3 font-mono text-xs text-wine-900/60">
                          #{line.vino.cod_vino}
                        </td>
                        <td className="px-4 py-3 font-semibold text-wine-900">
                          {line.vino.nombre}
                        </td>
                        <td className="px-4 py-3 text-wine-900/65">
                          {line.vino.bodega}
                        </td>
                        <td className="px-4 py-3 text-wine-900/65">
                          {tipoLabel(line.vino.tipo)}
                        </td>
                        <td className="px-4 py-3 text-right font-semibold text-wine-900">
                          {line.cantidad}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </section>
        </>
      ) : (
        <div className="mt-5">
          <EmptyState
            title="Todavía no hay una solicitud"
            description="Elegí una sala y creá la solicitud para comenzar a cargar renglones."
          />
        </div>
      )}

      {pickerOpen && transfer && canAdd ? (
        <WinePickerDialog
          title="Agregar renglón a la transferencia"
          disabledCodes={disabledCodes}
          onClose={() => setPickerOpen(false)}
          onAdd={addLine}
        />
      ) : null}
    </div>
  );
}
