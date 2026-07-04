"use client";

// Lab Wizard data layer.
//
// Uses Supabase when NEXT_PUBLIC_SUPABASE_URL + NEXT_PUBLIC_SUPABASE_ANON_KEY
// are configured. Otherwise falls back to a localStorage-backed mock store.
//
// The public API (signIn, addChemical, logAction, etc.) is identical in both
// modes — consumers don't need to know which backend is active.

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
import { getSupabase, isSupabaseConfigured } from "./supabase";

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
  recentScans: string[];
  undoStack: UndoRecord[];
  loading: boolean;

  // auth
  signIn: (email: string, password: string) => Promise<void>;
  signUp: (email: string, password: string, name?: string) => Promise<void>;
  signOut: () => Promise<void>;
  restoreSession: () => Promise<void>;

  // data loading
  loadAll: () => Promise<void>;

  // chemicals
  addChemical: (input: {
    name: string;
    formula: string;
    unit: ChemicalUnit;
    quantity: number;
    notes?: string;
  }) => Promise<Chemical>;
  updateChemical: (id: string, patch: Partial<Chemical>) => Promise<void>;
  deleteChemical: (id: string) => Promise<void>;
  findChemicalByQR: (qr: string) => Chemical | undefined;

  // apparatus
  addApparatus: (input: {
    name: string;
    category: ApparatusCategory;
    quantity: number;
    notes?: string;
  }) => Promise<Apparatus>;
  updateApparatus: (id: string, patch: Partial<Apparatus>) => Promise<void>;
  deleteApparatus: (id: string) => Promise<void>;

  // logging
  logAction: (input: {
    itemId: string;
    itemType: ItemType;
    action: LogAction;
    amount: number;
    note?: string;
    date?: string;
  }) => Promise<() => Promise<void>>;

  // scanner
  pushRecentScan: (chemicalId: string) => void;

  // reports
  clearMonth: (monthKey: string) => Promise<void>;

  // dev
  resetAll: () => Promise<void>;
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
      loading: false,

      // ============ AUTH ============

      signIn: async (email, password) => {
        const supabase = getSupabase();
        if (supabase) {
          const { data, error } = await supabase.auth.signInWithPassword({
            email,
            password,
          });
          if (error) throw error;
          const u = data.user;
          if (u) {
            set({
              user: {
                id: u.id,
                email: u.email || email,
                name:
                  (u.user_metadata?.name as string) ||
                  email.split("@")[0].replace(/[._-]/g, " "),
              },
            });
            await get().loadAll();
          }
        } else {
          // Mock mode — any password works
          const displayName = email
            .split("@")[0]
            .replace(/[._-]/g, " ")
            .replace(/\b\w/g, (c) => c.toUpperCase());
          set({ user: { id: uid(), email, name: displayName } });
        }
      },

      signUp: async (email, password, name) => {
        const supabase = getSupabase();
        if (supabase) {
          const { data, error } = await supabase.auth.signUp({
            email,
            password,
            options: { data: name ? { name } : undefined },
          });
          if (error) throw error;
          const u = data.user;
          if (u) {
            set({
              user: {
                id: u.id,
                email: u.email || email,
                name: name || email.split("@")[0],
              },
            });
            await get().loadAll();
          }
        } else {
          // Mock mode
          set({
            user: {
              id: uid(),
              email,
              name: name || email.split("@")[0],
            },
          });
        }
      },

      signOut: async () => {
        const supabase = getSupabase();
        if (supabase) {
          await supabase.auth.signOut();
        }
        set({ user: null, chemicals: [], apparatus: [], logs: [], undoStack: [] });
      },

      restoreSession: async () => {
        const supabase = getSupabase();
        if (!supabase) return;
        const { data } = await supabase.auth.getSession();
        const u = data.session?.user;
        if (u) {
          set({
            user: {
              id: u.id,
              email: u.email || "",
              name:
                (u.user_metadata?.name as string) ||
                (u.email || "").split("@")[0].replace(/[._-]/g, " "),
            },
          });
          await get().loadAll();
        }
      },

      // ============ DATA LOADING ============

      loadAll: async () => {
        const supabase = getSupabase();
        if (!supabase || !get().user) return;
        set({ loading: true });
        try {
          const [chemRes, appRes, logRes] = await Promise.all([
            supabase.from("chemicals").select("*").order("created_at", { ascending: false }),
            supabase.from("apparatus").select("*").order("created_at", { ascending: false }),
            supabase.from("consumption_logs").select("*").order("logged_at", { ascending: false }),
          ]);

          set({
            chemicals: (chemRes.data || []) as Chemical[],
            apparatus: (appRes.data || []) as Apparatus[],
            logs: (logRes.data || []) as ConsumptionLog[],
            loading: false,
          });
        } catch {
          set({ loading: false });
        }
      },

      // ============ CHEMICALS ============

      addChemical: async ({ name, formula, unit, quantity, notes }) => {
        const supabase = getSupabase();
        const userId = get().user?.id;
        if (!userId) throw new Error("not signed in");

        const base = {
          name: name.trim(),
          formula: formula.trim(),
          unit,
          quantity,
          initial_quantity: quantity,
          notes: notes?.trim() ?? "",
          qr_code: uid(),
        };

        if (supabase && userId) {
          const { data, error } = await supabase
            .from("chemicals")
            .insert({ ...base, user_id: userId })
            .select()
            .single();
          if (error) throw error;
          const chem = data as Chemical;
          set((s) => ({ chemicals: [chem, ...s.chemicals] }));
          return chem;
        } else {
          const chem: Chemical = {
            id: uid(),
            ...base,
            created_at: new Date().toISOString(),
          };
          set((s) => ({ chemicals: [chem, ...s.chemicals] }));
          return chem;
        }
      },

      updateChemical: async (id, patch) => {
        const supabase = getSupabase();
        if (supabase) {
          const { error } = await supabase.from("chemicals").update(patch).eq("id", id);
          if (error) throw error;
        }
        set((s) => ({
          chemicals: s.chemicals.map((c) => (c.id === id ? { ...c, ...patch } : c)),
        }));
      },

      deleteChemical: async (id) => {
        const supabase = getSupabase();
        if (supabase) {
          await supabase.from("chemicals").delete().eq("id", id);
          await supabase.from("consumption_logs").delete().eq("item_id", id).eq("item_type", "chemical");
        }
        set((s) => ({
          chemicals: s.chemicals.filter((c) => c.id !== id),
          logs: s.logs.filter((l) => !(l.item_id === id && l.item_type === "chemical")),
        }));
      },

      findChemicalByQR: (qr) => get().chemicals.find((c) => c.qr_code === qr),

      // ============ APPARATUS ============

      addApparatus: async ({ name, category, quantity, notes }) => {
        const supabase = getSupabase();
        const userId = get().user?.id;
        if (!userId) throw new Error("not signed in");

        const base = {
          name: name.trim(),
          category,
          quantity,
          initial_quantity: quantity,
          notes: notes?.trim() ?? "",
        };

        if (supabase && userId) {
          const { data, error } = await supabase
            .from("apparatus")
            .insert({ ...base, user_id: userId })
            .select()
            .single();
          if (error) throw error;
          const app = data as Apparatus;
          set((s) => ({ apparatus: [app, ...s.apparatus] }));
          return app;
        } else {
          const app: Apparatus = {
            id: uid(),
            ...base,
            created_at: new Date().toISOString(),
          };
          set((s) => ({ apparatus: [app, ...s.apparatus] }));
          return app;
        }
      },

      updateApparatus: async (id, patch) => {
        const supabase = getSupabase();
        if (supabase) {
          const { error } = await supabase.from("apparatus").update(patch).eq("id", id);
          if (error) throw error;
        }
        set((s) => ({
          apparatus: s.apparatus.map((a) => (a.id === id ? { ...a, ...patch } : a)),
        }));
      },

      deleteApparatus: async (id) => {
        const supabase = getSupabase();
        if (supabase) {
          await supabase.from("apparatus").delete().eq("id", id);
          await supabase.from("consumption_logs").delete().eq("item_id", id).eq("item_type", "apparatus");
        }
        set((s) => ({
          apparatus: s.apparatus.filter((a) => a.id !== id),
          logs: s.logs.filter((l) => !(l.item_id === id && l.item_type === "apparatus")),
        }));
      },

      // ============ LOGGING ============

      logAction: async ({ itemId, itemType, action, amount, note, date }) => {
        const supabase = getSupabase();
        const isoDate = dateToNoonISO(date ?? todayLocalDate());
        const userId = get().user?.id;
        if (!userId) throw new Error("not signed in");

        const logBase = {
          item_id: itemId,
          item_type: itemType,
          action,
          amount,
          note: note?.trim() ?? "",
          logged_at: isoDate,
        };

        // Capture previous quantity for undo
        const state = get();
        let prevQuantity = 0;
        if (itemType === "chemical") {
          const item = state.chemicals.find((c) => c.id === itemId);
          if (!item) return async () => {};
          prevQuantity = item.quantity;
          let newQty = item.quantity;
          if (action === "consume") newQty = Math.max(0, newQty - amount);
          if (action === "restock") newQty = newQty + amount;
          await get().updateChemical(itemId, { quantity: newQty });
        } else {
          const item = state.apparatus.find((a) => a.id === itemId);
          if (!item) return async () => {};
          prevQuantity = item.quantity;
          let newQty = item.quantity;
          if (action === "breakage") newQty = Math.max(0, newQty - amount);
          if (action === "restock") newQty = newQty + amount;
          await get().updateApparatus(itemId, { quantity: newQty });
        }

        let logId: string;
        if (supabase && userId) {
          const { data, error } = await supabase
            .from("consumption_logs")
            .insert({ ...logBase, user_id: userId })
            .select()
            .single();
          if (error) throw error;
          logId = (data as ConsumptionLog).id;
        } else {
          logId = uid();
        }

        const log: ConsumptionLog = {
          id: logId,
          ...logBase,
          created_at: new Date().toISOString(),
        };
        set((s) => ({ logs: [log, ...s.logs] }));

        const undoRecord: UndoRecord = { logId, itemId, itemType, prevQuantity };
        set((s) => ({ undoStack: [undoRecord, ...s.undoStack].slice(0, 20) }));

        // Return an undo function
        return async () => {
          const cur = get();
          const record = cur.undoStack.find((r) => r.logId === logId);
          if (!record) return;
          if (record.itemType === "chemical") {
            await cur.updateChemical(record.itemId, { quantity: record.prevQuantity });
          } else {
            await cur.updateApparatus(record.itemId, { quantity: record.prevQuantity });
          }
          if (supabase) {
            await supabase.from("consumption_logs").delete().eq("id", logId);
          }
          set((s) => ({
            logs: s.logs.filter((l) => l.id !== logId),
            undoStack: s.undoStack.filter((r) => r.logId !== logId),
          }));
        };
      },

      // ============ SCANNER ============

      pushRecentScan: (chemicalId) =>
        set((s) => ({
          recentScans: [chemicalId, ...s.recentScans.filter((id) => id !== chemicalId)].slice(0, 8),
        })),

      // ============ REPORTS ============

      clearMonth: async (monthKey) => {
        const supabase = getSupabase();
        if (supabase) {
          const start = `${monthKey}-01T00:00:00`;
          const [y, m] = monthKey.split("-").map(Number);
          const end = new Date(y, m, 1).toISOString();
          await supabase
            .from("consumption_logs")
            .delete()
            .gte("logged_at", start)
            .lt("logged_at", end);
        }
        set((s) => ({
          logs: s.logs.filter((l) => l.logged_at.slice(0, 7) !== monthKey),
        }));
      },

      // ============ DEV ============

      resetAll: async () => {
        const supabase = getSupabase();
        const userId = get().user?.id;
        if (supabase && userId) {
          await supabase.from("consumption_logs").delete().eq("user_id", userId);
          await supabase.from("chemicals").delete().eq("user_id", userId);
          await supabase.from("apparatus").delete().eq("user_id", userId);
        }
        set({
          user: null,
          chemicals: [],
          apparatus: [],
          logs: [],
          recentScans: [],
          undoStack: [],
        });
      },
    }),
    {
      name: "lab-wizard-v2",
      storage: createJSONStorage(() => localStorage),
      // Only persist user + recentScans in Supabase mode; persist everything in mock mode
      partialize: (state) => {
        if (isSupabaseConfigured()) {
          return { user: state.user, recentScans: state.recentScans };
        }
        return {
          user: state.user,
          chemicals: state.chemicals,
          apparatus: state.apparatus,
          logs: state.logs,
          recentScans: state.recentScans,
        };
      },
    }
  )
);
