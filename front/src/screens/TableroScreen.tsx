import { useState } from "react";
import {
  Bar,
  BarChart,
  CartesianGrid,
  Cell,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";

import { getTopVinos, getVentasPorSala, getVinosSinStock } from "../api";
import { useCatalogos } from "../context/CatalogosContext";
import { useApiResource } from "../hooks/useApiResource";
import {
  formatMoney,
  formatNumber,
  salaLabel,
} from "../lib/display";
import type { Sala, VentaSala } from "../types";
import {
  EmptyState,
  ErrorBanner,
  FormField,
  LoadingBlock,
  PageHeader,
  cardClass,
  inputClass,
} from "../components/ui";

const CHART_COLORS = [
  "#7A1C30",
  "#9B2D45",
  "#BC4060",
  "#D4687E",
  "#C4973A",
  "#A07828",
  "#581825",
];

export function TableroScreen() {
  const { data: catalogos } = useCatalogos();
  const [salaId, setSalaId] = useState<number | null>(null);

  const activeSalas = catalogos.salas.filter((sala) => sala.activo);
  const selectedSalaId = salaId ?? activeSalas[0]?.id_sala ?? null;

  const topVinos = useApiResource(
    (signal) => getTopVinos(signal),
    [],
  );
  const ventas = useApiResource(
    (signal) => getVentasPorSala(signal),
    [],
  );
  const sinStock = useApiResource(
    (signal) =>
      selectedSalaId
        ? getVinosSinStock(selectedSalaId, signal)
        : Promise.resolve([]),
    [selectedSalaId],
  );

  return (
    <div>
      <PageHeader
        title="Tablero"
        subtitle="Ranking de vinos vendidos, ventas por sala del último trimestre y vinos sin stock. Todos los valores provienen de los reportes de la API."
      />

      <section className={`${cardClass} overflow-hidden`}>
        <div className="border-b border-[#E7DADD] px-5 py-4">
          <h2 className="text-sm font-bold uppercase tracking-wide text-wine-800/60">
            Top 10 de vinos
          </h2>
          <p className="mt-1 text-sm text-wine-900/50">
            Orden y cantidades calculados por la base de datos.
          </p>
        </div>
        {topVinos.error ? (
          <div className="p-4">
            <ErrorBanner
              error={topVinos.error}
              title="No se pudo cargar el ranking"
              onRetry={topVinos.reload}
            />
          </div>
        ) : !topVinos.data ? (
          <div className="p-4">
            <LoadingBlock label="Cargando ranking..." />
          </div>
        ) : topVinos.data.length === 0 ? (
          <div className="p-4">
            <EmptyState title="Todavía no hay vinos vendidos" />
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full min-w-[520px] text-left text-sm">
              <thead className="bg-wine-50 text-xs uppercase tracking-wide text-wine-800/60">
                <tr>
                  <th className="px-4 py-3 font-bold">Puesto</th>
                  <th className="px-4 py-3 font-bold">Vino</th>
                  <th className="px-4 py-3 text-right font-bold">
                    Botellas vendidas
                  </th>
                </tr>
              </thead>
              <tbody className="divide-y divide-[#F1E7E9]">
                {topVinos.data.map((vino, index) => (
                  <tr key={vino.cod_vino} className="hover:bg-wine-50/40">
                    <td className="px-4 py-3">
                      <span className="inline-flex h-7 w-7 items-center justify-center rounded-full bg-wine-100 text-xs font-bold text-wine-700">
                        {index + 1}
                      </span>
                    </td>
                    <td className="px-4 py-3 font-semibold text-wine-900">
                      {vino.nombre}
                    </td>
                    <td className="px-4 py-3 text-right font-semibold text-wine-900">
                      {formatNumber(vino.botellas_vendidas)}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      <section className={`${cardClass} mt-5 p-5`}>
        <div>
          <h2 className="text-sm font-bold uppercase tracking-wide text-wine-800/60">
            Ventas por sala
          </h2>
          <p className="mt-1 text-sm text-wine-900/50">
            Importes del último trimestre, sin filtros ni cálculos en el front.
          </p>
        </div>
        <div className="mt-5">
          {ventas.error ? (
            <ErrorBanner
              error={ventas.error}
              title="No se pudo cargar el gráfico de ventas"
              onRetry={ventas.reload}
            />
          ) : !ventas.data ? (
            <LoadingBlock label="Cargando ventas por sala..." />
          ) : ventas.data.length === 0 ? (
            <EmptyState title="Todavía no hay ventas en el último trimestre" />
          ) : (
            <SalesChart rows={ventas.data} salas={catalogos.salas} />
          )}
        </div>
      </section>

      <section className={`${cardClass} mt-5 p-5`}>
        <div className="flex flex-wrap items-end justify-between gap-4">
          <div>
            <h2 className="text-sm font-bold uppercase tracking-wide text-wine-800/60">
              Vinos sin stock en la sala
            </h2>
            <p className="mt-1 text-sm text-wine-900/50">
              Lista informada por la API para la sala seleccionada.
            </p>
          </div>
          <FormField
            label="Sala"
            htmlFor="tablero-sala"
            className="w-full sm:w-80"
          >
            <select
              id="tablero-sala"
              value={selectedSalaId ?? ""}
              onChange={(event) => setSalaId(Number(event.target.value))}
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
        </div>

        <div className="mt-4">
          {sinStock.error ? (
            <ErrorBanner
              error={sinStock.error}
              title="No se pudo cargar el reporte de stock"
              onRetry={sinStock.reload}
            />
          ) : !sinStock.data ? (
            <LoadingBlock label="Cargando vinos sin stock..." />
          ) : sinStock.data.length === 0 ? (
            <EmptyState
              title="No hay vinos sin stock en esta sala"
              description="El reporte no devolvió filas para la sala seleccionada."
            />
          ) : (
            <div className="overflow-hidden rounded-xl border border-[#E7DADD]">
              <div className="overflow-x-auto">
                <table className="w-full min-w-[580px] text-left text-sm">
                  <thead className="bg-wine-50 text-xs uppercase tracking-wide text-wine-800/60">
                    <tr>
                      <th className="px-4 py-3 font-bold">Código</th>
                      <th className="px-4 py-3 font-bold">Vino</th>
                      <th className="px-4 py-3 text-right font-bold">
                        Stock en sala
                      </th>
                      <th className="px-4 py-3 text-right font-bold">
                        Stock en depósito
                      </th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-[#F1E7E9]">
                    {sinStock.data.map((vino) => (
                      <tr key={vino.cod_vino}>
                        <td className="px-4 py-3 font-mono text-xs text-wine-900/60">
                          #{vino.cod_vino}
                        </td>
                        <td className="px-4 py-3 font-semibold text-wine-900">
                          {vino.nombre}
                        </td>
                        <td className="px-4 py-3 text-right text-wine-900/65">
                          {formatNumber(vino.stock_sala)}
                        </td>
                        <td className="px-4 py-3 text-right text-wine-900/65">
                          {formatNumber(vino.stock_deposito)}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </div>
          )}
        </div>
      </section>
    </div>
  );
}

interface SalesChartProps {
  rows: VentaSala[];
  salas: Sala[];
}

function SalesChart({ rows, salas }: SalesChartProps) {
  const data = rows.map((row) => {
    const sala = salas.find((item) => item.id_sala === row.id_sala);
    return {
      sala: sala ? `${sala.localidad} · Sala ${sala.id_sala}` : `Sala ${row.id_sala}`,
      total: Number(row.monto_total_ventas),
    };
  });

  return (
    <div className="h-[360px] w-full">
      <ResponsiveContainer width="100%" height="100%">
        <BarChart
          data={data}
          layout="vertical"
          margin={{ top: 4, right: 24, bottom: 4, left: 8 }}
        >
          <CartesianGrid strokeDasharray="3 3" horizontal={false} />
          <XAxis
            type="number"
            tickFormatter={(value) => formatMoney(value as number)}
            tick={{ fontSize: 11, fill: "#7A1C30" }}
          />
          <YAxis
            type="category"
            dataKey="sala"
            width={180}
            tick={{ fontSize: 11, fill: "#3D0F18" }}
          />
          <Tooltip
            formatter={(value) => formatMoney(value as number)}
            labelFormatter={(label) => `Sala: ${label}`}
            contentStyle={{
              borderRadius: 10,
              borderColor: "#E2D4D7",
              fontSize: 12,
            }}
          />
          <Bar dataKey="total" name="Ventas" radius={[0, 5, 5, 0]}>
            {data.map((entry, index) => (
              <Cell
                key={`${entry.sala}-${index}`}
                fill={CHART_COLORS[index % CHART_COLORS.length]}
              />
            ))}
          </Bar>
        </BarChart>
      </ResponsiveContainer>
    </div>
  );
}
