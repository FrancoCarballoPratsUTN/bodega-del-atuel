import type { Catalogos } from "../types";
import { tipoLabel } from "../display";
import { FormField, ghostButtonClass, inputClass } from "./ui";

export interface VinoFilterValues {
  tipo: string;
  cepa: string;
  bodega: string;
  aniada: string;
}

export const EMPTY_VINO_FILTERS: VinoFilterValues = {
  tipo: "",
  cepa: "",
  bodega: "",
  aniada: "",
};

export function parseAniadaFilter(value: string): number | undefined {
  if (!value) return undefined;
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed < 1900 || parsed > 2100) {
    return undefined;
  }
  return parsed;
}

interface VinoFiltersProps {
  value: VinoFilterValues;
  catalogos: Catalogos;
  idPrefix: string;
  onChange: (value: VinoFilterValues) => void;
}

export function VinoFilters({
  value,
  catalogos,
  idPrefix,
  onChange,
}: VinoFiltersProps) {
  const hasFilters = Object.values(value).some(Boolean);

  function update(field: keyof VinoFilterValues, nextValue: string) {
    onChange({ ...value, [field]: nextValue });
  }

  return (
    <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-5">
      <FormField label="Tipo" htmlFor={`${idPrefix}-tipo`}>
        <select
          id={`${idPrefix}-tipo`}
          value={value.tipo}
          onChange={(event) => update("tipo", event.target.value)}
          className={inputClass}
        >
          <option value="">Todos los tipos</option>
          {catalogos.tipos_vino.map((tipo) => (
            <option key={tipo} value={tipo}>
              {tipoLabel(tipo)}
            </option>
          ))}
        </select>
      </FormField>

      <FormField label="Cepa" htmlFor={`${idPrefix}-cepa`}>
        <select
          id={`${idPrefix}-cepa`}
          value={value.cepa}
          onChange={(event) => update("cepa", event.target.value)}
          className={inputClass}
        >
          <option value="">Todas las cepas</option>
          {catalogos.cepas.map((cepa) => (
            <option key={cepa.id_cepa} value={cepa.nombre}>
              {cepa.nombre}
            </option>
          ))}
        </select>
      </FormField>

      <FormField label="Bodega" htmlFor={`${idPrefix}-bodega`}>
        <select
          id={`${idPrefix}-bodega`}
          value={value.bodega}
          onChange={(event) => update("bodega", event.target.value)}
          className={inputClass}
        >
          <option value="">Todas las bodegas</option>
          {catalogos.bodegas
            .filter((bodega) => bodega.activo)
            .map((bodega) => (
              <option key={bodega.cuit_bodega} value={bodega.razon_social}>
                {bodega.razon_social}
              </option>
            ))}
        </select>
      </FormField>

      <FormField label="Añada" htmlFor={`${idPrefix}-aniada`}>
        <input
          id={`${idPrefix}-aniada`}
          type="number"
          inputMode="numeric"
          min={1900}
          max={2100}
          placeholder="Todas"
          value={value.aniada}
          onChange={(event) => update("aniada", event.target.value)}
          className={inputClass}
        />
      </FormField>

      <div className="flex items-end">
        <button
          type="button"
          onClick={() => onChange(EMPTY_VINO_FILTERS)}
          disabled={!hasFilters}
          className={`${ghostButtonClass} h-[42px] w-full border border-[#E2D4D7]`}
        >
          Limpiar filtros
        </button>
      </div>
    </div>
  );
}
