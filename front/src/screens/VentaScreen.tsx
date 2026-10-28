import { useState } from "react";

import { createComprobante, toApiError, type ApiError } from "../api";
import { useCatalogos } from "../context/CatalogosContext";
import { ClientSearch } from "../components/ClientSearch";
import { WinePickerDialog } from "../components/WinePickerDialog";
import {
  formatDateTime,
  formatMoney,
  formatPercent,
  salaLabel,
  tipoLabel,
} from "../display";
import type { Cliente, Comprobante, VinoResumen } from "../types";
import {
  EmptyState,
  ErrorBanner,
  FormField,
  PageHeader,
  cardClass,
  dangerButtonClass,
  ghostButtonClass,
  inputClass,
  primaryButtonClass,
  secondaryButtonClass,
} from "../components/ui";
import { PlusIcon, TrashIcon } from "../components/Icons";

interface CartLine {
  vino: VinoResumen;
  cantidad: number;
}

export function VentaScreen() {
  const { data: catalogos } = useCatalogos();
  const [cliente, setCliente] = useState<Cliente | null>(null);
  const [salaId, setSalaId] = useState<number | null>(null);
  const [cart, setCart] = useState<CartLine[]>([]);
  const [pickerOpen, setPickerOpen] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<ApiError | null>(null);
  const [comprobante, setComprobante] = useState<Comprobante | null>(null);

  const activeSalas = catalogos.salas.filter((sala) => sala.activo);
  const selectedSalaId = salaId ?? activeSalas[0]?.id_sala ?? null;
  const selectedSala =
    catalogos.salas.find((sala) => sala.id_sala === selectedSalaId) ?? null;
  const disabledCodes = new Set(cart.map((line) => line.vino.cod_vino));

  function clearOutcome() {
    setComprobante(null);
    setError(null);
  }

  function selectCliente(next: Cliente | null) {
    setCliente(next);
    clearOutcome();
  }

  function selectSala(value: string) {
    setSalaId(Number(value));
    clearOutcome();
  }

  function addWine(vino: VinoResumen, cantidad: number) {
    if (cart.some((line) => line.vino.cod_vino === vino.cod_vino)) return;
    setCart((current) => [...current, { vino, cantidad }]);
    clearOutcome();
  }

  function updateCantidad(codVino: number, value: string) {
    const parsed = Number(value);
    const cantidad =
      Number.isFinite(parsed) && parsed >= 1 ? Math.trunc(parsed) : 1;
    setCart((current) =>
      current.map((line) =>
        line.vino.cod_vino === codVino ? { ...line, cantidad } : line,
      ),
    );
    clearOutcome();
  }

  function removeLine(codVino: number) {
    setCart((current) =>
      current.filter((line) => line.vino.cod_vino !== codVino),
    );
    clearOutcome();
  }

  async function generateComprobante() {
    if (!cliente || !selectedSalaId || cart.length === 0 || submitting) return;

    setSubmitting(true);
    setError(null);
    try {
      const result = await createComprobante({
        id_cliente: cliente.id_cliente,
        id_sala: selectedSalaId,
        renglones: cart.map((line) => ({
          cod_vino: line.vino.cod_vino,
          cantidad: line.cantidad,
        })),
      });
      setComprobante(result);
    } catch (reason) {
      setError(toApiError(reason));
    } finally {
      setSubmitting(false);
    }
  }

  function startNewSale() {
    setCliente(null);
    setCart([]);
    setComprobante(null);
    setError(null);
  }

  function wineName(codVino: number): string {
    return (
      cart.find((line) => line.vino.cod_vino === codVino)?.vino.nombre ??
      `Vino #${codVino}`
    );
  }

  return (
    <div>
      <PageHeader
        title="Nueva venta"
        subtitle="Elegí el cliente y la sala, agregá vinos y confirmá la venta."
      />

      {error ? (
        <div className="mb-5">
          <ErrorBanner
            error={error}
            title="No se pudo registrar la venta"
          />
        </div>
      ) : null}

      <div className="grid gap-5 xl:grid-cols-[1.35fr_0.9fr]">
        <div className="space-y-5">
          <section className={`${cardClass} p-5`}>
            <ClientSearch selected={cliente} onSelect={selectCliente} />
          </section>

          <section className={`${cardClass} p-5`}>
            <FormField
              label="Sala de venta"
              htmlFor="venta-sala"
            >
              <select
                id="venta-sala"
                value={selectedSalaId ?? ""}
                onChange={(event) => selectSala(event.target.value)}
                className={inputClass}
                disabled={activeSalas.length === 0}
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
            {selectedSala ? (
              <p className="mt-2 text-xs text-wine-900/45">
                Cierre semanal: {selectedSala.dia_cierre}
              </p>
            ) : null}
          </section>

          <section className={`${cardClass} overflow-hidden`}>
            <div className="flex flex-wrap items-center justify-between gap-3 border-b border-[#E7DADD] px-5 py-4">
              <div>
                <h2 className="text-sm font-bold uppercase tracking-wide text-wine-800/60">
                  Vinos de la venta
                </h2>
              </div>
              <button
                type="button"
                onClick={() => setPickerOpen(true)}
                className={secondaryButtonClass}
              >
                <PlusIcon className="h-4 w-4" />
                Agregar vino
              </button>
            </div>

            {cart.length === 0 ? (
              <div className="p-5">
                <EmptyState
                  title="La venta todavía no tiene vinos"
                  description="Agregá uno o más vinos. El comprobante se genera recién cuando lo confirmes."
                  action={
                    <button
                      type="button"
                      onClick={() => setPickerOpen(true)}
                      className={primaryButtonClass}
                    >
                      <PlusIcon className="h-4 w-4" />
                      Agregar vino
                    </button>
                  }
                />
              </div>
            ) : (
              <div className="overflow-x-auto">
                <table className="w-full min-w-[720px] text-left text-sm">
                  <thead className="bg-wine-50 text-xs uppercase tracking-wide text-wine-800/60">
                    <tr>
                      <th className="px-4 py-3 font-bold">Vino</th>
                      <th className="px-4 py-3 font-bold">Tipo</th>
                      <th className="px-4 py-3 font-bold">Cantidad</th>
                      <th className="px-4 py-3 text-right font-bold">
                        Precio unitario
                      </th>
                      <th className="px-4 py-3 text-right font-bold">
                        Quitar
                      </th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-[#F1E7E9]">
                    {cart.map((line) => (
                      <tr key={line.vino.cod_vino}>
                        <td className="px-4 py-3">
                          <p className="font-semibold text-wine-900">
                            {line.vino.nombre}
                          </p>
                          <p className="mt-0.5 text-xs text-wine-900/50">
                            {line.vino.bodega} · #{line.vino.cod_vino}
                          </p>
                        </td>
                        <td className="px-4 py-3 text-wine-900/65">
                          {tipoLabel(line.vino.tipo)}
                        </td>
                        <td className="px-4 py-3">
                          <input
                            type="number"
                            min={1}
                            step={1}
                            value={line.cantidad}
                            onChange={(event) =>
                              updateCantidad(
                                line.vino.cod_vino,
                                event.target.value,
                              )
                            }
                            aria-label={`Cantidad de ${line.vino.nombre}`}
                            className={`${inputClass} w-24`}
                          />
                        </td>
                        <td className="px-4 py-3 text-right font-semibold text-wine-900">
                          {formatMoney(line.vino.precio)}
                        </td>
                        <td className="px-4 py-3 text-right">
                          <button
                            type="button"
                            onClick={() => removeLine(line.vino.cod_vino)}
                            className={dangerButtonClass}
                            title="Quitar vino de la venta"
                          >
                            <TrashIcon className="h-4 w-4" />
                          </button>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}

            <div className="flex flex-wrap items-center justify-between gap-3 border-t border-[#E7DADD] px-5 py-4">
              <p className="text-xs text-wine-900/45">
                El total se muestra al generar el comprobante.
              </p>
              <button
                type="button"
                onClick={generateComprobante}
                disabled={
                  !cliente ||
                  !selectedSalaId ||
                  cart.length === 0 ||
                  submitting ||
                  Boolean(comprobante)
                }
                className={primaryButtonClass}
              >
                {comprobante
                  ? "Comprobante generado"
                  : submitting
                    ? "Generando..."
                    : "Generar comprobante"}
              </button>
            </div>
          </section>
        </div>

        <aside className="xl:sticky xl:top-6 xl:self-start">
          <section className={`${cardClass} p-5`} aria-live="polite">
            <div className="flex items-start justify-between gap-3">
              <div>
                <h2 className="text-sm font-bold uppercase tracking-wide text-wine-800/60">
                  Comprobante
                </h2>
                <p className="mt-1 text-sm text-wine-900/50">
                  El total aparecerá al generar el comprobante.
                </p>
              </div>
              {comprobante ? (
                <button
                  type="button"
                  onClick={startNewSale}
                  className={ghostButtonClass}
                >
                  Nueva venta
                </button>
              ) : null}
            </div>

            {!comprobante ? (
              <div className="mt-5 rounded-xl border border-dashed border-[#E2D4D7] bg-wine-50/40 p-5">
                <p className="text-sm font-semibold text-wine-900">
                  Todavía no se generó el comprobante.
                </p>
                <p className="mt-1 text-sm leading-6 text-wine-900/55">
                  Al confirmar la venta, vas a ver el subtotal, el descuento y
                  el total del comprobante.
                </p>
                {cliente ? (
                  <p className="mt-3 text-xs text-wine-900/45">
                    Cliente: {cliente.nombre_razon_social} · Descuento
                    registrado: {formatPercent(cliente.descuento)}
                  </p>
                ) : null}
              </div>
            ) : (
              <div className="mt-5 space-y-4">
                <div className="rounded-xl bg-wine-800 p-4 text-white">
                  <p className="text-xs font-bold uppercase tracking-wide text-gold-300">
                    Total
                  </p>
                  <p className="mt-1 text-3xl font-bold tracking-tight">
                    {formatMoney(comprobante.total)}
                  </p>
                  <p className="mt-2 text-xs text-white/65">
                    Comprobante #{comprobante.nro_comprobante} ·{" "}
                    {formatDateTime(comprobante.fecha)}
                  </p>
                </div>

                <dl className="space-y-2 text-sm">
                  <div className="flex justify-between gap-3">
                    <dt className="text-wine-900/55">Cliente</dt>
                    <dd className="text-right font-semibold text-wine-900">
                      {cliente?.nombre_razon_social ??
                        `Cliente #${comprobante.id_cliente}`}
                    </dd>
                  </div>
                  <div className="flex justify-between gap-3">
                    <dt className="text-wine-900/55">Sala</dt>
                    <dd className="text-right font-semibold text-wine-900">
                      {catalogos.salas.find(
                        (sala) => sala.id_sala === comprobante.id_sala,
                      )?.calle ?? "—"}{" "}
                      #{comprobante.id_sala}
                    </dd>
                  </div>
                  <div className="flex justify-between gap-3">
                    <dt className="text-wine-900/55">Subtotal</dt>
                    <dd className="font-semibold text-wine-900">
                      {formatMoney(comprobante.subtotal)}
                    </dd>
                  </div>
                  <div className="flex justify-between gap-3">
                    <dt className="text-wine-900/55">Descuento</dt>
                    <dd className="font-semibold text-wine-900">
                      {formatMoney(comprobante.descuento)}
                    </dd>
                  </div>
                </dl>

                <div className="border-t border-[#E7DADD] pt-3">
                  <h3 className="text-xs font-bold uppercase tracking-wide text-wine-800/60">
                    Renglones
                  </h3>
                  <ul className="mt-2 divide-y divide-[#F1E7E9]">
                    {comprobante.renglones.map((renglon) => (
                      <li
                        key={renglon.cod_vino}
                        className="py-2.5 text-sm"
                      >
                        <p className="font-semibold text-wine-900">
                          {wineName(renglon.cod_vino)}
                        </p>
                        <div className="mt-1 flex flex-wrap justify-between gap-2 text-xs text-wine-900/55">
                          <span>
                            {renglon.cantidad} ×{" "}
                            {formatMoney(renglon.precio_unitario)}
                          </span>
                          <span>
                            Desc. {formatMoney(renglon.descuento)} · Subtotal{" "}
                            {formatMoney(renglon.subtotal)}
                          </span>
                        </div>
                      </li>
                    ))}
                  </ul>
                </div>
              </div>
            )}
          </section>
        </aside>
      </div>

      {pickerOpen ? (
        <WinePickerDialog
          disabledCodes={disabledCodes}
          onClose={() => setPickerOpen(false)}
          onAdd={addWine}
        />
      ) : null}
    </div>
  );
}
