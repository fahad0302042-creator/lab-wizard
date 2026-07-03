"use client";

// Mock data layer for Lab Wizard.
//
// This is a Zustand store persisted to localStorage. The shape of the
// public API (load, addChemical, consume, etc.) is intentionally close
// to what a Supabase-backed implementation would look like — swapping
// later means replacing the bodies of these methods with supabase-js
// calls, not rewriting the consumers.

import { create } from "zustand";
import { persist, createJSONStorage } from "zustand/middleware";
import type {
  Chemical,
  Apparatus,
  ConsumptionLog,
  AppUser,
  ChemicalUnit,
  ApparatusCategory,
  ItemType,
  LogAction,
} from "./types";
import { uid, dateToNoonISO, todayLocalDate } from "./utils";

interface UndoRecord {
  logId: string;
  itemId: string;
  itemType: ItemType;
  prevQuantity: number;
}

interface LabState {
  user: AppUser | null;
  chemicals: Chemical[];
  apparatus: Apparatus[];
  logs: ConsumptionLog[];
  recentScans: string[]; // chemical ids, most-recent-first
  undoStack: UndoRecord[];

  // auth
  signIn: (email: string, name?: string) => void;
  signOut: () => void;

  // chemicals
  addChemical: (input: {
    name: string;
    formula: string;
    unit: ChemicalUnit;
    quantity: number;
    notes?: string;
  }) => Chemical;
  updateChemical: (id: string, patch: Partial<Chemical>) => void;
  deleteChemical: (id: string) => void;
  findChemicalByQR: (qr: string) => Chemical | undefined;

  // apparatus
  addApparatus: (input: {
    name: string;
    category: ApparatusCategory;
    quantity: number;
    notes?: string;
  }) => Apparatus;
  updateApparatus: (id: string, patch: Partial<Apparatus>) => void;
  deleteApparatus: (id: string) => void;

  // logging — returns a function to undo the action
  logAction: (input: {
    itemId: string;
    itemType: ItemType;
    action: LogAction;
    amount: number;
    note?: string;
    date?: string; // YYYY-MM-DD, defaults to today
  }) => () => void;

  // scanner helpers
  pushRecentScan: (chemicalId: string) => void;

  // reports
  clearMonth: (monthKey: string) => void;

  // dev
  resetAll: () => void;
}

export const useLabStore = create<LabState>()(
  persist(
    (set, get) => ({
      user: null,
      chemicals: [],
      apparatus: [],
      logs: [],
      recentScans: [],
      undoStack: [],

      signIn: (email, name) => {
        const displayName =
          name ||
          email
            .split("@")[0]
            .replace(/[._-]/g, " ")
            .replace(/\b\w/g, (c) => c.toUpperCase());
        set({
          user: {
            id: uid(),
            email,
            name: displayName,
          },
        });
      },

      signOut: () => set({ user: null }),

      addChemical: ({ name, formula, unit, quantity, notes }) => {
        const chem: Chemical = {
          id: uid(),
          name: name.trim(),
          formula: formula.trim(),
          unit,
          quantity,
          initial_quantity: quantity,
          notes: notes?.trim() ?? "",
          qr_code: uid(),
          created_at: new Date().toISOString(),
        };
        set((s) => ({ chemicals: [chem, ...s.chemicals] }));
        return chem;
      },

      updateChemical: (id, patch) =>
        set((s) => ({
          chemicals: s.chemicals.map((c) =>
            c.id === id ? { ...c, ...patch } : c
          ),
        })),

      deleteChemical: (id) =>
        set((s) => ({
          chemicals: s.chemicals.filter((c) => c.id !== id),
          logs: s.logs.filter((l) => !(l.item_id === id && l.item_type === "chemical")),
        })),

      findChemicalByQR: (qr) =>
        get().chemicals.find((c) => c.qr_code === qr),

      addApparatus: ({ name, category, quantity, notes }) => {
        const app: Apparatus = {
          id: uid(),
          name: name.trim(),
          category,
          quantity,
          initial_quantity: quantity,
          notes: notes?.trim() ?? "",
          created_at: new Date().toISOString(),
        };
        set((s) => ({ apparatus: [app, ...s.apparatus] }));
        return app;
      },

      updateApparatus: (id, patch) =>
        set((s) => ({
          apparatus: s.apparatus.map((a) =>
            a.id === id ? { ...a, ...patch } : a
          ),
        })),

      deleteApparatus: (id) =>
        set((s) => ({
          apparatus: s.apparatus.filter((a) => a.id !== id),
          logs: s.logs.filter((l) => !(l.item_id === id && l.item_type === "apparatus")),
        })),

      logAction: ({ itemId, itemType, action, amount, note, date }) => {
        const isoDate = dateToNoonISO(date ?? todayLocalDate());
        const log: ConsumptionLog = {
          id: uid(),
          item_id: itemId,
          item_type: itemType,
          action,
          amount,
          note: note?.trim() ?? "",
          logged_at: isoDate,
          created_at: new Date().toISOString(),
        };

        // Apply the quantity delta and capture the previous value for undo.
        const state = get();
        let prevQuantity = 0;
        if (itemType === "chemical") {
          const item = state.chemicals.find((c) => c.id === itemId);
          if (!item) return () => {};
          prevQuantity = item.quantity;
          let newQty = item.quantity;
          if (action === "consume") newQty = Math.max(0, newQty - amount);
          if (action === "restock") newQty = newQty + amount;
          get().updateChemical(itemId, { quantity: newQty });
        } else {
          const item = state.apparatus.find((a) => a.id === itemId);
          if (!item) return () => {};
          prevQuantity = item.quantity;
          let newQty = item.quantity;
          if (action === "breakage") newQty = Math.max(0, newQty - amount);
          if (action === "restock") newQty = newQty + amount;
          get().updateApparatus(itemId, { quantity: newQty });
        }

        set((s) => ({ logs: [log, ...s.logs] }));

        const undoRecord: UndoRecord = {
          logId: log.id,
          itemId,
          itemType,
          prevQuantity,
        };
        set((s) => ({ undoStack: [undoRecord, ...s.undoStack].slice(0, 20) }));

        // Return an undo function — the caller wires it to a sonner toast.
        return () => {
          const cur = get();
          const record = cur.undoStack.find((r) => r.logId === log.id);
          if (!record) return;
          if (record.itemType === "chemical") {
            cur.updateChemical(record.itemId, { quantity: record.prevQuantity });
          } else {
            cur.updateApparatus(record.itemId, { quantity: record.prevQuantity });
          }
          set((s) => ({
            logs: s.logs.filter((l) => l.id !== log.id),
            undoStack: s.undoStack.filter((r) => r.logId !== log.id),
          }));
        };
      },

      pushRecentScan: (chemicalId) =>
        set((s) => ({
          recentScans: [chemicalId, ...s.recentScans.filter((id) => id !== chemicalId)].slice(0, 8),
        })),

      clearMonth: (monthKey) =>
        set((s) => ({
          logs: s.logs.filter((l) => l.logged_at.slice(0, 7) !== monthKey),
        })),

      resetAll: () =>
        set({
          user: null,
          chemicals: [],
          apparatus: [],
          logs: [],
          recentScans: [],
          undoStack: [],
        }),
    }),
    {
      name: "lab-wizard-v1",
      storage: createJSONStorage(() => localStorage),
    }
  )
);
