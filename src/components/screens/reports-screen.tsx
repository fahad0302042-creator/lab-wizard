"use client";

import { useState, useMemo } from "react";
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
import type { ItemType } from "@/lib/types";

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

  // Build per-item report rows: only items with usage in the selected month.
  const rows = useMemo(() => {
    const items =
      tab === "chemical"
        ? chemicals.map((c) => ({ id: c.id, name: c.name, formulaOrCat: c.formula, quantity: c.quantity, initial: c.initial_quantity, unit: c.unit }))
        : apparatus.map((a) => ({ id: a.id, name: a.name, formulaOrCat: a.category, quantity: a.quantity, initial: a.initial_quantity, unit: "pcs" as const }));

    return items
      .map((item) => {
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
        const left = item.quantity;
        const stockItem = tab === "chemical"
          ? chemicals.find((c) => c.id === item.id)!
          : apparatus.find((a) => a.id === item.id)!;
        return {
          ...item,
          used,
          added,
          left,
          status: stockStatus(stockItem),
          pct: percentRemaining(stockItem),
        };
      })
      .filter((r): r is NonNullable<typeof r> => r !== null)
      .sort((a, b) => b.used - a.used);
  }, [chemicals, apparatus, monthLogs, tab]);

  const totalUsed = rows.reduce((s, r) => s + r.used, 0);
  const totalAdded = rows.reduce((s, r) => s + r.added, 0);

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

  return (
    <div className="pb-24">
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
      <div className="flex items-center gap-3 mb-5 no-print">
        <CircledButton onClick={() => window.print()}>
          generate report (PDF)
        </CircledButton>
        <button
          onClick={handleClear}
          className="font-display text-lg font-semibold underline"
          style={{ color: "var(--margin-red)", textUnderlineOffset: "3px" }}
        >
          clear {monthLabel(selectedMonth).split(" ")[0]} data
        </button>
      </div>

      {/* Report table */}
      <NotebookCard tilt={0} className="print-clean">
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
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </NotebookCard>

      <p
        className="font-body text-xs mt-4 text-center no-print"
        style={{ color: "var(--ink-muted)" }}
      >
        only items with usage this month are shown. “generate report” opens your browser's print dialog — save as PDF for a clean copy.
      </p>
    </div>
  );
}
