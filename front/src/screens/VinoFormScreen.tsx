import { useEffect, useState, type FormEvent } from "react";

import {
  createVino,
  getVino,
  toApiError,
  updateVino,
  type ApiError,
} from "../api";
import { useCatalogos } from "../context/CatalogosContext";
import { useApiResource } from "../hooks/useApiResource";
import type { VinoPayload } from "../types";
import { TIPOS_VINO } from "../types";
import {
  ErrorBanner,
  FormField,
  LoadingBlock,
  PageHeader,
  cardClass,
  dangerButtonClass,
  inputClass,
  primaryButtonClass,
  secondaryButtonClass,
} from "../components/ui";
import { CheckIcon, PlusIcon, TrashIcon } from "../components/Icons";

interface VinoFormValues {
  cuit_bodega: string;
  nombre: string;
  tipo: string;
  aniada: string;
  volumen: string;
  graduacion: string;
  precio: string;
}

interface CepaRow {
  id_cepa: string;
  porcentaje: string;
}

const EMPTY_FORM: VinoFormValues = {
  cuit_bodega: "",
  nombre: "",
  tipo: "",
  aniada: "",
  volumen: "",
  graduacion: "",
  precio: "",
};

const EMPTY_CEPA_ROW: CepaRow = { id_cepa: "", porcentaje: "" };

interface VinoFormScreenProps {
  codVino: number | null;
  onBack: () => void;
  onSaved: () => void;
}

export function VinoFormScreen({
  codVino,
  onBack,
  onSaved,
}: VinoFormScreenProps) {
  const { data: catalogos } = useCatalogos();
  const editing = codVino !== null;
  const [form, setForm] = useState<VinoFormValues>(EMPTY_FORM);
  const [cepas, setCepas] = useState<CepaRow[]>([{ ...EMPTY_CEPA_ROW }]);
  const [hydrated, setHydrated] = useState(!editing);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<ApiError | null>(null);

  const resource = useApiResource(
    (signal) =>
      codVino === null ? Promise.resolve(null) : getVino(codVino, signal),
    [codVino],
  );

  useEffect(() => {
    if (!resource.data) return;
    setForm({
      cuit_bodega: resource.data.cuit_bodega,
      nombre: resource.data.nombre,
      tipo: resource.data.tipo,
      aniada: String(resource.data.aniada),
      volumen: String(resource.data.volumen),
      graduacion: String(resource.data.graduacion),
      precio: String(resource.data.precio),
    });
    setCepas(
      resource.data.cepas.length > 0
        ? resource.data.cepas.map((cepa) => ({
            id_cepa: String(cepa.id_cepa),
            porcentaje: String(cepa.porcentaje),
          }))
        : [{ ...EMPTY_CEPA_ROW }],
    );
    setHydrated(true);
  }, [resource.data]);

  function updateField(field: keyof VinoFormValues, value: string) {
    setForm((current) => ({ ...current, [field]: value }));
  }

  function updateCepa(index: number, field: keyof CepaRow, value: string) {
    setCepas((current) =>
      current.map((row, rowIndex) =>
        rowIndex === index ? { ...row, [field]: value } : row,
      ),
    );
  }

  function addCepaRow() {
    setCepas((current) => [...current, { ...EMPTY_CEPA_ROW }]);
  }

  function removeCepaRow(index: number) {
    setCepas((current) => current.filter((_, rowIndex) => rowIndex !== index));
  }

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (submitting) return;

    const payload: VinoPayload = {
      cuit_bodega: form.cuit_bodega,
      nombre: form.nombre.trim(),
      tipo: form.tipo,
      aniada: Number(form.aniada),
      volumen: Number(form.volumen),
      graduacion: Number(form.graduacion),
      precio: Number(form.precio),
      cepas: cepas.map((cepa) => ({
        id_cepa: Number(cepa.id_cepa),
        porcentaje: Number(cepa.porcentaje),
      })),
    };

    setSubmitting(true);
    setError(null);
    try {
      if (codVino === null) {
        await createVino({ ...payload, maridajes: [] });
      } else {
        await updateVino(codVino, payload);
      }
      onSaved();
    } catch (reason) {
      setError(toApiError(reason));
    } finally {
      setSubmitting(false);
    }
  }

  const waitingForDetail =
    editing && !hydrated && !resource.error && resource.loading;

  return (
    <div>
      <PageHeader
        title={editing ? `Editar vino #${codVino}` : "Alta de vino"}
        subtitle="Los datos se guardan directamente en la base. La API valida la composición y las reglas de negocio."
        actions={
          <button type="button" onClick={onBack} className={secondaryButtonClass}>
            Volver al catálogo
          </button>
        }
      />

      {resource.error ? (
        <ErrorBanner
          error={resource.error}
          title="No se pudo cargar el vino"
          onRetry={resource.reload}
        />
      ) : waitingForDetail ? (
        <LoadingBlock label="Cargando vino..." />
      ) : (
        <form onSubmit={handleSubmit} className="space-y-5">
          {error ? (
            <ErrorBanner
              error={error}
              title="No se pudo guardar el vino"
            />
          ) : null}

          <section className={`${cardClass} p-5`}>
            <h2 className="text-sm font-bold uppercase tracking-wide text-wine-800/60">
              Datos generales
            </h2>
            <div className="mt-4 grid gap-4 md:grid-cols-2 xl:grid-cols-3">
              <FormField
                label="Bodega"
                htmlFor="vino-bodega"
                className="md:col-span-2 xl:col-span-1"
              >
                <select
                  id="vino-bodega"
                  required
                  value={form.cuit_bodega}
                  onChange={(event) =>
                    updateField("cuit_bodega", event.target.value)
                  }
                  className={inputClass}
                >
                  <option value="">Seleccionar bodega</option>
                  {catalogos.bodegas.map((bodega) => (
                    <option
                      key={bodega.cuit_bodega}
                      value={bodega.cuit_bodega}
                    >
                      {bodega.razon_social}
                      {bodega.activo ? "" : " (inactiva)"}
                    </option>
                  ))}
                </select>
              </FormField>

              <FormField
                label="Nombre"
                htmlFor="vino-nombre"
                className="xl:col-span-2"
              >
                <input
                  id="vino-nombre"
                  required
                  maxLength={150}
                  value={form.nombre}
                  onChange={(event) => updateField("nombre", event.target.value)}
                  className={inputClass}
                  placeholder="Nombre del vino"
                />
              </FormField>

              <FormField label="Tipo" htmlFor="vino-tipo">
                <select
                  id="vino-tipo"
                  required
                  value={form.tipo}
                  onChange={(event) => updateField("tipo", event.target.value)}
                  className={inputClass}
                >
                  <option value="">Seleccionar tipo</option>
                  {TIPOS_VINO.map((tipo) => (
                    <option key={tipo.value} value={tipo.value}>
                      {tipo.label}
                    </option>
                  ))}
                </select>
              </FormField>

              <FormField label="Añada" htmlFor="vino-aniada">
                <input
                  id="vino-aniada"
                  type="number"
                  required
                  min={1900}
                  max={2100}
                  value={form.aniada}
                  onChange={(event) => updateField("aniada", event.target.value)}
                  className={inputClass}
                  placeholder="2024"
                />
              </FormField>

              <FormField label="Volumen (ml)" htmlFor="vino-volumen">
                <input
                  id="vino-volumen"
                  type="number"
                  required
                  min={0.01}
                  step="0.01"
                  value={form.volumen}
                  onChange={(event) => updateField("volumen", event.target.value)}
                  className={inputClass}
                  placeholder="750"
                />
              </FormField>

              <FormField label="Graduación (%)" htmlFor="vino-graduacion">
                <input
                  id="vino-graduacion"
                  type="number"
                  required
                  min={0}
                  max={100}
                  step="0.01"
                  value={form.graduacion}
                  onChange={(event) =>
                    updateField("graduacion", event.target.value)
                  }
                  className={inputClass}
                  placeholder="13.5"
                />
              </FormField>

              <FormField label="Precio unitario" htmlFor="vino-precio">
                <input
                  id="vino-precio"
                  type="number"
                  required
                  min={0.01}
                  step="0.01"
                  value={form.precio}
                  onChange={(event) => updateField("precio", event.target.value)}
                  className={inputClass}
                  placeholder="4200"
                />
              </FormField>
            </div>
          </section>

          <section className={`${cardClass} p-5`}>
            <div className="flex flex-wrap items-start justify-between gap-3">
              <div>
                <h2 className="text-sm font-bold uppercase tracking-wide text-wine-800/60">
                  Composición de cepas
                </h2>
                <p className="mt-1 text-sm text-wine-900/55">
                  La API envía los porcentajes a PostgreSQL, que valida que la
                  composición sume exactamente 100%.
                </p>
              </div>
              <button
                type="button"
                onClick={addCepaRow}
                className={secondaryButtonClass}
              >
                <PlusIcon className="h-4 w-4" />
                Agregar cepa
              </button>
            </div>

            <div className="mt-4 space-y-3">
              {cepas.map((cepa, index) => (
                <div
                  key={index}
                  className="grid gap-3 rounded-xl border border-[#E7DADD] bg-wine-50/30 p-3 sm:grid-cols-[1fr_180px_auto]"
                >
                  <FormField
                    label="Cepa"
                    htmlFor={`vino-cepa-${index}`}
                  >
                    <select
                      id={`vino-cepa-${index}`}
                      required
                      value={cepa.id_cepa}
                      onChange={(event) =>
                        updateCepa(index, "id_cepa", event.target.value)
                      }
                      className={inputClass}
                    >
                      <option value="">Seleccionar cepa</option>
                      {catalogos.cepas.map((item) => (
                        <option key={item.id_cepa} value={item.id_cepa}>
                          {item.nombre} ({item.tipo})
                        </option>
                      ))}
                    </select>
                  </FormField>

                  <FormField
                    label="Porcentaje"
                    htmlFor={`vino-porcentaje-${index}`}
                  >
                    <input
                      id={`vino-porcentaje-${index}`}
                      type="number"
                      required
                      min={0.01}
                      max={100}
                      step="0.01"
                      value={cepa.porcentaje}
                      onChange={(event) =>
                        updateCepa(index, "porcentaje", event.target.value)
                      }
                      className={inputClass}
                      placeholder="100"
                    />
                  </FormField>

                  <div className="flex items-end">
                    <button
                      type="button"
                      onClick={() => removeCepaRow(index)}
                      disabled={cepas.length === 1}
                      className={`${dangerButtonClass} h-[42px]`}
                      title="Quitar cepa"
                    >
                      <TrashIcon className="h-4 w-4" />
                      Quitar
                    </button>
                  </div>
                </div>
              ))}
            </div>
          </section>

          <div className="flex flex-wrap justify-end gap-2">
            <button
              type="button"
              onClick={onBack}
              className={secondaryButtonClass}
              disabled={submitting}
            >
              Cancelar
            </button>
            <button
              type="submit"
              className={primaryButtonClass}
              disabled={submitting}
            >
              <CheckIcon className="h-4 w-4" />
              {submitting ? "Guardando..." : "Guardar vino"}
            </button>
          </div>
        </form>
      )}
    </div>
  );
}
