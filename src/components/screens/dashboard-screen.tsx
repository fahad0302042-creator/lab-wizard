"use client";

import { useMemo, useState } from "react";
import { motion } from "framer-motion";
import { useLabStore } from "@/lib/store";
import {
  fullDateLine,
  greeting,
  percentRemaining,
  stockStatus,
  statusHatch,
  relativeTime,
  activitySentence,
  last7Days,
  logOnDay,
  shortDate,
} from "@/lib/utils";
import {
  NotebookCard,
  SectionTitle,
  HandDrawnBar,
  ActivityEntry,
  CircledButton,
} from "@/components/notebook/primitives";
import {
  FlaskIcon,
  BeakerIcon,
  PlusIcon,
  ScanIcon,
  SearchIcon,
  ArrowRightIcon,
} from "@/components/notebook/icons";
import type { TabKey } from "@/lib/types";

interface DashboardProps {
  onNavigate: (tab: TabKey) => void;
  onSearch: (q: string) => void;
  onQuickAdd: (kind: "chemical" | "apparatus") => void;
  onScan: () => void;
}

export function DashboardScreen({
  onNavigate,
  onSearch,
  onQuickAdd,
  onScan,
}: DashboardProps) {
  const user = useLabStore((s) => s.user);
  const chemicals = useLabStore((s) => s.chemicals);
  const apparatus = useLabStore((s) => s.apparatus);
  const logs = useLabStore((s) => s.logs);
  const [q, setQ] = useState("");

  const today = new Date();

  const lowStock = useMemo(() => {
    const chems = chemicals
      .filter((c) => stockStatus(c) === "low" || stockStatus(c) === "critical")
      .map((c) => ({ kind: "chemical" as const, name: c.name, pct: percentRemaining(c), status: stockStatus(c) }));
    const apps = apparatus
      .filter((a) => stockStatus(a) === "low" || stockStatus(a) === "critical")
      .map((a) => ({ kind: "apparatus" as const, name: a.name, pct: percentRemaining(a), status: stockStatus(a) }));
    return [...chems, ...apps];
  }, [chemicals, apparatus]);

  const week = useMemo(() => {
    const days = last7Days();
    return days.map((d) => {
      const dayLogs = logs.filter((l) => logOnDay(l, d.key));
      const used = dayLogs
        .filter((l) => l.action === "consume" || l.action === "breakage")
        .reduce((sum, l) => sum + l.amount, 0);
      const added = dayLogs
        .filter((l) => l.action === "restock")
        .reduce((sum, l) => sum + l.amount, 0);
      return { ...d, used, added };
    });
  }, [logs]);

  const maxBar = Math.max(1, ...week.map((w) => Math.max(w.used, w.added)));

  const consumedThisWeek = week.reduce((s, d) => s + d.used, 0);

  const recentLogs = useMemo(
    () =>
      [...logs]
        .sort((a, b) => new Date(b.logged_at).getTime() - new Date(a.logged_at).getTime())
        .slice(0, 8),
    [logs]
  );

  const submitSearch = (e: React.FormEvent) => {
    e.preventDefault();
    onSearch(q);
  };

  return (
    <div className="pb-24">
      {/* Header */}
      <div className="mb-5">
        <p
          className="font-body text-sm"
          style={{ color: "var(--ink-muted)" }}
        >
          {fullDateLine(today)}
        </p>
        <h1
          className="font-display font-bold leading-none mt-1"
          style={{ fontSize: "38px", transform: "rotate(-1.5deg)", color: "var(--ink)" }}
        >
          {greeting(today)}, {user?.name?.split(" ")[0] ?? "friend"}
        </h1>
      </div>

      {/* Search */}
      <form onSubmit={submitSearch} className="mb-5">
        <div className="flex items-center gap-2 border-b-2 pb-1" style={{ borderColor: "var(--ruled-line)" }}>
          <SearchIcon width="18" height="18" style={{ color: "var(--ink-muted)" }} />
          <input
            value={q}
            onChange={(e) => setQ(e.target.value)}
            placeholder="search chemicals, apparatus…"
            className="flex-1 bg-transparent border-none outline-none font-body text-base"
            style={{ color: "var(--ink)" }}
          />
          {q && (
            <button
              type="submit"
              className="font-display text-base font-semibold"
              style={{ color: "var(--margin-red)" }}
            >
              go
            </button>
          )}
        </div>
      </form>

      {/* Low-stock margin-note callout */}
      {lowStock.length > 0 && (
        <motion.div
          initial={{ opacity: 0, x: -8 }}
          animate={{ opacity: 1, x: 0 }}
          className="mb-5 flex items-start gap-2"
        >
          <div
            className="font-display text-lg font-bold leading-tight"
            style={{ color: "var(--margin-red)" }}
          >
            {lowStock.length} {lowStock.length === 1 ? "item needs" : "items need"} restocking!
          </div>
          <ArrowRightIcon
            width="20"
            height="20"
            style={{ color: "var(--margin-red)", marginTop: "4px" }}
          />
        </motion.div>
      )}

      {/* KPI cards (2x2 on mobile) */}
      <div className="grid grid-cols-2 gap-4 mb-6">
        <NotebookCard tape="yellow" tilt={-0.6} className="flex flex-col gap-1">
          <div style={{ color: "var(--ink-muted)" }}>
            <FlaskIcon width="22" height="22" />
          </div>
          <div
            className="font-body font-bold"
            style={{ fontSize: "32px", lineHeight: 1, color: "var(--ink)" }}
          >
            {chemicals.length}
          </div>
          <div className="font-body text-sm" style={{ color: "var(--ink-muted)" }}>
            chemicals
          </div>
        </NotebookCard>

        <NotebookCard tape="blue" tilt={0.7} className="flex flex-col gap-1">
          <div style={{ color: "var(--ink-muted)" }}>
            <BeakerIcon width="22" height="22" />
          </div>
          <div
            className="font-body font-bold"
            style={{ fontSize: "32px", lineHeight: 1, color: "var(--ink)" }}
          >
            {apparatus.length}
          </div>
          <div className="font-body text-sm" style={{ color: "var(--ink-muted)" }}>
            apparatus
          </div>
        </NotebookCard>

        <NotebookCard
          tape={lowStock.length > 0 ? "pink" : "none"}
          tilt={0.5}
          className="flex flex-col gap-1"
        >
          <div style={{ color: "var(--stock-low)" }}>
            <PlusIcon width="22" height="22" style={{ transform: "rotate(45deg)" }} />
          </div>
          <div
            className="font-body font-bold"
            style={{ fontSize: "32px", lineHeight: 1, color: "var(--margin-red)" }}
          >
            {lowStock.length}
          </div>
          <div className="font-body text-sm" style={{ color: "var(--ink-muted)" }}>
            low stock
          </div>
        </NotebookCard>

        <NotebookCard tape="green" tilt={-0.4} className="flex flex-col gap-1">
          <div style={{ color: "var(--stock-healthy)" }}>
            <FlaskIcon width="22" height="22" />
          </div>
          <div
            className="font-body font-bold"
            style={{ fontSize: "32px", lineHeight: 1, color: "var(--ink)" }}
          >
            {consumedThisWeek}
          </div>
          <div className="font-body text-sm" style={{ color: "var(--ink-muted)" }}>
            used this week
          </div>
        </NotebookCard>
      </div>

      {/* 7-day activity chart */}
      <div className="mb-6">
        <SectionTitle>7-day activity</SectionTitle>
        <NotebookCard className="mt-3" tilt={0}>
          <div className="flex items-end justify-between gap-2 h-32 mb-2">
            {week.map((d, i) => (
              <div key={d.key} className="flex-1 flex flex-col items-center gap-1 h-full justify-end">
                <div className="flex items-end gap-0.5 h-full w-full justify-center">
                  {d.added > 0 && (
                    <div
                      className={statusHatch("healthy")}
                      style={{
                        width: "8px",
                        height: `${(d.added / maxBar) * 100}%`,
                        border: "1px solid var(--stock-healthy)",
                        borderRadius: "2px 4px 1px 5px / 4px 1px 5px 2px",
                      }}
                      title={`added ${d.added}`}
                    />
                  )}
                  {d.used > 0 && (
                    <div
                      className={statusHatch("low")}
                      style={{
                        width: "8px",
                        height: `${(d.used / maxBar) * 100}%`,
                        border: "1px solid var(--stock-low)",
                        borderRadius: "2px 4px 1px 5px / 4px 1px 5px 2px",
                      }}
                      title={`used ${d.used}`}
                    />
                  )}
                  {d.used === 0 && d.added === 0 && (
                    <div
                      style={{
                        width: "8px",
                        height: "3px",
                        background: "var(--ruled-line)",
                        borderRadius: "2px",
                      }}
                    />
                  )}
                </div>
                <span
                  className="font-body text-xs"
                  style={{ color: "var(--ink-muted)" }}
                >
                  {d.label}
                </span>
              </div>
            ))}
          </div>
          <div className="flex items-center gap-4 mt-1">
            <div className="flex items-center gap-1">
              <div
                className={statusHatch("low")}
                style={{ width: "12px", height: "10px", border: "1px solid var(--stock-low)" }}
              />
              <span className="font-body text-xs" style={{ color: "var(--ink-muted)" }}>
                used
              </span>
            </div>
            <div className="flex items-center gap-1">
              <div
                className={statusHatch("healthy")}
                style={{ width: "12px", height: "10px", border: "1px solid var(--stock-healthy)" }}
              />
              <span className="font-body text-xs" style={{ color: "var(--ink-muted)" }}>
                added
              </span>
            </div>
          </div>
        </NotebookCard>
      </div>

      {/* Quick actions */}
      <div className="mb-6">
        <SectionTitle>quick actions</SectionTitle>
        <div className="flex items-center gap-3 mt-3 flex-wrap">
          <CircledButton onClick={onScan}>
            <ScanIcon width="18" height="18" /> scan
          </CircledButton>
          <CircledButton onClick={() => onQuickAdd("chemical")}>
            <PlusIcon width="18" height="18" /> chemical
          </CircledButton>
          <CircledButton onClick={() => onQuickAdd("apparatus")}>
            <PlusIcon width="18" height="18" /> apparatus
          </CircledButton>
        </div>
      </div>

      {/* Recent activity */}
      <div>
        <SectionTitle>recent activity</SectionTitle>
        <NotebookCard className="mt-3" tilt={0}>
          {recentLogs.length === 0 ? (
            <p className="font-body text-sm" style={{ color: "var(--ink-muted)" }}>
              nothing logged yet — scan or add something to get started.
            </p>
          ) : (
            <div className="flex flex-col">
              {recentLogs.map((log) => (
                <ActivityEntry key={log.id} time={relativeTime(log.logged_at)}>
                  {activitySentence(log, chemicals, apparatus)} —{" "}
                  <span style={{ color: "var(--ink-muted)" }}>{shortDate(log.logged_at)}</span>
                </ActivityEntry>
              ))}
            </div>
          )}
        </NotebookCard>
      </div>

      <div className="mt-8 text-center">
        <button
          onClick={() => onNavigate("reports")}
          className="font-display text-xl font-semibold underline"
          style={{
            color: "var(--ink-muted)",
            textUnderlineOffset: "4px",
            textDecorationColor: "var(--ruled-line)",
          }}
        >
          view monthly reports →
        </button>
      </div>
    </div>
  );
}
