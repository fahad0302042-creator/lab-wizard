"use client";

// Core Notebook design-system primitives.
// All of these are pure presentational components with no business logic.

import {
  forwardRef,
  type HTMLAttributes,
  type ReactNode,
  type InputHTMLAttributes,
  type TextareaHTMLAttributes,
  type ButtonHTMLAttributes,
} from "react";
import { clsx } from "clsx";
import {
  Squiggle,
  MarginArrow,
  PaperclipDoodle,
} from "./icons";
import type { StockStatus } from "@/lib/types";
import { statusHatch } from "@/lib/utils";

/* ============ Notebook Card ============ */

interface NotebookCardProps extends HTMLAttributes<HTMLDivElement> {
  /** Alternate corner pattern so no two cards look identical. */
  variant?: "a" | "b";
  /** Slight rotation tilt — pass a deg number, or "auto" for a deterministic per-index tilt. */
  tilt?: number | "auto";
  /** Show a washi-tape strip — pass a color or "random" for deterministic assignment. */
  tape?: "pink" | "yellow" | "blue" | "green" | "none";
  /** Show a paperclip doodle — for starred/flagged cards. */
  paperclip?: boolean;
  children: ReactNode;
}

const tapeColor: Record<string, string> = {
  pink: "var(--tape-pink)",
  yellow: "var(--tape-yellow)",
  blue: "var(--tape-blue)",
  green: "var(--tape-green)",
};

// Deterministic pseudo-random tilt based on a seed string.
function tiltFromSeed(seed: string): number {
  let h = 0;
  for (let i = 0; i < seed.length; i++) {
    h = (h * 31 + seed.charCodeAt(i)) | 0;
  }
  // Range -0.9 to +0.9 deg, never 0.
  const v = ((h % 180) / 100) - 0.9;
  return Math.abs(v) < 0.2 ? 0.6 * Math.sign(v || 1) : v;
}

export const NotebookCard = forwardRef<HTMLDivElement, NotebookCardProps>(
  function NotebookCard(
    {
      variant = "a",
      tilt = 0,
      tape = "none",
      paperclip = false,
      className,
      children,
      ...rest
    },
    ref
  ) {
    const tiltDeg =
      tilt === "auto"
        ? tiltFromSeed(typeof rest.id === "string" ? rest.id : String(children))
        : tilt;

    return (
      <div
        ref={ref}
        className={clsx(variant === "a" ? "nb-card" : "nb-card-alt", "p-4", className)}
        style={{
          transform: `rotate(${tiltDeg}deg)`,
        }}
        {...rest}
      >
        {tape !== "none" && (
          <div
            className="washi-tape animate-tape"
            style={
              {
                top: "-10px",
                left: "20px",
                backgroundColor: tapeColor[tape],
                "--tape-rot": "5deg",
                transform: "rotate(5deg)",
              } as React.CSSProperties
            }
          />
        )}
        {paperclip && (
          <div
            className="absolute"
            style={{ top: "-14px", right: "24px", color: "#8a8578", zIndex: 3 }}
          >
            <PaperclipDoodle />
          </div>
        )}
        {children}
      </div>
    );
  }
);

/* ============ Hand-Drawn Stock Bar ============ */

interface HandDrawnBarProps {
  status: StockStatus;
  percent: number;
  className?: string;
}

export function HandDrawnBar({ status, percent, className }: HandDrawnBarProps) {
  const pct = Math.max(0, Math.min(100, percent));
  return (
    <div
      className={clsx(
        "relative w-full overflow-hidden",
        className
      )}
      style={{
        height: "16px",
        border: "2px solid var(--ink)",
        borderRadius: "255px 15px 225px 15px / 15px 225px 15px 255px",
        background: "transparent",
      }}
      role="progressbar"
      aria-valuenow={pct}
      aria-valuemin={0}
      aria-valuemax={100}
    >
      <div
        className={clsx("h-full animate-bar", statusHatch(status))}
        style={{ width: `${pct}%` }}
      />
    </div>
  );
}

/* ============ Section title with squiggle underline ============ */

interface SectionTitleProps {
  children: ReactNode;
  className?: string;
  as?: "h1" | "h2" | "h3";
  tilt?: number;
}

export function SectionTitle({
  children,
  className,
  as: Tag = "h2",
  tilt = -1.5,
}: SectionTitleProps) {
  return (
    <div className={clsx("inline-block", className)}>
      <Tag
        className="font-display font-bold leading-none"
        style={{
          fontSize: Tag === "h1" ? "38px" : Tag === "h2" ? "30px" : "24px",
          transform: `rotate(${tilt}deg)`,
          color: "var(--ink)",
        }}
      >
        {children}
      </Tag>
      <div style={{ transform: `rotate(${tilt * 0.5}deg)`, color: "var(--margin-red)" }}>
        <Squiggle width="120" height="8" />
      </div>
    </div>
  );
}

/* ============ Circled hand-written button ============ */

interface CircledButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: "default" | "danger";
  children: ReactNode;
}

export const CircledButton = forwardRef<HTMLButtonElement, CircledButtonProps>(
  function CircledButton({ variant = "default", className, children, ...rest }, ref) {
    return (
      <button
        ref={ref}
        className={clsx("circled-btn", className)}
        style={
          variant === "danger"
            ? {
                borderColor: "var(--margin-red)",
                color: "var(--margin-red)",
              }
            : undefined
        }
        {...rest}
      >
        {children}
      </button>
    );
  }
);

/* ============ Ruled-line input ============ */

interface RuledInputProps extends InputHTMLAttributes<HTMLInputElement> {
  label?: string;
}

export const RuledInput = forwardRef<HTMLInputElement, RuledInputProps>(
  function RuledInput({ label, className, id, ...rest }, ref) {
    const inputId = id || rest.name;
    return (
      <div className="flex flex-col gap-1">
        {label && (
          <label
            htmlFor={inputId}
            className="font-display text-base font-semibold"
            style={{ color: "var(--ink-muted)" }}
          >
            {label}
          </label>
        )}
        <input
          ref={ref}
          id={inputId}
          className={clsx("ruled-input", className)}
          {...rest}
        />
      </div>
    );
  }
);

interface RuledTextareaProps extends TextareaHTMLAttributes<HTMLTextAreaElement> {
  label?: string;
}

export const RuledTextarea = forwardRef<HTMLTextAreaElement, RuledTextareaProps>(
  function RuledTextarea({ label, className, id, ...rest }, ref) {
    const inputId = id || rest.name;
    return (
      <div className="flex flex-col gap-1">
        {label && (
          <label
            htmlFor={inputId}
            className="font-display text-base font-semibold"
            style={{ color: "var(--ink-muted)" }}
          >
            {label}
          </label>
        )}
        <textarea
          ref={ref}
          id={inputId}
          className={clsx("ruled-input resize-none", className)}
          rows={2}
          {...rest}
        />
      </div>
    );
  }
);

/* ============ Torn-edge top ============ */

export function TornEdge({ className }: { className?: string }) {
  return (
    <div
      className={clsx("torn-top", className)}
      aria-hidden
      style={{ height: "1px" }}
    />
  );
}

/* ============ Highlighter accent ============ */

export function Highlighter({ children }: { children: ReactNode }) {
  return <span className="highlighter">{children}</span>;
}

/* ============ Margin note with arrow ============ */

interface MarginNoteProps {
  text: string;
  className?: string;
  arrow?: boolean;
}

export function MarginNote({ text, className, arrow = true }: MarginNoteProps) {
  return (
    <div
      className={clsx("flex items-start gap-1", className)}
      style={{
        color: "var(--margin-red)",
        transform: "rotate(-8deg)",
      }}
    >
      <div className="font-display font-bold leading-tight" style={{ fontSize: "17px", maxWidth: "70px" }}>
        {text}
      </div>
      {arrow && <MarginArrow width="40" height="24" />}
    </div>
  );
}

/* ============ Filter pill (handwritten word, not boxed) ============ */

interface FilterPillProps {
  active: boolean;
  children: ReactNode;
  onClick: () => void;
}

export function FilterPill({ active, children, onClick }: FilterPillProps) {
  return (
    <button
      onClick={onClick}
      className="font-display text-xl font-semibold transition-all"
      style={{
        color: active ? "var(--margin-red)" : "var(--ink-muted)",
        textDecoration: active ? "underline" : "none",
        textUnderlineOffset: "4px",
        textDecorationThickness: "2px",
        cursor: "pointer",
      }}
    >
      {children}
    </button>
  );
}

/* ============ Activity feed entry ============ */

export function ActivityEntry({
  children,
  time,
}: {
  children: ReactNode;
  time: string;
}) {
  return (
    <div className="flex items-baseline justify-between gap-3 py-1.5 border-b border-dashed border-[var(--ruled-line)] last:border-0">
      <span className="font-body text-sm" style={{ color: "var(--ink)" }}>
        {children}
      </span>
      <span
        className="font-body text-xs whitespace-nowrap"
        style={{ color: "var(--ink-muted)" }}
      >
        {time}
      </span>
    </div>
  );
}
