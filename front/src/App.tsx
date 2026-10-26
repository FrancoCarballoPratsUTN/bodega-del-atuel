import { useState, type ComponentType } from "react";

import { CatalogosProvider } from "./context/CatalogosContext";
import { CatalogoScreen } from "./screens/CatalogoScreen";
import { VinoFormScreen } from "./screens/VinoFormScreen";
import { VentaScreen } from "./screens/VentaScreen";
import { TransferenciasScreen } from "./screens/TransferenciasScreen";
import { TableroScreen } from "./screens/TableroScreen";
import type { Screen } from "./types";
import {
  CatalogIcon,
  DashboardIcon,
  PlusIcon,
  SaleIcon,
  TransferIcon,
  WineIcon,
} from "./components/Icons";

interface NavItem {
  id: Screen;
  label: string;
  icon: ComponentType<{ className?: string }>;
}

const NAV_ITEMS: NavItem[] = [
  { id: "catalogo", label: "Catálogo", icon: CatalogIcon },
  { id: "vino-form", label: "Alta / Edición", icon: PlusIcon },
  { id: "venta", label: "Nueva Venta", icon: SaleIcon },
  { id: "transferencias", label: "Transferencias", icon: TransferIcon },
  { id: "tablero", label: "Tablero", icon: DashboardIcon },
];

export default function App() {
  return (
    <CatalogosProvider>
      <AppContent />
    </CatalogosProvider>
  );
}

function AppContent() {
  const [screen, setScreen] = useState<Screen>("catalogo");
  const [editingCode, setEditingCode] = useState<number | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  function navigate(nextScreen: Screen) {
    setScreen(nextScreen);
    setNotice(null);
    if (nextScreen === "vino-form") setEditingCode(null);
  }

  function openNewWine() {
    setEditingCode(null);
    setNotice(null);
    setScreen("vino-form");
  }

  function openEditWine(codVino: number) {
    setEditingCode(codVino);
    setNotice(null);
    setScreen("vino-form");
  }

  function handleSaved() {
    setNotice("Vino guardado correctamente.");
    setEditingCode(null);
    setScreen("catalogo");
  }

  return (
    <div className="min-h-screen bg-[#F8F9FA] lg:flex">
      <a
        href="#main-content"
        className="sr-only rounded-md bg-wine-900 px-4 py-2 text-sm font-bold text-white focus:not-sr-only focus:absolute focus:left-3 focus:top-3 focus:z-[60]"
      >
        Saltar al contenido
      </a>

      <aside className="hidden w-64 shrink-0 flex-col bg-wine-900 text-white lg:flex">
        <div className="flex items-center gap-3 border-b border-white/10 px-5 py-6">
          <span className="flex h-11 w-11 items-center justify-center rounded-xl bg-gold-400 text-wine-900">
            <WineIcon className="h-6 w-6" />
          </span>
          <div>
            <p className="text-base font-bold leading-tight">Bodega del Atuel</p>
            <p className="mt-0.5 text-[11px] font-semibold uppercase tracking-[0.16em] text-gold-300">
              Gestión TPI
            </p>
          </div>
        </div>

        <nav className="flex-1 space-y-1 px-3 py-5" aria-label="Navegación principal">
          {NAV_ITEMS.map((item) => {
            const Icon = item.icon;
            const active = screen === item.id;
            return (
              <button
                key={item.id}
                type="button"
                onClick={() => navigate(item.id)}
                aria-current={active ? "page" : undefined}
                className={`flex w-full items-center gap-3 rounded-lg border-l-2 px-3 py-2.5 text-left text-sm font-semibold transition ${
                  active
                    ? "border-gold-400 bg-white/10 text-gold-300"
                    : "border-transparent text-white/70 hover:bg-white/5 hover:text-white"
                }`}
              >
                <Icon className="h-5 w-5 shrink-0" />
                {item.label}
              </button>
            );
          })}
        </nav>

        <div className="border-t border-white/10 px-5 py-4 text-[11px] leading-5 text-white/40">
          Los datos se consultan en línea a la API. Los importes, descuentos y
          stock los calcula PostgreSQL.
        </div>
      </aside>

      <div className="flex min-w-0 flex-1 flex-col">
        <header className="border-b border-[#E7DADD] bg-white lg:hidden">
          <div className="flex items-center gap-3 px-4 py-3">
            <span className="flex h-9 w-9 items-center justify-center rounded-lg bg-wine-700 text-gold-300">
              <WineIcon className="h-5 w-5" />
            </span>
            <div>
              <p className="text-sm font-bold text-wine-900">Bodega del Atuel</p>
              <p className="text-[10px] font-semibold uppercase tracking-[0.14em] text-wine-700/55">
                Gestión TPI
              </p>
            </div>
          </div>
          <nav
            className="flex gap-1 overflow-x-auto px-2 pb-2"
            aria-label="Navegación principal"
          >
            {NAV_ITEMS.map((item) => {
              const Icon = item.icon;
              const active = screen === item.id;
              return (
                <button
                  key={item.id}
                  type="button"
                  onClick={() => navigate(item.id)}
                  aria-current={active ? "page" : undefined}
                  className={`flex shrink-0 items-center gap-1.5 rounded-lg px-2.5 py-2 text-xs font-bold transition ${
                    active
                      ? "bg-wine-700 text-white"
                      : "text-wine-900/60 hover:bg-wine-50"
                  }`}
                >
                  <Icon className="h-4 w-4" />
                  {item.label}
                </button>
              );
            })}
          </nav>
        </header>

        <main
          id="main-content"
          className="flex-1 px-4 py-6 sm:px-6 lg:px-8 lg:py-8"
        >
          <div className="mx-auto w-full max-w-[1400px]">
            {screen === "catalogo" ? (
              <CatalogoScreen
                notice={notice}
                onNew={openNewWine}
                onEdit={openEditWine}
              />
            ) : null}

            {screen === "vino-form" ? (
              <VinoFormScreen
                key={editingCode ?? "new"}
                codVino={editingCode}
                onBack={() => navigate("catalogo")}
                onSaved={handleSaved}
              />
            ) : null}

            {screen === "venta" ? <VentaScreen /> : null}
            {screen === "transferencias" ? <TransferenciasScreen /> : null}
            {screen === "tablero" ? <TableroScreen /> : null}
          </div>
        </main>
      </div>
    </div>
  );
}
