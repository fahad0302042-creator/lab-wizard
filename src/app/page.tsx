"use client";

import { useState, useEffect } from "react";
import { AnimatePresence, motion } from "framer-motion";
import { useLabStore } from "@/lib/store";
import type { TabKey, Chemical, Apparatus } from "@/lib/types";
import { AuthScreen } from "@/components/screens/auth-screen";
import { DashboardScreen } from "@/components/screens/dashboard-screen";
import { ChemicalsScreen } from "@/components/screens/chemicals-screen";
import { ApparatusScreen } from "@/components/screens/apparatus-screen";
import { ScannerScreen } from "@/components/screens/scanner-screen";
import { ReportsScreen } from "@/components/screens/reports-screen";
import { SettingsScreen } from "@/components/screens/settings-screen";
import { QrLabelsScreen } from "@/components/screens/qr-labels-screen";
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
import { BatchConsumeModal } from "@/components/modals/batch-consume-modal";

export default function Page() {
  const user = useLabStore((s) => s.user);
  const restoreSession = useLabStore((s) => s.restoreSession);
  const [restoring, setRestoring] = useState(true);

  // Restore Supabase session on mount (if configured)
  useEffect(() => {
    const restore = async () => {
      try {
        await restoreSession();
      } catch {
        // ignore
      }
      setRestoring(false);
    };
    restore();
  }, [restoreSession]);

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
  const [qrLabelsOpen, setQrLabelsOpen] = useState(false);
  const [batchConsumeOpen, setBatchConsumeOpen] = useState(false);

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

  if (restoring) {
    return (
      <div
        className="min-h-screen flex items-center justify-center"
        style={{ background: "var(--desk)" }}
      >
        <div
          className="nb-card p-8"
          style={{ textAlign: "center" }}
        >
          <p
            className="font-display text-2xl font-bold"
            style={{ color: "var(--ink)" }}
          >
            opening your notebook…
          </p>
        </div>
      </div>
    );
  }

  if (!user) {
    return <AuthScreen />;
  }

  return (
    <div id="app-root" className="min-h-screen flex flex-col items-center" style={{ background: "var(--desk)" }}>
      <div className="nb-page w-full max-w-[420px] flex-1 flex flex-col relative">
        <main className="flex-1 relative" style={{ paddingLeft: "50px", paddingRight: "18px", paddingTop: "20px" }}>
          <AnimatePresence mode="wait">
            <motion.div
              key={tab}
              initial={{ opacity: 0, y: 8 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -4 }}
              transition={{ duration: 0.2, ease: "easeOut" }}
            >
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
              onPrintQrLabels={() => setQrLabelsOpen(true)}
              onQuickConsume={(c) => {
                setLogChem(c);
                setLogChemAction("consume");
                setLogChemOpen(true);
              }}
              onQuickRestock={(c) => {
                setLogChem(c);
                setLogChemAction("restock");
                setLogChemOpen(true);
              }}
              onBatchConsume={() => setBatchConsumeOpen(true)}
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
            </motion.div>
          </AnimatePresence>
        </main>
      </div>

      {/* QR Labels printing overlay */}
      {qrLabelsOpen && (
        <div
          className="fixed inset-0 z-[100] overflow-y-auto"
          style={{ background: "#f0f0f0", paddingTop: "60px" }}
        >
          <QrLabelsScreen onClose={() => setQrLabelsOpen(false)} />
        </div>
      )}

      {/* Settings as a full-screen overlay */}
      {settingsOpen && (
        <div
          className="fixed inset-0 z-[100] overflow-y-auto"
          style={{ background: "var(--desk)" }}
        >
          <div
            className="nb-page w-full max-w-[420px] mx-auto min-h-screen relative"
          >
            <div
              className="sticky top-0 z-10 py-3 flex items-center justify-between no-print"
              style={{
                paddingLeft: "50px",
                paddingRight: "18px",
                borderBottom: "1.5px dashed var(--ruled-line)",
                background: "var(--paper)",
              }}
            >
              <button
                onClick={() => setSettingsOpen(false)}
                className="font-display text-xl font-semibold underline"
                style={{ color: "var(--ink-muted)", textUnderlineOffset: "3px" }}
              >
                ← back
              </button>
            </div>
            <div style={{ paddingLeft: "50px", paddingRight: "18px", paddingTop: "20px" }}>
              <SettingsScreen />
            </div>
          </div>
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

      {/* Batch consume */}
      <BatchConsumeModal
        open={batchConsumeOpen}
        onClose={() => setBatchConsumeOpen(false)}
      />
    </div>
  );
}
