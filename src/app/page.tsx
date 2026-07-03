"use client";

import { useState } from "react";
import { useLabStore } from "@/lib/store";
import type { TabKey, Chemical, Apparatus } from "@/lib/types";
import { AuthScreen } from "@/components/screens/auth-screen";
import { DashboardScreen } from "@/components/screens/dashboard-screen";
import { ChemicalsScreen } from "@/components/screens/chemicals-screen";
import { ApparatusScreen } from "@/components/screens/apparatus-screen";
import { ScannerScreen } from "@/components/screens/scanner-screen";
import { ReportsScreen } from "@/components/screens/reports-screen";
import { SettingsScreen } from "@/components/screens/settings-screen";
import { BottomNav } from "@/components/bottom-nav";
import {
  AddChemicalModal,
  ChemicalDetailModal,
  ChemicalLogModal,
  EditChemicalModal,
  ChemicalQRModal,
} from "@/components/modals/chemical-modals";
import {
  AddApparatusModal,
  ApparatusDetailModal,
  ApparatusLogModal,
  EditApparatusModal,
} from "@/components/modals/apparatus-modals";

export default function Page() {
  const user = useLabStore((s) => s.user);

  const [tab, setTab] = useState<TabKey>("home");
  const [search, setSearch] = useState("");

  // Chemical modal state
  const [addChemOpen, setAddChemOpen] = useState(false);
  const [detailChem, setDetailChem] = useState<Chemical | null>(null);
  const [detailChemOpen, setDetailChemOpen] = useState(false);
  const [logChem, setLogChem] = useState<Chemical | null>(null);
  const [logChemAction, setLogChemAction] = useState<"consume" | "restock">("consume");
  const [logChemOpen, setLogChemOpen] = useState(false);
  const [editChem, setEditChem] = useState<Chemical | null>(null);
  const [editChemOpen, setEditChemOpen] = useState(false);
  const [qrChem, setQrChem] = useState<Chemical | null>(null);
  const [qrChemOpen, setQrChemOpen] = useState(false);

  // Apparatus modal state
  const [addAppOpen, setAddAppOpen] = useState(false);
  const [detailApp, setDetailApp] = useState<Apparatus | null>(null);
  const [detailAppOpen, setDetailAppOpen] = useState(false);
  const [logApp, setLogApp] = useState<Apparatus | null>(null);
  const [logAppAction, setLogAppAction] = useState<"restock" | "breakage">("breakage");
  const [logAppOpen, setLogAppOpen] = useState(false);
  const [editApp, setEditApp] = useState<Apparatus | null>(null);
  const [editAppOpen, setEditAppOpen] = useState(false);

  const [settingsOpen, setSettingsOpen] = useState(false);

  if (!user) {
    return <AuthScreen />;
  }

  const openChemDetail = (c: Chemical) => {
    setDetailChem(c);
    setDetailChemOpen(true);
  };

  const openAppDetail = (a: Apparatus) => {
    setDetailApp(a);
    setDetailAppOpen(true);
  };

  const handleSearch = (q: string) => {
    setSearch(q);
    setTab("chemicals");
  };

  const handleQuickAdd = (kind: "chemical" | "apparatus") => {
    if (kind === "chemical") {
      setAddChemOpen(true);
    } else {
      setAddAppOpen(true);
    }
  };

  const handleScan = () => setTab("scan");

  // After a log action, refresh the detail modal's chemical reference so
  // quantities stay in sync. We pull fresh from the store on each render
  // via the live store subscription below.

  return (
    <div className="min-h-screen flex flex-col items-center" style={{ background: "var(--desk)" }}>
      <div className="nb-page w-full max-w-[420px] flex-1 flex flex-col relative">
        <main className="flex-1 relative" style={{ paddingLeft: "50px", paddingRight: "18px", paddingTop: "20px" }}>
          {tab === "home" && (
            <DashboardScreen
              onNavigate={setTab}
              onSearch={handleSearch}
              onQuickAdd={handleQuickAdd}
              onScan={handleScan}
            />
          )}
          {tab === "chemicals" && (
            <ChemicalsScreen
              searchQuery={search}
              onSearchChange={setSearch}
              onAdd={() => setAddChemOpen(true)}
              onOpenDetail={openChemDetail}
            />
          )}
          {tab === "apparatus" && (
            <ApparatusScreen
              searchQuery={search}
              onSearchChange={setSearch}
              onAdd={() => setAddAppOpen(true)}
              onOpenDetail={openAppDetail}
            />
          )}
          {tab === "scan" && (
            <ScannerScreen
              onScanned={(c) => {
                openChemDetail(c);
              }}
            />
          )}
          {tab === "reports" && <ReportsScreen />}
        </main>
      </div>

      {/* Settings as an overlay screen rather than a tab */}
      {settingsOpen && (
        <div className="fixed inset-0 z-50 overflow-y-auto nb-page" style={{ maxWidth: "420px", margin: "0 auto" }}>
          <div className="sticky top-0 z-10 px-4 py-3 flex items-center justify-between no-print" style={{ paddingLeft: "50px", paddingRight: "18px", borderBottom: "1.5px dashed var(--ruled-line)" }}>
            <button
              onClick={() => setSettingsOpen(false)}
              className="font-display text-xl font-semibold underline"
              style={{ color: "var(--ink-muted)", textUnderlineOffset: "3px" }}
            >
              ← back
            </button>
          </div>
          <SettingsScreen />
        </div>
      )}

      {/* Floating settings button (top-right) */}
      {!settingsOpen && (
        <button
          onClick={() => setSettingsOpen(true)}
          aria-label="settings"
          className="fixed top-3 right-4 z-30 no-print font-display text-lg font-semibold"
          style={{ color: "var(--ink-muted)" }}
        >
          ⚙
        </button>
      )}

      <BottomNav
        active={tab}
        onChange={(t) => {
          setTab(t);
          setSettingsOpen(false);
          if (t !== "chemicals" && t !== "apparatus") setSearch("");
        }}
      />

      {/* ============ Chemical modals ============ */}
      <AddChemicalModal open={addChemOpen} onClose={() => setAddChemOpen(false)} />

      <ChemicalDetailModal
        chemical={detailChem}
        open={detailChemOpen}
        onClose={() => setDetailChemOpen(false)}
        onConsume={() => {
          if (!detailChem) return;
          setLogChem(detailChem);
          setLogChemAction("consume");
          setDetailChemOpen(false);
          setLogChemOpen(true);
        }}
        onRestock={() => {
          if (!detailChem) return;
          setLogChem(detailChem);
          setLogChemAction("restock");
          setDetailChemOpen(false);
          setLogChemOpen(true);
        }}
        onEdit={() => {
          if (!detailChem) return;
          setEditChem(detailChem);
          setDetailChemOpen(false);
          setEditChemOpen(true);
        }}
        onShowQR={() => {
          if (!detailChem) return;
          setQrChem(detailChem);
          setDetailChemOpen(false);
          setQrChemOpen(true);
        }}
      />

      <ChemicalLogModal
        chemical={logChem}
        action={logChemAction}
        open={logChemOpen}
        onClose={() => setLogChemOpen(false)}
      />

      <EditChemicalModal
        chemical={editChem}
        open={editChemOpen}
        onClose={() => setEditChemOpen(false)}
      />

      <ChemicalQRModal
        chemical={qrChem}
        open={qrChemOpen}
        onClose={() => setQrChemOpen(false)}
      />

      {/* ============ Apparatus modals ============ */}
      <AddApparatusModal open={addAppOpen} onClose={() => setAddAppOpen(false)} />

      <ApparatusDetailModal
        apparatus={detailApp}
        open={detailAppOpen}
        onClose={() => setDetailAppOpen(false)}
        onBreakage={() => {
          if (!detailApp) return;
          setLogApp(detailApp);
          setLogAppAction("breakage");
          setDetailAppOpen(false);
          setLogAppOpen(true);
        }}
        onRestock={() => {
          if (!detailApp) return;
          setLogApp(detailApp);
          setLogAppAction("restock");
          setDetailAppOpen(false);
          setLogAppOpen(true);
        }}
        onEdit={() => {
          if (!detailApp) return;
          setEditApp(detailApp);
          setDetailAppOpen(false);
          setEditAppOpen(true);
        }}
      />

      <ApparatusLogModal
        apparatus={logApp}
        action={logAppAction}
        open={logAppOpen}
        onClose={() => setLogAppOpen(false)}
      />

      <EditApparatusModal
        apparatus={editApp}
        open={editAppOpen}
        onClose={() => setEditAppOpen(false)}
      />
    </div>
  );
}
