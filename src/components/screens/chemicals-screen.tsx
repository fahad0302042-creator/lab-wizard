"use client";

import { useState, useMemo } from "react";
import { motion } from "framer-motion";
import { useLabStore } from "@/lib/store";
import type { Chemical } from "@/lib/types";
import {
  percentRemaining,
  stockStatus,
  stockCaption,
  statusColor,
} from "@/lib/utils";
import {
  NotebookCard,
  SectionTitle,
  HandDrawnBar,
  FilterPill,
  MarginNote,
  Highlighter,
  CircledButton,
} from "@/components/notebook/primitives";
import { PlusIcon, SearchIcon, QrIcon } from "@/components/notebook/icons";
import { SwipeableCard } from "@/components/notebook/swipeable-card";
import { PullToRefresh } from "@/components/notebook/pull-to-refresh";

type Filter = "all" | "low" | "critical";

interface ChemicalsProps {
  searchQuery: string;
  onSearchChange: (q: string) => void;
  onAdd: () => void;
  onOpenDetail: (c: Chemical) => void;
  onPrintQrLabels: () => void;
  onQuickConsume: (c: Chemical) => void;
}

const TAPE_CYCLE = ["yellow", "blue", "green", "pink", "none", "none"] as const;

export function ChemicalsScreen({
  searchQuery,
  onSearchChange,
  onAdd,
  onOpenDetail,
  onPrintQrLabels,
  onQuickConsume,
}: ChemicalsProps) {
  const chemicals = useLabStore((s) => s.chemicals);
  const [filter, setFilter] = useState<Filter>("all");
  const [localSearch, setLocalSearch] = useState(searchQuery);

  const effectiveSearch = (searchQuery || localSearch).toLowerCase().trim();

  const filtered = useMemo(() => {
    return chemicals.filter((c) => {
      const status = stockStatus(c);
      if (filter === "low" && !(status === "low" || status === "critical")) return false;
      if (filter === "critical" && status !== "critical" && status !== "empty") return false;
      if (effectiveSearch) {
        const hay = `${c.name} ${c.formula} ${c.notes}`.toLowerCase();
        if (!hay.includes(effectiveSearch)) return false;
      }
      return true;
    });
  }, [chemicals, filter, effectiveSearch]);

  return (
    <PullToRefresh onRefresh={async () => { /* data is reactive via Supabase */ }}>
    <div className="pb-24">
      <div className="mb-4">
        <SectionTitle>chemicals shelf</SectionTitle>
      </div>

      {/* Search */}
      <div className="mb-3 flex items-center gap-2 border-b-2 pb-1" style={{ borderColor: "var(--ruled-line)" }}>
        <SearchIcon width="18" height="18" style={{ color: "var(--ink-muted)" }} />
        <input
          value={localSearch}
          onChange={(e) => {
            setLocalSearch(e.target.value);
            onSearchChange(e.target.value);
          }}
          placeholder="search by name, formula, note…"
          className="flex-1 bg-transparent border-none outline-none font-body text-base"
          style={{ color: "var(--ink)" }}
        />
      </div>

      {/* Filters */}
      <div className="flex items-center gap-4 mb-3 flex-wrap">
        <FilterPill active={filter === "all"} onClick={() => setFilter("all")}>
          all
        </FilterPill>
        <FilterPill active={filter === "low"} onClick={() => setFilter("low")}>
          low
        </FilterPill>
        <FilterPill active={filter === "critical"} onClick={() => setFilter("critical")}>
          critical
        </FilterPill>
        <span
          className="font-body text-sm ml-auto"
          style={{ color: "var(--ink-muted)" }}
        >
          {filtered.length} of {chemicals.length}
        </span>
      </div>

      {/* Print QR labels */}
      {chemicals.length > 0 && (
        <div className="mb-5">
          <button
            onClick={onPrintQrLabels}
            className="font-body text-sm underline flex items-center gap-1"
            style={{ color: "var(--ink-muted)", textUnderlineOffset: "3px" }}
          >
            <QrIcon width="16" height="16" /> print QR labels (40 per A4)
          </button>
        </div>
      )}

      {/* List */}
      {filtered.length === 0 ? (
        <NotebookCard tilt={0} className="text-center py-10">
          <p
            className="font-display text-2xl font-bold mb-2"
            style={{ color: "var(--ink)" }}
          >
            empty shelf
          </p>
          <p className="font-body text-sm" style={{ color: "var(--ink-muted)" }}>
            {chemicals.length === 0
              ? "tap the + below to add your first reagent."
              : "nothing matches your filter — try “all”."}
          </p>
        </NotebookCard>
      ) : (
        <div className="flex flex-col gap-4">
          {filtered.map((c, i) => (
            <ChemicalCard
              key={c.id}
              chemical={c}
              index={i}
              onOpen={() => onOpenDetail(c)}
              onQuickConsume={() => onQuickConsume(c)}
            />
          ))}
        </div>
      )}

      {/* Add doodle — circled + with caption, like the reference */}
      <div className="text-center mt-6">
        <button
          onClick={onAdd}
          aria-label="add chemical"
          className="inline-flex flex-col items-center gap-1"
        >
          <div
            style={{
              width: "56px",
              height: "56px",
              border: "2.5px solid var(--ink)",
              borderRadius: "50%",
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              fontFamily: "var(--font-display), cursive",
              fontSize: "34px",
              fontWeight: 700,
              background: "var(--card-fill)",
              color: "var(--ink)",
              lineHeight: 1,
              paddingBottom: "4px",
            }}
          >
            +
          </div>
          <span
            className="font-display"
            style={{ fontSize: "16px", color: "var(--ink-muted)", transform: "rotate(-1deg)" }}
          >
            ~ add new reagent ~
          </span>
        </button>
      </div>
    </div>
    </PullToRefresh>
  );
}

function ChemicalCard({
  chemical,
  index,
  onOpen,
  onQuickConsume,
}: {
  chemical: Chemical;
  index: number;
  onOpen: () => void;
  onQuickConsume: () => void;
}) {
  const status = stockStatus(chemical);
  const pct = percentRemaining(chemical);
  const caption = stockCaption(chemical);
  const tape = TAPE_CYCLE[index % TAPE_CYCLE.length];
  const isFlagged = status === "low" || status === "critical" || status === "empty";
  const tilt = index % 2 === 0 ? -0.8 : 0.9;
  const canConsume = chemical.quantity > 0;

  return (
    <motion.div
      initial={{ opacity: 0, y: 10 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ delay: Math.min(index * 0.04, 0.3) }}
      className="relative"
    >
      {isFlagged && (
        <div
          className="absolute z-10"
          style={{
            left: "-42px",
            top: "6px",
            color: "var(--margin-red)",
          }}
        >
          <MarginNote text={status === "empty" ? "empty!" : "order!"} />
        </div>
      )}
      <SwipeableCard
        actionLabel={canConsume ? "use" : "—"}
        actionColor={canConsume ? "var(--margin-red)" : "var(--ink-muted)"}
        onAction={canConsume ? onQuickConsume : () => {}}
      >
        <NotebookCard
          tape={tape}
          paperclip={status === "critical" || status === "empty"}
          tilt={tilt}
          onClick={onOpen}
          className="cursor-pointer hover:translate-y-[-2px] transition-transform"
        >
          <div className="flex items-start justify-between gap-2 mb-1">
            <div className="min-w-0 flex-1">
              <h3
                className="font-accent font-bold leading-tight truncate"
                style={{ fontSize: "22px", color: "var(--ink)" }}
              >
                {chemical.name}
              </h3>
              {chemical.formula && (
                <p
                  className="font-body text-base"
                  style={{ color: "var(--ink-muted)" }}
                >
                  {chemical.formula}
                </p>
              )}
            </div>
            <div className="text-right shrink-0">
              <div
                className="font-body font-bold"
                style={{ fontSize: "20px", color: "var(--ink)" }}
              >
                {chemical.quantity}
                <span style={{ color: "var(--ink-muted)", fontSize: "14px" }}>
                  {" "}{chemical.unit}
                </span>
              </div>
              <div
                className="font-body text-xs"
                style={{ color: "var(--ink-muted)" }}
              >
                {chemical.low_stock_threshold > 0
                  ? `min ${chemical.low_stock_threshold} ${chemical.unit}`
                  : chemical.unit}
              </div>
            </div>
          </div>

          <HandDrawnBar status={status} percent={pct} className="mt-2" />

          <p
            className="font-display text-base font-semibold mt-1"
            style={{ color: statusColor(status) }}
          >
            {status === "empty" ? (
              <>
                <Highlighter>0% — (empty!)</Highlighter>
              </>
            ) : (
              caption
            )}
          </p>
        </NotebookCard>
      </SwipeableCard>
    </motion.div>
  );
}
