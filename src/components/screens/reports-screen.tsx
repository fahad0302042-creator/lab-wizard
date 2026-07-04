"use client";

import { useState, useMemo } from "react";
import { createPortal } from "react-dom";
import { toast } from "sonner";
import { useLabStore } from "@/lib/store";
import {
  SectionTitle,
  NotebookCard,
  CircledButton,
} from "@/components/notebook/primitives";
import {
  monthLabel,
  recentMonthKeys,
  statusColor,
  percentRemaining,
  stockStatus,
} from "@/lib/utils";
import { ShareIcon, PrintIcon } from "@/components/notebook/icons";
import type { ItemType } from "@/lib/types";

interface ReportRow {
  id: string;
  name: string;
  formulaOrCat: string;
  quantity: number;
  unit: string;
  used: number;
  added: number;
  left: number;
  status: ReturnType<typeof stockStatus>;
  pct: number;
}

export function ReportsScreen() {
  const chemicals = useLabStore((s) => s.chemicals);
  const apparatus = useLabStore((s) => s.apparatus);
  const logs = useLabStore((s) => s.logs);
  const clearMonth = useLabStore((s) => s.clearMonth);

  const monthKeys = useMemo(() => recentMonthKeys(), []);
  const [selectedMonth, setSelectedMonth] = useState(monthKeys[0]);
  const [tab, setTab] = useState<ItemType>("chemical");

  const monthLogs = useMemo(
    () => logs.filter((l) => l.logged_at.slice(0, 7) === selectedMonth),
    [logs, selectedMonth]
  );

  const rows = useMemo(() => {
    const items =
      tab === "chemical"
        ? chemicals.map((c) => ({ id: c.id, name: c.name, formulaOrCat: c.formula, quantity: c.quantity, initial: c.initial_quantity, unit: c.unit }))
        : apparatus.map((a) => ({ id: a.id, name: a.name, formulaOrCat: a.category, quantity: a.quantity, initial: a.initial_quantity, unit: "pcs" as const }));

    return items
      .map((item): ReportRow | null => {
        const itemLogs = monthLogs.filter(
          (l) => l.item_id === item.id && l.item_type === tab
        );
        if (itemLogs.length === 0) return null;
        const used = itemLogs
          .filter((l) => l.action === "consume" || l.action === "breakage")
          .reduce((s, l) => s + l.amount, 0);
        const added = itemLogs
          .filter((l) => l.action === "restock")
          .reduce((s, l) => s + l.amount, 0);
        if (used === 0 && added === 0) return null;
        const stockItem = tab === "chemical"
          ? chemicals.find((c) => c.id === item.id)!
          : apparatus.find((a) => a.id === item.id)!;
        return {
          ...item,
          used,
          added,
          left: item.quantity,
          status: stockStatus(stockItem),
          pct: percentRemaining(stockItem),
        };
      })
      .filter((r): r is ReportRow => r !== null)
      .sort((a, b) => b.used - a.used);
  }, [chemicals, apparatus, monthLogs, tab]);

  const totalUsed = rows.reduce((s, r) => s + r.used, 0);
  const totalAdded = rows.reduce((s, r) => s + r.added, 0);
  const criticalCount = rows.filter((r) => r.pct < 20).length;

  const handleClear = () => {
    if (
      !confirm(
        `Clear all log entries for ${monthLabel(selectedMonth)}? This cannot be undone.`
      )
    )
      return;
    clearMonth(selectedMonth);
    toast.success(`cleared ${monthLabel(selectedMonth)} data`);
  };

  // Determine asterisk for a row: ** below 20%, * below 50%
  const asteriskFor = (pct: number) => {
    if (pct < 20) return "**";
    if (pct < 50) return "*";
    return "";
  };

  const buildReportHTML = () => {
    const reportEl = document.querySelector(".print-only");
    if (!reportEl) return null;
    const reportHTML = reportEl.innerHTML;
    const title = `Lab Wizard — ${tab === "chemical" ? "Chemicals" : "Apparatus"} Report — ${monthLabel(selectedMonth)}`;
    return {
      title,
      html: `<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>${title}</title>
<style>
  @page { size: A4; margin: 12mm; }
  html, body { margin: 0; padding: 0; background: #f0f0f0; font-family: 'Helvetica Neue', Arial, sans-serif; color: #1a1a1a; }
  * { box-sizing: border-box; }
  .report-page { background: white; max-width: 210mm; margin: 20px auto; padding: 36px; box-shadow: 0 2px 12px rgba(0,0,0,0.1); }
  .print-toolbar { position: sticky; top: 0; background: #1a1a1a; color: white; padding: 10px 20px; display: flex; align-items: center; justify-content: space-between; z-index: 100; }
  .print-btn { background: #fff; color: #1a1a1a; border: none; padding: 8px 20px; font-size: 14px; font-weight: 600; border-radius: 4px; cursor: pointer; font-family: inherit; }
  .print-btn:hover { background: #f0f0f0; }
  .print-hint { font-size: 12px; opacity: 0.7; }
  @media print {
    body { background: white; }
    .print-toolbar { display: none !important; }
    .report-page { margin: 0; padding: 0; box-shadow: none; max-width: none; }
    @page { size: A4; margin: 12mm; }
  }
</style>
</head>
<body>
  <div class="print-toolbar">
    <span style="font-size: 14px; font-weight: 600;">Lab Wizard Report</span>
    <div style="display: flex; align-items: center; gap: 14px;">
      <span class="print-hint">click to print / save as PDF</span>
      <button class="print-btn" onclick="window.print()">🖨 Print</button>
    </div>
  </div>
  <div class="report-page">${reportHTML}</div>
</body>
</html>`,
    };
  };

  const handlePrint = () => {
    const built = buildReportHTML();
    if (!built) {
      toast.error("no report data to print");
      return;
    }

    // Try opening a new window first (works outside iframes)
    const win = window.open("", "_blank", "width=800,height=900");
    if (win && !win.closed) {
      win.document.write(built.html);
      win.document.close();
      win.focus();
      setTimeout(() => {
        try {
          win.print();
        } catch {
          // ignore
        }
      }, 600);
      toast.success("report opened — click the Print button to save as PDF");
    } else {
      // Pop-up blocked (common in iframes) — download the HTML file instead
      const blob = new Blob([built.html], { type: "text/html" });
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = `lab-wizard-report-${selectedMonth}.html`;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      URL.revokeObjectURL(url);
      toast.success("report downloaded — open the HTML file and click Print to save as PDF");
    }
  };

  const handleShare = async () => {
    const built = buildReportHTML();
    if (!built) {
      toast.error("no report data to share");
      return;
    }

    const filename = `lab-wizard-report-${selectedMonth}.html`;
    const file = new File([built.html], filename, { type: "text/html" });
    const shareData = {
      title: built.title,
      text: `${tab === "chemical" ? "Chemicals" : "Apparatus"} usage report for ${monthLabel(selectedMonth)} — ${rows.length} items, ${totalUsed} used.`,
    };

    // Try Web Share API with file (works on mobile — WhatsApp, email, etc.)
    if (typeof navigator !== "undefined" && navigator.share) {
      try {
        // Some browsers support file sharing, others only text
        if (navigator.canShare && navigator.canShare({ files: [file] })) {
          await navigator.share({ ...shareData, files: [file] });
          toast.success("report shared");
        } else {
          // Fallback: share text + download the file
          await navigator.share(shareData);
          // Also trigger a download so the user has the file
          const blob = new Blob([built.html], { type: "text/html" });
          const url = URL.createObjectURL(blob);
          const a = document.createElement("a");
          a.href = url;
          a.download = filename;
          document.body.appendChild(a);
          a.click();
          document.body.removeChild(a);
          URL.revokeObjectURL(url);
          toast.success("report shared — HTML file also saved to your device");
        }
        return;
      } catch (err) {
        // User cancelled or share failed — fall through to download
        if (err instanceof Error && err.name === "AbortError") {
          return; // user cancelled, no toast
        }
      }
    }

    // Fallback: download the HTML file (desktop / no Web Share API)
    const blob = new Blob([built.html], { type: "text/html" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
    toast.success("report downloaded — share the HTML file via WhatsApp or email");
  };

  return (
    <>
      {/* ============ On-screen notebook version ============ */}
      <div className="pb-24 no-print">
        <div className="mb-4">
          <SectionTitle>monthly report</SectionTitle>
        </div>

        {/* Month selector tabs */}
        <div className="flex gap-2 overflow-x-auto no-scrollbar pb-2 mb-3">
          {monthKeys.map((mk) => (
            <button
              key={mk}
              onClick={() => setSelectedMonth(mk)}
              className="shrink-0 font-display text-lg font-semibold px-2 py-0.5"
              style={{
                color: mk === selectedMonth ? "var(--margin-red)" : "var(--ink-muted)",
                textDecoration: mk === selectedMonth ? "underline" : "none",
                textUnderlineOffset: "3px",
              }}
            >
              {monthLabel(mk)}
            </button>
          ))}
        </div>

        {/* Type toggle */}
        <div className="flex items-center gap-4 mb-4">
          <button
            onClick={() => setTab("chemical")}
            className="font-display text-xl font-semibold"
            style={{
              color: tab === "chemical" ? "var(--margin-red)" : "var(--ink-muted)",
              textDecoration: tab === "chemical" ? "underline" : "none",
              textUnderlineOffset: "4px",
            }}
          >
            chemicals
          </button>
          <button
            onClick={() => setTab("apparatus")}
            className="font-display text-xl font-semibold"
            style={{
              color: tab === "apparatus" ? "var(--margin-red)" : "var(--ink-muted)",
              textDecoration: tab === "apparatus" ? "underline" : "none",
              textUnderlineOffset: "4px",
            }}
          >
            apparatus
          </button>
        </div>

        {/* Summary stats */}
        <div className="flex gap-6 mb-4 font-body text-sm" style={{ color: "var(--ink-muted)" }}>
          <span>
            <strong style={{ color: "var(--stock-low)" }}>{totalUsed}</strong> used
          </span>
          <span>
            <strong style={{ color: "var(--stock-healthy)" }}>{totalAdded}</strong> added
          </span>
          <span>{rows.length} items touched</span>
        </div>

        {/* Actions */}
        <div className="flex items-center gap-3 mb-3 flex-wrap">
          <CircledButton onClick={handleShare}>
            <ShareIcon width="16" height="16" /> share
          </CircledButton>
          <CircledButton onClick={handlePrint}>
            <PrintIcon width="16" height="16" /> print / PDF
          </CircledButton>
        </div>
        <div className="flex items-center gap-3 mb-5">
          <button
            onClick={handleClear}
            className="font-display text-lg font-semibold underline"
            style={{ color: "var(--margin-red)", textUnderlineOffset: "3px" }}
          >
            clear {monthLabel(selectedMonth).split(" ")[0]} data
          </button>
        </div>

        {/* Report table */}
        <NotebookCard tilt={0}>
          <div className="mb-3">
            <h3
              className="font-display font-bold"
              style={{ fontSize: "24px", color: "var(--ink)" }}
            >
              {tab === "chemical" ? "Chemicals" : "Apparatus"} — {monthLabel(selectedMonth)}
            </h3>
          </div>

          {rows.length === 0 ? (
            <p className="font-body text-sm py-6 text-center" style={{ color: "var(--ink-muted)" }}>
              no {tab} usage logged this month.
            </p>
          ) : (
            <table className="w-full font-body text-sm" style={{ borderCollapse: "collapse" }}>
              <thead>
                <tr style={{ borderBottom: "2px solid var(--ruled-line)" }}>
                  <th className="text-left py-2 pr-2 font-display font-bold" style={{ color: "var(--ink-muted)" }}>
                    Name
                  </th>
                  <th className="text-right py-2 px-2 font-display font-bold" style={{ color: "var(--ink-muted)" }}>
                    Stock
                  </th>
                  <th className="text-right py-2 px-2 font-display font-bold" style={{ color: "var(--stock-low)" }}>
                    −Used
                  </th>
                  <th className="text-right py-2 pl-2 font-display font-bold" style={{ color: "var(--margin-red)" }}>
                    =Left
                  </th>
                </tr>
              </thead>
              <tbody>
                {rows.map((r) => (
                  <tr
                    key={r.id}
                    style={{ borderBottom: "1.5px dashed var(--ruled-line)" }}
                  >
                    <td className="py-2 pr-2">
                      <div className="font-accent font-bold" style={{ color: "var(--ink)", fontSize: "16px" }}>
                        {r.name}
                      </div>
                      {r.formulaOrCat && (
                        <div className="text-xs" style={{ color: "var(--ink-muted)" }}>
                          {r.formulaOrCat}
                        </div>
                      )}
                    </td>
                    <td className="text-right py-2 px-2" style={{ color: "var(--ink-muted)" }}>
                      {r.quantity} {r.unit}
                    </td>
                    <td className="text-right py-2 px-2" style={{ color: "var(--stock-low)" }}>
                      −{r.used}
                    </td>
                    <td
                      className={`text-right py-2 pl-2 font-bold ${statusColor(r.status)}`}
                    >
                      {r.left} {r.unit}
                      {asteriskFor(r.pct) && (
                        <span style={{ color: "var(--margin-red)" }}>{asteriskFor(r.pct)}</span>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}

          {rows.length > 0 && (
            <p className="font-body text-xs mt-3" style={{ color: "var(--ink-muted)" }}>
              <span style={{ color: "var(--margin-red)" }}>*</span> below 50% remaining &nbsp;
              <span style={{ color: "var(--margin-red)" }}>**</span> below 20% remaining — reorder
            </p>
          )}
        </NotebookCard>

        <p
          className="font-body text-xs mt-4 text-center"
          style={{ color: "var(--ink-muted)" }}
        >
          only items with usage this month are shown. tap "share" to send via WhatsApp/email, or "print / PDF" to save as PDF.
        </p>
      </div>

      {/* ============ Print-only report (portaled to body, matches reference PDF) ============ */}
      <PrintReportPortal
        rows={rows}
        tab={tab}
        selectedMonth={selectedMonth}
        totalUsed={totalUsed}
        totalAdded={totalAdded}
        criticalCount={criticalCount}
      />
    </>
  );
}

function PrintReportPortal(props: {
  rows: ReportRow[];
  tab: ItemType;
  selectedMonth: string;
  totalUsed: number;
  totalAdded: number;
  criticalCount: number;
}) {
  if (typeof document === "undefined") return null;
  return createPortal(<PrintReport {...props} />, document.body);
}

function PrintReport({
  rows,
  tab,
  selectedMonth,
  totalUsed,
  totalAdded,
  criticalCount,
}: {
  rows: ReportRow[];
  tab: ItemType;
  selectedMonth: string;
  totalUsed: number;
  totalAdded: number;
  criticalCount: number;
}) {
  const now = new Date();
  const generated = `${now.toLocaleDateString("en-GB", { day: "2-digit", month: "short", year: "numeric" }).replace(/ /g, " ")}, ${now.toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit" })}`;

  const asteriskFor = (pct: number) => {
    if (pct < 20) return "**";
    if (pct < 50) return "*";
    return "";
  };

  const itemsUsedCount = rows.filter((r) => r.used > 0).length;
  const restockedCount = rows.filter((r) => r.added > 0).length;

  return (
    <div
      className="print-only"
      style={{
        fontFamily: "'Helvetica Neue', Arial, sans-serif",
        color: "#1a1a1a",
        background: "white",
        padding: "40px 36px",
        maxWidth: "210mm",
        margin: "0 auto",
      }}
    >
      {/* Header */}
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start", borderBottom: "2px solid #1a1a1a", paddingBottom: "12px", marginBottom: "20px" }}>
        <div>
          <div style={{ fontSize: "22px", fontWeight: 700, letterSpacing: "-0.5px" }}>Lab Wizard</div>
          <div style={{ fontSize: "12px", color: "#666", marginTop: "1px" }}>bench inventory</div>
        </div>
        <div style={{ textAlign: "right" }}>
          <div style={{ fontSize: "16px", fontWeight: 600 }}>
            {tab === "chemical" ? "Chemicals" : "Apparatus"} Usage Report
          </div>
          <div style={{ fontSize: "11px", color: "#666", marginTop: "3px" }}>
            Period: {monthLabel(selectedMonth)} &nbsp;·&nbsp; Generated: {generated}
          </div>
        </div>
      </div>

      {/* KPI boxes */}
      <div style={{ display: "flex", gap: "12px", marginBottom: "24px" }}>
        <KpiBox value={itemsUsedCount} label="Items used" color="#1a1a1a" />
        <KpiBox value={restockedCount} label="Restocked" color="#5E8C5A" />
        <KpiBox value={criticalCount} label="Critical" color="#B23A2E" />
      </div>

      {/* Table */}
      {rows.length === 0 ? (
        <p style={{ fontSize: "13px", color: "#666", textAlign: "center", padding: "30px 0" }}>
          No {tab} usage logged for {monthLabel(selectedMonth)}.
        </p>
      ) : (
        <table style={{ width: "100%", borderCollapse: "collapse", fontSize: "13px" }}>
          <thead>
            <tr style={{ borderBottom: "2px solid #1a1a1a" }}>
              <th style={{ textAlign: "left", padding: "8px 6px", fontWeight: 700, fontSize: "12px", textTransform: "uppercase", letterSpacing: "0.5px", color: "#555" }}>
                Name
              </th>
              <th style={{ textAlign: "right", padding: "8px 6px", fontWeight: 700, fontSize: "12px", textTransform: "uppercase", letterSpacing: "0.5px", color: "#555", whiteSpace: "nowrap" }}>
                Stock
              </th>
              <th style={{ textAlign: "right", padding: "8px 6px", fontWeight: 700, fontSize: "12px", textTransform: "uppercase", letterSpacing: "0.5px", color: "#555", whiteSpace: "nowrap" }}>
                − Used
              </th>
              <th style={{ textAlign: "right", padding: "8px 6px", fontWeight: 700, fontSize: "12px", textTransform: "uppercase", letterSpacing: "0.5px", color: "#555", whiteSpace: "nowrap" }}>
                = Left
              </th>
            </tr>
          </thead>
          <tbody>
            {rows.map((r) => {
              const ast = asteriskFor(r.pct);
              return (
                <tr key={r.id} style={{ borderBottom: "1px solid #e0e0e0" }}>
                  <td style={{ padding: "8px 6px", verticalAlign: "top" }}>
                    <div style={{ fontWeight: 600, fontSize: "13px" }}>{r.name}</div>
                    {r.formulaOrCat && (
                      <div style={{ fontSize: "11px", color: "#888", marginTop: "1px" }}>
                        {r.formulaOrCat}
                      </div>
                    )}
                  </td>
                  <td style={{ textAlign: "right", padding: "8px 6px", verticalAlign: "top", whiteSpace: "nowrap", color: "#555" }}>
                    {r.quantity} {r.unit}
                  </td>
                  <td style={{ textAlign: "right", padding: "8px 6px", verticalAlign: "top", whiteSpace: "nowrap", color: "#D89A3E" }}>
                    −{r.used}
                  </td>
                  <td style={{ textAlign: "right", padding: "8px 6px", verticalAlign: "top", whiteSpace: "nowrap", fontWeight: 600 }}>
                    {r.left} {r.unit}
                    {ast && <span style={{ color: "#B23A2E" }}>{ast}</span>}
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      )}

      {/* Footer note */}
      {rows.length > 0 && (
        <div style={{ marginTop: "20px", paddingTop: "10px", borderTop: "1px solid #e0e0e0", fontSize: "11px", color: "#666" }}>
          <span style={{ color: "#B23A2E" }}>*</span> below 50% remaining &nbsp;&nbsp;
          <span style={{ color: "#B23A2E" }}>**</span> below 20% remaining — reorder &nbsp;&nbsp;
          <span style={{ float: "right" }}>Page 1</span>
        </div>
      )}
    </div>
  );
}

function KpiBox({ value, label, color }: { value: number; label: string; color: string }) {
  return (
    <div
      style={{
        flex: 1,
        border: "1.5px solid #1a1a1a",
        borderRadius: "4px",
        padding: "10px 14px",
        background: "white",
      }}
    >
      <div style={{ fontSize: "28px", fontWeight: 700, color, lineHeight: 1 }}>{value}</div>
      <div style={{ fontSize: "11px", color: "#666", marginTop: "3px", textTransform: "uppercase", letterSpacing: "0.5px" }}>
        {label}
      </div>
    </div>
  );
}
