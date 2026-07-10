"use client";

import { useState } from "react";
import { toast } from "sonner";
import { useLabStore } from "@/lib/store";
import type { ConsumptionLog, Chemical, Apparatus } from "@/lib/types";
import { shortDate, todayLocalDate, dateToNoonISO } from "@/lib/utils";
import { RuledInput, RuledTextarea, CircledButton } from "@/components/notebook/primitives";
import { Modal } from "@/components/notebook/modal";
import { PencilIcon, TrashIcon } from "@/components/notebook/icons";

/**
 * Shows all consume/restock/breakage log entries for a single item,
 * with edit + delete options for each entry.
 */
export function LogHistory({
  item,
  itemType,
}: {
  item: Chemical | Apparatus;
  itemType: "chemical" | "apparatus";
}) {
  const logs = useLabStore((s) => s.logs);
  const deleteLog = useLabStore((s) => s.deleteLog);
  const [editingLog, setEditingLog] = useState<ConsumptionLog | null>(null);
  const [editOpen, setEditOpen] = useState(false);

  const itemLogs = logs
    .filter((l) => l.item_id === item.id && l.item_type === itemType)
    .sort((a, b) => new Date(b.logged_at).getTime() - new Date(a.logged_at).getTime());

  const handleDelete = async (log: ConsumptionLog) => {
    if (!confirm(`Delete this ${log.action} entry (${log.amount} on ${shortDate(log.logged_at)})?\n\nThe quantity will be reversed.`)) return;
    try {
      await deleteLog(log.id);
      toast.success("entry deleted — quantity reversed");
    } catch {
      toast.error("couldn't delete entry");
    }
  };

  if (itemLogs.length === 0) {
    return (
      <p
        className="font-body text-sm py-4 text-center"
        style={{ color: "var(--ink-muted)" }}
      >
        no activity logged yet.
      </p>
    );
  }

  return (
    <>
      <div className="flex flex-col gap-1">
        {itemLogs.map((log) => {
          const isPositive = log.action === "restock";
          const isBreakage = log.action === "breakage";
          const sign = isPositive ? "+" : "−";
          const color = isPositive
            ? "var(--stock-healthy)"
            : isBreakage
              ? "var(--margin-red)"
              : "var(--stock-low)";

          return (
            <div
              key={log.id}
              className="flex items-start gap-2 py-2 px-2"
              style={{ borderBottom: "1.5px dashed var(--ruled-line)" }}
            >
              <div className="flex-1 min-w-0">
                <div className="flex items-baseline gap-2">
                  <span
                    className="font-body font-bold"
                    style={{ color, fontSize: "16px" }}
                  >
                    {sign}{log.amount} {("unit" in item ? item.unit : "")}
                  </span>
                  <span
                    className="font-display text-base font-semibold"
                    style={{ color: "var(--ink-muted)" }}
                  >
                    {log.action}
                  </span>
                </div>
                <div
                  className="font-body text-xs"
                  style={{ color: "var(--ink-muted)" }}
                >
                  {shortDate(log.logged_at)}
                  {log.note && ` — ${log.note}`}
                </div>
              </div>
              <button
                onClick={() => {
                  setEditingLog(log);
                  setEditOpen(true);
                }}
                aria-label="edit entry"
                className="p-1 shrink-0"
                style={{ color: "var(--ink-muted)" }}
              >
                <PencilIcon width="16" height="16" />
              </button>
              <button
                onClick={() => handleDelete(log)}
                aria-label="delete entry"
                className="p-1 shrink-0"
                style={{ color: "var(--margin-red)" }}
              >
                <TrashIcon width="16" height="16" />
              </button>
            </div>
          );
        })}
      </div>

      <EditLogModal
        key={editingLog?.id || "none"}
        log={editingLog}
        open={editOpen}
        onClose={() => setEditOpen(false)}
        unit={"unit" in item ? item.unit : ""}
      />
    </>
  );
}

function EditLogModal({
  log,
  open,
  onClose,
  unit,
}: {
  log: ConsumptionLog | null;
  open: boolean;
  onClose: () => void;
  unit: string;
}) {
  const updateLog = useLabStore((s) => s.updateLog);
  // Initialize from log — key-based remount ensures fresh state per log
  const [amount, setAmount] = useState(log ? String(log.amount) : "");
  const [note, setNote] = useState(log?.note ?? "");
  const [date, setDate] = useState(log ? log.logged_at.slice(0, 10) : todayLocalDate());

  if (!log) return null;

  const submit = async () => {
    const amt = Number(amount);
    if (!Number.isFinite(amt) || amt <= 0) {
      toast.error("amount must be > 0");
      return;
    }
    try {
      await updateLog(log.id, {
        amount: amt,
        note: note.trim(),
        logged_at: dateToNoonISO(date || todayLocalDate()),
      });
      toast.success("entry updated");
      onClose();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "couldn't update entry");
    }
  };

  return (
    <Modal
      open={open}
      onClose={onClose}
      title={`edit ${log.action} entry`}
      footer={
        <>
          <CircledButton onClick={onClose}>cancel</CircledButton>
          <CircledButton onClick={submit}>save</CircledButton>
        </>
      }
    >
      <div className="flex flex-col gap-4">
        <RuledInput
          label={`amount (${unit})`}
          type="number"
          inputMode="decimal"
          value={amount}
          onChange={(e) => setAmount(e.target.value)}
          autoFocus
        />
        <RuledTextarea
          label="note"
          value={note}
          onChange={(e) => setNote(e.target.value)}
          placeholder="what was it used for?"
        />
        <RuledInput
          label="date"
          type="date"
          value={date}
          max={todayLocalDate()}
          onChange={(e) => setDate(e.target.value)}
        />
        <p className="font-body text-xs" style={{ color: "var(--ink-muted)" }}>
          changing the amount will automatically adjust the {log.item_type}'s quantity.
        </p>
      </div>
    </Modal>
  );
}
