// Type definitions for Lab Wizard
// Matches the data model in the spec — designed so a Supabase swap
// later only touches the store implementation, not consumers.

export type ChemicalUnit = "mL" | "g" | "mg" | "L" | "kg" | "drops" | "pcs";

export interface Chemical {
  id: string;
  name: string;
  formula: string;
  unit: ChemicalUnit;
  quantity: number;
  initial_quantity: number;
  notes: string;
  qr_code: string; // uuid string
  created_at: string; // ISO
}

export type ApparatusCategory =
  | "glassware"
  | "balances"
  | "heating"
  | "measurement"
  | "other";

export interface Apparatus {
  id: string;
  name: string;
  category: ApparatusCategory;
  quantity: number;
  initial_quantity: number;
  notes: string;
  created_at: string;
}

export type ItemType = "chemical" | "apparatus";
export type LogAction = "consume" | "restock" | "breakage";

export interface ConsumptionLog {
  id: string;
  item_id: string;
  item_type: ItemType;
  action: LogAction;
  amount: number;
  note: string;
  logged_at: string; // ISO — backdatable, noon-local per spec
  created_at: string; // ISO
}

export interface AppUser {
  id: string;
  email: string;
  name: string;
}

export type TabKey =
  | "home"
  | "chemicals"
  | "apparatus"
  | "scan"
  | "reports";

export type StockStatus = "healthy" | "low" | "critical" | "empty";
