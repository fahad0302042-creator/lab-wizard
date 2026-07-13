"use client";

import { useState, useMemo } from "react";
import { motion } from "framer-motion";
import { useLabStore } from "@/lib/store";
import type { Apparatus, ApparatusCategory } from "@/lib/types";
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
} from "@/components/notebook/primitives";
import { PlusIcon, SearchIcon } from "@/components/notebook/icons";
import { PullToRefresh } from "@/components/notebook/pull-to-refresh";

interface ApparatusProps {
  searchQuery: string;
  onSearchChange: (q: string) => void;
  onAdd: () => void;
  onOpenDetail: (a: Apparatus) => void;
}

const TAPE_CYCLE = ["blue", "yellow", "green", "pink", "none", "none"] as const;

export function ApparatusScreen({
  searchQuery,
  onSearchChange,
  onAdd,
  onOpenDetail,
}: ApparatusProps) {
  const apparatus = useLabStore((s) => s.apparatus);
  const [category, setCategory] = useState<ApparatusCategory | "all">("all");
  const [localSearch, setLocalSearch] = useState(searchQuery);

  const effectiveSearch = (searchQuery || localSearch).toLowerCase().trim();

  const filtered = useMemo(() => {
    return apparatus.filter((a) => {
      if (category !== "all" && a.category !== category) return false;
      if (effectiveSearch) {
        const hay = `${a.name} ${a.notes}`.toLowerCase();
        if (!hay.includes(effectiveSearch)) return false;
      }
      return true;
    });
  }, [apparatus, category, effectiveSearch]);

  const cats: (ApparatusCategory | "all")[] = ["all", ...[
    "glassware", "balances", "heating", "measurement", "other",
  ]];

  return (
    <PullToRefresh onRefresh={async () => { /* data is reactive via Supabase */ }}>
    <div className="pb-24">
      <div className="mb-4">
        <SectionTitle>apparatus shelf</SectionTitle>
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
          placeholder="search apparatus…"
          className="flex-1 bg-transparent border-none outline-none font-body text-base"
          style={{ color: "var(--ink)" }}
        />
      </div>

      {/* Category filters */}
      <div className="flex items-center gap-3 mb-5 flex-wrap">
        {cats.map((c) => (
          <FilterPill
            key={c}
            active={category === c}
            onClick={() => setCategory(c)}
          >
            {c}
          </FilterPill>
        ))}
      </div>

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
            {apparatus.length === 0
              ? "tap the + below to add your first piece of apparatus."
              : "nothing matches your filter."}
          </p>
        </NotebookCard>
      ) : (
        <div className="flex flex-col gap-4">
          {filtered.map((a, i) => (
            <ApparatusCard
              key={a.id}
              apparatus={a}
              index={i}
              onOpen={() => onOpenDetail(a)}
            />
          ))}
        </div>
      )}

      {/* Add doodle */}
      <div className="text-center mt-6">
        <button
          onClick={onAdd}
          aria-label="add apparatus"
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
            ~ add new apparatus ~
          </span>
        </button>
      </div>
    </div>
    </PullToRefresh>
  );
}

function ApparatusCard({
  apparatus,
  index,
  onOpen,
}: {
  apparatus: Apparatus;
  index: number;
  onOpen: () => void;
}) {
  const status = stockStatus(apparatus);
  const pct = percentRemaining(apparatus);
  const caption = stockCaption(apparatus);
  const tape = TAPE_CYCLE[index % TAPE_CYCLE.length];
  const isFlagged = status === "low" || status === "critical" || status === "empty";
  const tilt = index % 2 === 0 ? 0.7 : -0.8;

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
          <MarginNote text={status === "empty" ? "out!" : "low!"} />
        </div>
      )}
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
              {apparatus.name}
            </h3>
            <p
              className="font-body text-base"
              style={{ color: "var(--ink-muted)" }}
            >
              {apparatus.category}
            </p>
          </div>
          <div className="text-right shrink-0">
            <div
              className="font-body font-bold"
              style={{ fontSize: "20px", color: "var(--ink)" }}
            >
              {apparatus.quantity}
            </div>
            <div
              className="font-body text-xs"
              style={{ color: "var(--ink-muted)" }}
            >
              {apparatus.low_stock_threshold > 0
                ? `min ${apparatus.low_stock_threshold}`
                : "pcs"}
            </div>
          </div>
        </div>

        <HandDrawnBar status={status} percent={pct} className="mt-2" />

        <p
          className="font-display text-base font-semibold mt-1"
          style={{ color: statusColor(status) }}
        >
          {status === "empty" ? (
            <Highlighter>out of stock!</Highlighter>
          ) : (
            caption
          )}
        </p>
      </NotebookCard>
    </motion.div>
  );
}
