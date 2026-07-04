"use client";

import { useState } from "react";
import { QRCodeSVG } from "qrcode.react";
import { toast } from "sonner";
import { useLabStore } from "@/lib/store";
import type { Chemical, ChemicalUnit, LogAction } from "@/lib/types";
import { todayLocalDate } from "@/lib/utils";
import {
  percentRemaining,
  stockStatus,
  stockCaption,
  statusColor,
} from "@/lib/utils";
import { Modal } from "@/components/notebook/modal";
import {
  RuledInput,
  RuledTextarea,
  CircledButton,
  HandDrawnBar,
  Highlighter,
} from "@/components/notebook/primitives";
import { QrIcon, PencilIcon, TrashIcon, PlusIcon, MinusIcon } from "@/components/notebook/icons";

const UNITS: ChemicalUnit[] = ["mL", "g", "mg", "L", "kg", "drops", "pcs"];

/* ============ Add Chemical ============ */

function AddChemicalForm({ onClose }: { onClose: () => void }) {
  const addChemical = useLabStore((s) => s.addChemical);
  const [name, setName] = useState("");
  const [formula, setFormula] = useState("");
  const [unit, setUnit] = useState<ChemicalUnit>("mL");
  const [quantity, setQuantity] = useState("");
  const [notes, setNotes] = useState("");

  const submit = () => {
    if (!name.trim()) {
      toast.error("give it a name first");
      return;
    }
    const qty = Number(quantity);
    if (!Number.isFinite(qty) || qty < 0) {
      toast.error("quantity needs to be a number ≥ 0");
      return;
    }
    addChemical({ name, formula, unit, quantity: qty, notes });
    toast.success(`added ${name} to the shelf`);
    onClose();
  };

  return (
    <>
      <div className="flex flex-col gap-4">
        <RuledInput
          label="name"
          value={name}
          onChange={(e) => setName(e.target.value)}
          placeholder="Hydrochloric acid"
          autoFocus
        />
        <RuledInput
          label="formula"
          value={formula}
          onChange={(e) => setFormula(e.target.value)}
          placeholder="HCl"
        />
        <div className="flex flex-col gap-1">
          <label
            className="font-display text-base font-semibold"
            style={{ color: "var(--ink-muted)" }}
          >
            unit
          </label>
          <div className="flex flex-wrap gap-2">
            {UNITS.map((u) => (
              <button
                key={u}
                onClick={() => setUnit(u)}
                className="font-display text-lg font-semibold px-3 py-0.5"
                style={{
                  color: unit === u ? "var(--margin-red)" : "var(--ink-muted)",
                  textDecoration: unit === u ? "underline" : "none",
                  textUnderlineOffset: "3px",
                }}
              >
                {u}
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
          placeholder="500"
        />
        <RuledTextarea
          label="notes (optional)"
          value={notes}
          onChange={(e) => setNotes(e.target.value)}
          placeholder="stored in acid cabinet"
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

export function AddChemicalModal({
  open,
  onClose,
}: {
  open: boolean;
  onClose: () => void;
}) {
  return (
    <Modal open={open} onClose={onClose} title="new reagent">
      {open ? <AddChemicalForm onClose={onClose} /> : null}
    </Modal>
  );
}

/* ============ Chemical Detail ============ */

interface DetailProps {
  chemical: Chemical | null;
  open: boolean;
  onClose: () => void;
  onConsume: () => void;
  onRestock: () => void;
  onEdit: () => void;
  onShowQR: () => void;
}

export function ChemicalDetailModal({
  chemical,
  open,
  onClose,
  onConsume,
  onRestock,
  onEdit,
  onShowQR,
}: DetailProps) {
  if (!chemical) return null;
  const pct = percentRemaining(chemical);
  const status = stockStatus(chemical);

  return (
    <Modal
      open={open}
      onClose={onClose}
      title="reagent"
      size="md"
      footer={
        <>
          <CircledButton onClick={onEdit}>
            <PencilIcon width="16" height="16" /> edit
          </CircledButton>
          <CircledButton onClick={onRestock}>
            <PlusIcon width="16" height="16" /> restock
          </CircledButton>
          <CircledButton onClick={onConsume} variant="danger">
            <MinusIcon width="16" height="16" /> consume
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
            {chemical.name}
          </h3>
          {chemical.formula && (
            <p
              className="font-body text-lg"
              style={{ color: "var(--ink-muted)" }}
            >
              {chemical.formula}
            </p>
          )}
        </div>

        <div className="flex items-baseline justify-between">
          <span className="font-body text-sm" style={{ color: "var(--ink-muted)" }}>
            on hand
          </span>
          <span
            className="font-body font-bold"
            style={{ fontSize: "22px", color: "var(--ink)" }}
          >
            {chemical.quantity} {chemical.unit}
            <span style={{ color: "var(--ink-muted)", fontSize: "14px" }}>
              {" "}/ {chemical.initial_quantity} {chemical.unit}
            </span>
          </span>
        </div>

        <HandDrawnBar status={status} percent={pct} />
        <p
          className="font-display text-lg font-semibold"
          style={{ color: statusColor(status) }}
        >
          {stockCaption(chemical)}
        </p>

        {chemical.notes && (
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
              {chemical.notes}
            </p>
          </div>
        )}

        <button
          onClick={onShowQR}
          className="self-start mt-1 font-body text-sm flex items-center gap-1 underline"
          style={{ color: "var(--ink-muted)", textUnderlineOffset: "3px" }}
        >
          <QrIcon width="16" height="16" /> view QR code
        </button>
      </div>
    </Modal>
  );
}

/* ============ Consume / Restock shared form ============ */

function ChemicalLogForm({
  chemical,
  action,
  onClose,
}: {
  chemical: Chemical;
  action: LogAction;
  onClose: () => void;
}) {
  const logAction = useLabStore((s) => s.logAction);
  const [amount, setAmount] = useState("");
  const [note, setNote] = useState("");
  const [date, setDate] = useState(todayLocalDate());

  const isConsume = action === "consume";
  const verb = isConsume ? "consume" : "restock";
  const verbPast = isConsume ? "used" : "restocked";
  const today = todayLocalDate();
  const isBackdated = date !== today;

  const submit = () => {
    const amt = Number(amount);
    if (!Number.isFinite(amt) || amt <= 0) {
      toast.error("amount must be > 0");
      return;
    }
    if (isConsume && amt > chemical.quantity) {
      toast.error(`only ${chemical.quantity} ${chemical.unit} on hand`);
      return;
    }
    const undo = logAction({
      itemId: chemical.id,
      itemType: "chemical",
      action,
      amount: amt,
      note,
      date,
    });
    toast.success(`${verbPast} ${amt} ${chemical.unit} of ${chemical.name}`, {
      duration: 5000,
      action: {
        label: "undo",
        onClick: () => {
          undo();
          toast.info("undone — quantity restored");
        },
      },
    });
    onClose();
  };

  return (
    <>
      <div className="flex flex-col gap-4">
        <div>
          <p className="font-body text-sm" style={{ color: "var(--ink-muted)" }}>
            {chemical.name} — {chemical.quantity} {chemical.unit} on hand
          </p>
        </div>

        <RuledInput
          label={`amount to ${verb} (${chemical.unit})`}
          type="number"
          inputMode="decimal"
          value={amount}
          onChange={(e) => setAmount(e.target.value)}
          placeholder="10"
          autoFocus
        />

        <RuledTextarea
          label="note (optional)"
          value={note}
          onChange={(e) => setNote(e.target.value)}
          placeholder={isConsume ? "titration lab, period 3" : "new bottle from supplier"}
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
        submitLabel={`${verbPast} it`}
        submitVariant={isConsume ? "danger" : "default"}
      />
    </>
  );
}

interface LogFormProps {
  chemical: Chemical | null;
  action: LogAction;
  open: boolean;
  onClose: () => void;
}

export function ChemicalLogModal({ chemical, action, open, onClose }: LogFormProps) {
  const title = action === "consume" ? "consume" : "restock";
  return (
    <Modal open={open} onClose={onClose} title={title}>
      {open && chemical ? (
        <ChemicalLogForm chemical={chemical} action={action} onClose={onClose} />
      ) : null}
    </Modal>
  );
}

/* ============ Edit Chemical ============ */

function EditChemicalForm({
  chemical,
  onClose,
}: {
  chemical: Chemical;
  onClose: () => void;
}) {
  const updateChemical = useLabStore((s) => s.updateChemical);
  const deleteChemical = useLabStore((s) => s.deleteChemical);
  const [name, setName] = useState(chemical.name);
  const [formula, setFormula] = useState(chemical.formula);
  const [unit, setUnit] = useState<ChemicalUnit>(chemical.unit);
  const [notes, setNotes] = useState(chemical.notes);

  const submit = () => {
    if (!name.trim()) {
      toast.error("name can't be empty");
      return;
    }
    updateChemical(chemical.id, {
      name: name.trim(),
      formula: formula.trim(),
      unit,
      notes: notes.trim(),
    });
    toast.success("updated");
    onClose();
  };

  const remove = () => {
    deleteChemical(chemical.id);
    toast.success(`removed ${chemical.name}`);
    onClose();
  };

  return (
    <>
      <div className="flex flex-col gap-4">
        <RuledInput label="name" value={name} onChange={(e) => setName(e.target.value)} />
        <RuledInput label="formula" value={formula} onChange={(e) => setFormula(e.target.value)} />
        <div className="flex flex-col gap-1">
          <label
            className="font-display text-base font-semibold"
            style={{ color: "var(--ink-muted)" }}
          >
            unit
          </label>
          <div className="flex flex-wrap gap-2">
            {UNITS.map((u) => (
              <button
                key={u}
                onClick={() => setUnit(u)}
                className="font-display text-lg font-semibold px-3 py-0.5"
                style={{
                  color: unit === u ? "var(--margin-red)" : "var(--ink-muted)",
                  textDecoration: unit === u ? "underline" : "none",
                  textUnderlineOffset: "3px",
                }}
              >
                {u}
              </button>
            ))}
          </div>
        </div>
        <RuledTextarea label="notes" value={notes} onChange={(e) => setNotes(e.target.value)} />
        <p className="font-body text-xs" style={{ color: "var(--ink-muted)" }}>
          quantity is changed via consume / restock, not here. edit initial_quantity by deleting & re-adding.
        </p>
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

export function EditChemicalModal({
  chemical,
  open,
  onClose,
}: {
  chemical: Chemical | null;
  open: boolean;
  onClose: () => void;
}) {
  return (
    <Modal open={open} onClose={onClose} title="edit reagent">
      {open && chemical ? (
        <EditChemicalForm chemical={chemical} onClose={onClose} />
      ) : null}
    </Modal>
  );
}

/* ============ QR View ============ */

export function ChemicalQRModal({
  chemical,
  open,
  onClose,
}: {
  chemical: Chemical | null;
  open: boolean;
  onClose: () => void;
}) {
  if (!chemical) return null;
  return (
    <Modal
      open={open}
      onClose={onClose}
      title="QR code"
      footer={<CircledButton onClick={onClose}>done</CircledButton>}
    >
      <div className="flex flex-col items-center gap-3 py-2">
        <div
          className="p-4"
          style={{ background: "white", border: "1.5px solid var(--border)" }}
        >
          <QRCodeSVG value={`labwizard:chemical:${chemical.qr_code}`} size={180} level="M" />
        </div>
        <div className="text-center">
          <p
            className="font-accent font-bold"
            style={{ fontSize: "20px", color: "var(--ink)" }}
          >
            {chemical.name}
          </p>
          {chemical.formula && (
            <p className="font-body text-sm" style={{ color: "var(--ink-muted)" }}>
              {chemical.formula}
            </p>
          )}
          <p
            className="font-body text-xs mt-2 break-all"
            style={{ color: "var(--ink-muted)" }}
          >
            {chemical.qr_code}
          </p>
        </div>
        <p
          className="font-body text-xs text-center mt-1"
          style={{ color: "var(--ink-muted)" }}
        >
          print this on a label and stick it on the bottle — scan from the Scan tab to log quickly.
        </p>
      </div>
    </Modal>
  );
}

/* ============ Shared modal footer (for the form components) ============ */

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
