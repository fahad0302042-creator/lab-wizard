// Helpers shared across the app.

import type { Chemical, Apparatus, StockStatus, ConsumptionLog, ItemType, LogAction } from "./types";

/** Convert a YYYY-MM-DD date into a noon-local ISO timestamp (avoids TZ edge cases). */
export function dateToNoonISO(date: string): string {
  return new Date(`${date}T12:00:00`).toISOString();
}

/** Today's date as YYYY-MM-DD in the user's local timezone. */
export function todayLocalDate(): string {
  const d = new Date();
  const tzOffset = d.getTimezoneOffset() * 60000;
  return new Date(d.getTime() - tzOffset).toISOString().slice(0, 10);
}

/** Percentage remaining for a chemical or apparatus item. */
export function percentRemaining(item: Chemical | Apparatus): number {
  if (item.initial_quantity <= 0) return 0;
  const pct = (item.quantity / item.initial_quantity) * 100;
  return Math.max(0, Math.min(100, Math.round(pct)));
}

/** Stock status thresholds: <20% critical, <50% low, otherwise healthy. Empty = 0. */
export function stockStatus(item: Chemical | Apparatus): StockStatus {
  const pct = percentRemaining(item);
  if (pct === 0) return "empty";
  if (pct < 20) return "critical";
  if (pct < 50) return "low";
  return "healthy";
}

/** Handwritten tone caption to go under the hand-drawn bar. */
export function stockCaption(item: Chemical | Apparatus): string {
  const pct = percentRemaining(item);
  const status = stockStatus(item);
  if (status === "empty") return "0% — (empty!)";
  if (status === "critical") return `${pct}% — order more!`;
  if (status === "low") return `${pct}% — getting low`;
  if (pct >= 85) return `${pct}% full — plenty ✓`;
  return `${pct}% full`;
}

/** Map a stock status to its tailwind color class. */
export function statusColor(status: StockStatus): string {
  switch (status) {
    case "healthy":
      return "text-[var(--stock-healthy)]";
    case "low":
      return "text-[var(--stock-low)]";
    case "critical":
    case "empty":
      return "text-[var(--stock-critical)]";
  }
}

/** Map a stock status to the hatched fill class. */
export function statusHatch(status: StockStatus): string {
  switch (status) {
    case "healthy":
      return "hatch-healthy";
    case "low":
      return "hatch-low";
    case "critical":
    case "empty":
      return "hatch-critical";
  }
}

/** Format an ISO timestamp as a relative "2 hours ago" style string. */
export function relativeTime(iso: string): string {
  const then = new Date(iso).getTime();
  const now = Date.now();
  const diff = Math.max(0, now - then);
  const min = Math.floor(diff / 60000);
  if (min < 1) return "just now";
  if (min < 60) return `${min} min ago`;
  const hr = Math.floor(min / 60);
  if (hr < 24) return `${hr} hour${hr > 1 ? "s" : ""} ago`;
  const day = Math.floor(hr / 24);
  if (day < 7) return `${day} day${day > 1 ? "s" : ""} ago`;
  const wk = Math.floor(day / 7);
  return `${wk} week${wk > 1 ? "s" : ""} ago`;
}

/** Format an ISO timestamp as a short date like "Jul 3". */
export function shortDate(iso: string): string {
  return new Date(iso).toLocaleDateString("en-US", {
    month: "short",
    day: "numeric",
  });
}

/** Full date line for dashboard header: "Thursday, July 3". */
export function fullDateLine(d = new Date()): string {
  return d.toLocaleDateString("en-US", {
    weekday: "long",
    month: "long",
    day: "numeric",
  });
}

/** Get the YYYY-MM string key for a date (for report grouping). */
export function monthKey(iso: string): string {
  return iso.slice(0, 7);
}

/** Human-readable month label from a YYYY-MM key: "July 2025". */
export function monthLabel(key: string): string {
  const [y, m] = key.split("-").map(Number);
  return new Date(y, m - 1, 1).toLocaleDateString("en-US", {
    month: "long",
    year: "numeric",
  });
}

/** List of last 12 YYYY-MM month keys, newest first. */
export function recentMonthKeys(): string[] {
  const keys: string[] = [];
  const now = new Date();
  for (let i = 0; i < 12; i++) {
    const d = new Date(now.getFullYear(), now.getMonth() - i, 1);
    keys.push(`${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}`);
  }
  return keys;
}

/** Generate a UUID-ish string (good enough for mock; real uuid used for QR). */
export function uid(): string {
  if (typeof crypto !== "undefined" && crypto.randomUUID) {
    return crypto.randomUUID();
  }
  return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0;
    const v = c === "x" ? r : (r & 0x3) | 0x8;
    return v.toString(16);
  });
}

/** Short label for a log action. */
export function actionLabel(action: LogAction): string {
  switch (action) {
    case "consume":
      return "used";
    case "restock":
      return "restocked";
    case "breakage":
      return "broke";
  }
}

/** Find the display name for an item referenced in a log. */
export function itemLabel(
  log: ConsumptionLog,
  chemicals: Chemical[],
  apparatus: Apparatus[]
): string {
  const list = log.item_type === "chemical" ? chemicals : apparatus;
  const found = list.find((i) => i.id === log.item_id);
  return found ? found.name : "(removed item)";
}

/** Friendly greeting based on the hour. */
export function greeting(d = new Date()): string {
  const h = d.getHours();
  if (h < 12) return "good morning";
  if (h < 17) return "good afternoon";
  if (h < 21) return "good evening";
  return "working late";
}

/** Last 7 day keys (YYYY-MM-DD) oldest first, plus short labels. */
export function last7Days(): { key: string; label: string; date: Date }[] {
  const out: { key: string; label: string; date: Date }[] = [];
  for (let i = 6; i >= 0; i--) {
    const d = new Date();
    d.setHours(0, 0, 0, 0);
    d.setDate(d.getDate() - i);
    out.push({
      key: d.toISOString().slice(0, 10),
      label: d.toLocaleDateString("en-US", { weekday: "narrow" }),
      date: d,
    });
  }
  return out;
}

/** Determine if a log falls on a given YYYY-MM-DD local date key. */
export function logOnDay(log: ConsumptionLog, dayKey: string): boolean {
  // logged_at is stored as noon-local ISO — its UTC slice maps cleanly back.
  const d = new Date(log.logged_at);
  const tzOffset = d.getTimezoneOffset() * 60000;
  const local = new Date(d.getTime() - tzOffset);
  return local.toISOString().slice(0, 10) === dayKey;
}

/** Type guard — does this log apply to chemicals vs apparatus? */
export function isChemicalLog(log: ConsumptionLog): log is ConsumptionLog & { item_type: "chemical" } {
  return log.item_type === "chemical";
}

/** Build the "used X of Y" sentence for an activity feed entry. */
export function activitySentence(
  log: ConsumptionLog,
  chemicals: Chemical[],
  apparatus: Apparatus[]
): string {
  const name = itemLabel(log, chemicals, apparatus);
  const verb = actionLabel(log.action);
  const list = log.item_type === "chemical" ? chemicals : apparatus;
  const item = list.find((i) => i.id === log.item_id);
  const unit = item && "unit" in item ? ` ${item.unit}` : "";
  return `${verb} ${log.amount}${unit} ${name}`;
}
