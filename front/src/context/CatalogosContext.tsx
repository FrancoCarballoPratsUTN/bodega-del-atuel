import {
  createContext,
  useContext,
  type ReactNode,
} from "react";

import { getCatalogos } from "../api";
import type { Catalogos } from "../types";
import { useApiResource } from "../hooks/useApiResource";
import { ErrorBanner } from "../components/ui";
import { WineIcon } from "../components/Icons";

interface CatalogosContextValue {
  data: Catalogos;
  reload: () => void;
}

const CatalogosContext = createContext<CatalogosContextValue | null>(null);

export function CatalogosProvider({ children }: { children: ReactNode }) {
  const resource = useApiResource(getCatalogos, []);

  if (!resource.data) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-wine-50 px-4">
        <div className="w-full max-w-lg">
          <div className="mb-5 flex items-center gap-3">
            <span className="flex h-11 w-11 items-center justify-center rounded-xl bg-wine-700 text-gold-300">
              <WineIcon className="h-6 w-6" />
            </span>
            <div>
              <p className="text-lg font-bold text-wine-900">Bodega del Atuel</p>
              <p className="text-xs font-semibold text-wine-900/50">
                Cargando catálogos...
              </p>
            </div>
          </div>
          {resource.error ? (
            <ErrorBanner
              error={resource.error}
              title="No se pudieron cargar los catálogos"
              onRetry={resource.reload}
            />
          ) : (
            <div className="h-2 overflow-hidden rounded-full bg-wine-100">
              <div className="h-full w-1/2 animate-pulse rounded-full bg-wine-500" />
            </div>
          )}
        </div>
      </div>
    );
  }

  return (
    <CatalogosContext.Provider
      value={{ data: resource.data, reload: resource.reload }}
    >
      {children}
    </CatalogosContext.Provider>
  );
}

export function useCatalogos(): CatalogosContextValue {
  const context = useContext(CatalogosContext);
  if (!context) {
    throw new Error("useCatalogos debe usarse dentro de CatalogosProvider.");
  }
  return context;
}
