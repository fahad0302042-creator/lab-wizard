"use client";

import { useState } from "react";
import { toast } from "sonner";
import { useLabStore } from "@/lib/store";
import type { Chemical } from "@/lib/types";
import { Modal } from "@/components/notebook/modal";
import { RuledInput, RuledTextarea, CircledButton } from "@/components/notebook/primitives";
import { hapticSuccess } from "@/lib/haptics";

/**
 * Batch consume modal — select multiple chemicals and log usage at once.
 * Useful after a lab session where you used many chemicals.
 */
export function BatchConsumeModal({
  open,
  onClose,
}: {
  open: boolean;
  onClose: () => void;
}) {
  const chemicals = useLabStore((s) => s.chemicals);
  const batchConsume = useLabStore((s) => s.batchConsume);
  const [search, setSearch] = useState("");
  const [amounts, setAmounts] = useState<Record<string, string>>({});
  const [note, setNote] = useState("");
  const [busy, setBusy] = useState(false);

  const filtered = chemicals.filter((c) => {
    if (c.quantity <= 0) return false;
    if (!search.trim()) return true;
    return `${c.name} ${c.formula}`.toLowerCase().includes(search.toLowerCase());
  });

  const setAmount = (id: string, value: string) => {
    setAmounts((prev) => ({ ...prev, [id]: value }));
  };

  const selectedCount = Object.values(amounts).filter((v) => {
    const n = Number(v);
    return Number.isFinite(n) && n > 0;
  }).length;

  const submit = async () => {
    type Entry = { itemId: string; itemType: "chemical"; amount: number; note?: string };
    const entries: Entry[] = [];
    for (const [itemId, val] of Object.entries(amounts)) {
      const amt = Number(val);
      if (Number.isFinite(amt) && amt > 0) {
        const chem = chemicals.find((c) => c.id === itemId);
        if (chem && amt <= chem.quantity) {
          entries.push({ itemId, itemType: "chemical", amount: amt, note });
        } else if (chem && amt > chem.quantity) {
          toast.error(`${chem.name}: only ${chem.quantity} ${chem.unit} on hand`);
          return;
        }
      }
    }

    if (entries.length === 0) {
      toast.error("enter at least one amount");
      return;
    }

    setBusy(true);
    try {
      await batchConsume(entries);
      hapticSuccess();
      toast.success(`consumed ${entries.length} item${entries.length > 1 ? "s" : ""}`);
      setAmounts({});
      setNote("");
      setSearch("");
      onClose();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "couldn't batch consume");
    } finally {
      setBusy(false);
    }
  };

  return (
    <Modal
      open={open}
      onClose={onClose}
      title="batch consume"
      size="lg"
      footer={
        <>
          <CircledButton onClick={onClose}>cancel</CircledButton>
          <CircledButton onClick={submit} variant="danger" disabled={busy || selectedCount === 0}>
            {busy ? "…" : `consume ${selectedCount || ""}`}
          </CircledButton>
        </>
      }
    >
      <div className="flex flex-col gap-3">
        <p className="font-body text-sm" style={{ color: "var(--ink-muted)" }}>
          enter amounts for each chemical used in this session, then tap consume.
        </p>

        {/* Search */}
        <RuledInput
          label="filter"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          placeholder="search by name or formula…"
        />

        {/* List with amount inputs */}
        <div className="max-h-80 overflow-y-auto nb-scroll flex flex-col gap-1" style={{ marginTop: "4px" }}>
          {filtered.length === 0 ? (
            <p className="font-body text-sm text-center py-4" style={{ color: "var(--ink-muted)" }}>
              no chemicals in stock to consume.
            </p>
          ) : (
            filtered.map((c) => (
              <div
                key={c.id}
                className="flex items-center gap-2 py-2 px-2"
                style={{ borderBottom: "1.5px dashed var(--ruled-line)" }}
              >
                <div className="flex-1 min-w-0">
                  <div className="font-accent font-bold truncate" style={{ color: "var(--ink)", fontSize: "15px" }}>
                    {c.name}
                  </div>
                  <div className="font-body text-xs" style={{ color: "var(--ink-muted)" }}>
                    {c.quantity} {c.unit} on hand{c.formula ? ` · ${c.formula}` : ""}
                  </div>
                </div>
                <input
                  type="number"
                  inputMode="decimal"
                  value={amounts[c.id] || ""}
                  onChange={(e) => setAmount(c.id, e.target.value)}
                  placeholder="0"
                  className="font-body text-right"
                  style={{
                    width: 70,
                    background: "transparent",
                    border: "1.5px solid var(--ruled-line)",
                    borderRadius: "4px",
                    padding: "4px 8px",
                    color: "var(--ink)",
                    fontFamily: "var(--font-body), cursive",
                    fontSize: "14px",
                    outline: "none",
                  }}
                />
                <span className="font-body text-xs" style={{ color: "var(--ink-muted)", width: 30 }}>
                  {c.unit}
                </span>
              </div>
            ))
          )}
        </div>

        {/* Shared note */}
        <RuledTextarea
          label="note (applies to all)"
          value={note}
          onChange={(e) => setNote(e.target.value)}
          placeholder="e.g. titration lab, period 3"
        />
      </div>
    </Modal>
  );
}
