"use client";

import { useState } from "react";
import { toast } from "sonner";
import { useLabStore } from "@/lib/store";
import type { Apparatus, ApparatusCategory, LogAction } from "@/lib/types";
import {
  percentRemaining,
  stockStatus,
  stockCaption,
  statusColor,
  todayLocalDate,
} from "@/lib/utils";
import { Modal } from "@/components/notebook/modal";
import {
  RuledInput,
  RuledTextarea,
  CircledButton,
  HandDrawnBar,
  Highlighter,
} from "@/components/notebook/primitives";
import { PencilIcon, TrashIcon, PlusIcon, MinusIcon } from "@/components/notebook/icons";

const CATEGORIES: ApparatusCategory[] = [
  "glassware",
  "balances",
  "heating",
  "measurement",
  "other",
];

/* ============ Shared footer ============ */

function ModalFooter({
  onClose,
  onSubmit,
  submitLabel,
  submitIcon,
  submitVariant = "default",
}: {
  onClose: () => void;
  onSubmit: () => void;
  submitLabel: string;
  submitIcon?: React.ReactNode;
  submitVariant?: "default" | "danger";
}) {
  return (
    <div
      className="px-5 py-3 flex items-center justify-end gap-2 flex-wrap sticky bottom-0"
      style={{
        borderTop: "1.5px dashed var(--ruled-line)",
        background: "var(--card-fill)",
      }}
    >
      <CircledButton onClick={onClose}>cancel</CircledButton>
      <CircledButton onClick={onSubmit} variant={submitVariant}>
        {submitIcon}
        {submitLabel}
      </CircledButton>
    </div>
  );
}

/* ============ Add Apparatus ============ */

function AddApparatusForm({ onClose }: { onClose: () => void }) {
  const addApparatus = useLabStore((s) => s.addApparatus);
  const [name, setName] = useState("");
  const [category, setCategory] = useState<ApparatusCategory>("glassware");
  const [quantity, setQuantity] = useState("");
  const [lowStockThreshold, setLowStockThreshold] = useState("");
  const [notes, setNotes] = useState("");

  const submit = async () => {
    if (!name.trim()) {
      toast.error("give it a name first");
      return;
    }
    const qty = Number(quantity);
    if (!Number.isFinite(qty) || qty < 0) {
      toast.error("quantity needs to be a number ≥ 0");
      return;
    }
    const threshold = Number(lowStockThreshold) || 0;
    try {
      await addApparatus({ name, category, quantity: qty, low_stock_threshold: threshold, notes });
      toast.success(`added ${name}`);
      onClose();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "couldn't add apparatus");
    }
  };

  return (
    <>
      <div className="flex flex-col gap-4">
        <RuledInput
          label="name"
          value={name}
          onChange={(e) => setName(e.target.value)}
          placeholder="250 mL Erlenmeyer flask"
          autoFocus
        />
        <div className="flex flex-col gap-1">
          <label
            className="font-display text-base font-semibold"
            style={{ color: "var(--ink-muted)" }}
          >
            category
          </label>
          <div className="flex flex-wrap gap-2">
            {CATEGORIES.map((cat) => (
              <button
                key={cat}
                onClick={() => setCategory(cat)}
                className="font-display text-lg font-semibold px-3 py-0.5"
                style={{
                  color: category === cat ? "var(--margin-red)" : "var(--ink-muted)",
                  textDecoration: category === cat ? "underline" : "none",
                  textUnderlineOffset: "3px",
                }}
              >
                {cat}
              </button>
            ))}
          </div>
        </div>
        <RuledInput
          label="starting quantity"
          type="number"
          inputMode="decimal"
          value={quantity}
          onChange={(e) => setQuantity(e.target.value)}
          placeholder="30"
        />
        <RuledInput
          label="low stock level (optional)"
          type="number"
          inputMode="decimal"
          value={lowStockThreshold}
          onChange={(e) => setLowStockThreshold(e.target.value)}
          placeholder="e.g. 5 — bar turns red at this level"
        />
        <RuledTextarea
          label="notes (optional)"
          value={notes}
          onChange={(e) => setNotes(e.target.value)}
          placeholder="cabinet B, top shelf"
        />
      </div>
      <ModalFooter
        onClose={onClose}
        onSubmit={submit}
        submitLabel="add"
        submitIcon={<PlusIcon width="16" height="16" />}
      />
    </>
  );
}

export function AddApparatusModal({
  open,
  onClose,
}: {
  open: boolean;
  onClose: () => void;
}) {
  return (
    <Modal open={open} onClose={onClose} title="new apparatus">
      {open ? <AddApparatusForm onClose={onClose} /> : null}
    </Modal>
  );
}

/* ============ Apparatus Detail ============ */

interface DetailProps {
  apparatus: Apparatus | null;
  open: boolean;
  onClose: () => void;
  onBreakage: () => void;
  onRestock: () => void;
  onEdit: () => void;
}

export function ApparatusDetailModal({
  apparatus,
  open,
  onClose,
  onBreakage,
  onRestock,
  onEdit,
}: DetailProps) {
  if (!apparatus) return null;
  const pct = percentRemaining(apparatus);
  const status = stockStatus(apparatus);

  return (
    <Modal
      open={open}
      onClose={onClose}
      title="apparatus"
      footer={
        <>
          <CircledButton onClick={onEdit}>
            <PencilIcon width="16" height="16" /> edit
          </CircledButton>
          <CircledButton onClick={onRestock}>
            <PlusIcon width="16" height="16" /> restock
          </CircledButton>
          <CircledButton onClick={onBreakage} variant="danger">
            <MinusIcon width="16" height="16" /> breakage
          </CircledButton>
        </>
      }
    >
      <div className="flex flex-col gap-3">
        <div>
          <h3
            className="font-accent font-bold leading-none"
            style={{ fontSize: "26px", color: "var(--ink)" }}
          >
            {apparatus.name}
          </h3>
          <p
            className="font-body text-base"
            style={{ color: "var(--ink-muted)" }}
          >
            {apparatus.category}
          </p>
        </div>

        <div className="flex items-baseline justify-between">
          <span className="font-body text-sm" style={{ color: "var(--ink-muted)" }}>
            on hand
          </span>
          <span
            className="font-body font-bold"
            style={{ fontSize: "22px", color: "var(--ink)" }}
          >
            {apparatus.quantity}
            {apparatus.low_stock_threshold > 0 && (
              <span style={{ color: "var(--ink-muted)", fontSize: "14px" }}>
                {" "}/ min {apparatus.low_stock_threshold}
              </span>
            )}
          </span>
        </div>

        <HandDrawnBar status={status} percent={pct} />
        <p
          className="font-display text-lg font-semibold"
          style={{ color: statusColor(status) }}
        >
          {stockCaption(apparatus)}
        </p>

        {apparatus.notes && (
          <div
            className="mt-2 pt-2"
            style={{ borderTop: "1.5px dashed var(--ruled-line)" }}
          >
            <p
              className="font-body text-xs mb-1"
              style={{ color: "var(--ink-muted)" }}
            >
              notes
            </p>
            <p className="font-body text-sm" style={{ color: "var(--ink)" }}>
              {apparatus.notes}
            </p>
          </div>
        )}
      </div>
    </Modal>
  );
}

/* ============ Restock / Breakage shared form ============ */

function ApparatusLogForm({
  apparatus,
  action,
  onClose,
}: {
  apparatus: Apparatus;
  action: LogAction;
  onClose: () => void;
}) {
  const logAction = useLabStore((s) => s.logAction);
  const [amount, setAmount] = useState("");
  const [note, setNote] = useState("");
  const [date, setDate] = useState(todayLocalDate());

  const isBreakage = action === "breakage";
  const today = todayLocalDate();
  const isBackdated = date !== today;

  const submit = async () => {
    const amt = Number(amount);
    if (!Number.isFinite(amt) || amt <= 0) {
      toast.error("amount must be > 0");
      return;
    }
    if (isBreakage && amt > apparatus.quantity) {
      toast.error(`only ${apparatus.quantity} on hand`);
      return;
    }
    try {
      const undo = await logAction({
        itemId: apparatus.id,
        itemType: "apparatus",
        action,
        amount: amt,
        note,
        date,
      });
      toast.success(
        `${isBreakage ? "logged breakage of" : "restocked"} ${amt} ${apparatus.name}`,
        {
          duration: 5000,
          action: {
            label: "undo",
            onClick: async () => {
              await undo();
              toast.info("undone");
            },
          },
        }
      );
      onClose();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "couldn't log action");
    }
  };

  return (
    <>
      <div
        className="flex flex-col gap-4"
        style={isBreakage ? { color: "var(--margin-red)" } : undefined}
      >
        <div>
          <p className="font-body text-sm" style={{ color: "var(--ink-muted)" }}>
            {apparatus.name} — {apparatus.quantity} on hand
          </p>
          {isBreakage && (
            <p
              className="font-display text-2xl font-bold mt-1"
              style={{ color: "var(--margin-red)" }}
            >
              −1 unit
            </p>
          )}
        </div>

        <RuledInput
          label={isBreakage ? "how many broken" : "how many added"}
          type="number"
          inputMode="decimal"
          value={amount}
          onChange={(e) => setAmount(e.target.value)}
          placeholder={isBreakage ? "1" : "5"}
          autoFocus
        />

        <RuledTextarea
          label={isBreakage ? "what happened" : "note (optional)"}
          value={note}
          onChange={(e) => setNote(e.target.value)}
          placeholder={
            isBreakage ? "dropped on floor during period 4 cleanup" : "new from supply room"
          }
          style={isBreakage ? { color: "var(--margin-red)" } : undefined}
        />

        <RuledInput
          label="date"
          type="date"
          value={date}
          max={today}
          onChange={(e) => setDate(e.target.value)}
        />
        {isBackdated && (
          <p
            className="font-display text-base font-semibold"
            style={{ color: "var(--margin-red)" }}
          >
            ⚠ backdated — this will appear as {date} in reports & activity
          </p>
        )}
      </div>
      <ModalFooter
        onClose={onClose}
        onSubmit={submit}
        submitLabel="log it"
        submitVariant={isBreakage ? "danger" : "default"}
      />
    </>
  );
}

export function ApparatusLogModal({
  apparatus,
  action,
  open,
  onClose,
}: {
  apparatus: Apparatus | null;
  action: LogAction;
  open: boolean;
  onClose: () => void;
}) {
  const title = action === "breakage" ? "breakage log" : "restock";
  return (
    <Modal open={open} onClose={onClose} title={title}>
      {open && apparatus ? (
        <ApparatusLogForm apparatus={apparatus} action={action} onClose={onClose} />
      ) : null}
    </Modal>
  );
}

/* ============ Edit Apparatus ============ */

function EditApparatusForm({
  apparatus,
  onClose,
}: {
  apparatus: Apparatus;
  onClose: () => void;
}) {
  const updateApparatus = useLabStore((s) => s.updateApparatus);
  const deleteApparatus = useLabStore((s) => s.deleteApparatus);
  const [name, setName] = useState(apparatus.name);
  const [category, setCategory] = useState<ApparatusCategory>(apparatus.category);
  const [lowStockThreshold, setLowStockThreshold] = useState(
    String(apparatus.low_stock_threshold || "")
  );
  const [exactQuantity, setExactQuantity] = useState("");
  const [correctionNote, setCorrectionNote] = useState("");
  const [showCorrection, setShowCorrection] = useState(false);
  const [notes, setNotes] = useState(apparatus.notes);

  const submit = async () => {
    if (!name.trim()) {
      toast.error("name can't be empty");
      return;
    }
    try {
      await updateApparatus(apparatus.id, {
        name: name.trim(),
        category,
        low_stock_threshold: Number(lowStockThreshold) || 0,
        notes: notes.trim(),
      });
      toast.success("updated");
      onClose();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "couldn't update");
    }
  };

  const applyCorrection = async () => {
    const newQty = Number(exactQuantity);
    if (!Number.isFinite(newQty) || newQty < 0) {
      toast.error("enter a valid quantity ≥ 0");
      return;
    }
    if (newQty === apparatus.quantity) {
      toast.error("new quantity is the same as current");
      return;
    }
    try {
      await updateApparatus(apparatus.id, { quantity: newQty });
      toast.success(`quantity corrected: ${apparatus.quantity} → ${newQty}`);
      onClose();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "couldn't correct quantity");
    }
  };

  const remove = async () => {
    try {
      await deleteApparatus(apparatus.id);
      toast.success(`removed ${apparatus.name}`);
      onClose();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "couldn't delete");
    }
  };

  return (
    <>
      <div className="flex flex-col gap-4">
        <RuledInput label="name" value={name} onChange={(e) => setName(e.target.value)} />
        <div className="flex flex-col gap-1">
          <label
            className="font-display text-base font-semibold"
            style={{ color: "var(--ink-muted)" }}
          >
            category
          </label>
          <div className="flex flex-wrap gap-2">
            {CATEGORIES.map((cat) => (
              <button
                key={cat}
                onClick={() => setCategory(cat)}
                className="font-display text-lg font-semibold px-3 py-0.5"
                style={{
                  color: category === cat ? "var(--margin-red)" : "var(--ink-muted)",
                  textDecoration: category === cat ? "underline" : "none",
                  textUnderlineOffset: "3px",
                }}
              >
                {cat}
              </button>
            ))}
          </div>
        </div>
        <RuledInput
          label="low stock level"
          type="number"
          inputMode="decimal"
          value={lowStockThreshold}
          onChange={(e) => setLowStockThreshold(e.target.value)}
          placeholder="0 = not set"
        />
        <RuledTextarea label="notes" value={notes} onChange={(e) => setNotes(e.target.value)} />

        {/* Quantity correction — for fixing wrong entries */}
        <div
          style={{
            marginTop: "8px",
            padding: "12px",
            border: "1.5px dashed var(--margin-red)",
            borderRadius: "4px 8px 3px 9px / 8px 3px 9px 2px",
            background: "color-mix(in srgb, var(--margin-red) 5%, var(--card-fill))",
          }}
        >
          <button
            type="button"
            onClick={() => setShowCorrection(!showCorrection)}
            className="font-display text-lg font-bold w-full text-left"
            style={{ color: "var(--margin-red)" }}
          >
            {showCorrection ? "▼" : "▶"} fix wrong quantity
          </button>
          {showCorrection && (
            <div className="mt-3 flex flex-col gap-3">
              <p className="font-body text-xs" style={{ color: "var(--ink-muted)" }}>
                current: <strong>{apparatus.quantity}</strong> — enter the correct amount if you made a data-entry error.
              </p>
              <RuledInput
                label="correct quantity"
                type="number"
                inputMode="decimal"
                value={exactQuantity}
                onChange={(e) => setExactQuantity(e.target.value)}
                placeholder={String(apparatus.quantity)}
              />
              <RuledTextarea
                label="why are you correcting it? (optional)"
                value={correctionNote}
                onChange={(e) => setCorrectionNote(e.target.value)}
                placeholder="e.g. miscounted during stocktake"
              />
              <button
                type="button"
                onClick={applyCorrection}
                className="font-display text-base font-bold"
                style={{
                  color: "white",
                  background: "var(--margin-red)",
                  border: "none",
                  padding: "8px 16px",
                  borderRadius: "999px",
                  cursor: "pointer",
                  alignSelf: "flex-start",
                }}
              >
                apply correction
              </button>
            </div>
          )}
        </div>
      </div>
      <div
        className="px-5 py-3 flex items-center justify-end gap-2 flex-wrap sticky bottom-0"
        style={{
          borderTop: "1.5px dashed var(--ruled-line)",
          background: "var(--card-fill)",
        }}
      >
        <button
          onClick={remove}
          className="font-display text-lg font-semibold mr-auto flex items-center gap-1"
          style={{ color: "var(--margin-red)", textDecoration: "underline", textUnderlineOffset: "3px" }}
        >
          <TrashIcon width="16" height="16" /> delete
        </button>
        <CircledButton onClick={onClose}>cancel</CircledButton>
        <CircledButton onClick={submit}>save</CircledButton>
      </div>
    </>
  );
}

export function EditApparatusModal({
  apparatus,
  open,
  onClose,
}: {
  apparatus: Apparatus | null;
  open: boolean;
  onClose: () => void;
}) {
  return (
    <Modal open={open} onClose={onClose} title="edit apparatus">
      {open && apparatus ? (
        <EditApparatusForm apparatus={apparatus} onClose={onClose} />
      ) : null}
    </Modal>
  );
}
