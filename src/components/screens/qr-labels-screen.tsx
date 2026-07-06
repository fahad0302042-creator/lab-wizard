"use client";

import { useMemo, useState, createPortal } from "react";
import { QRCodeSVG } from "qrcode.react";
import { useLabStore } from "@/lib/store";

/**
 * Bulk QR label printing page.
 * Renders 40 QR codes per A4 page (5 cols × 8 rows) for all chemicals.
 * Clean/functional layout — no hand-drawn flourishes — so labels scan reliably.
 * Triggered via window.print(); only this component shows when printing.
 */
export function QrLabelsScreen({ onClose }: { onClose: () => void }) {
  const chemicals = useLabStore((s) => s.chemicals);
  const [search, setSearch] = useState("");

  const filtered = useMemo(() => {
    if (!search.trim()) return chemicals;
    const q = search.toLowerCase();
    return chemicals.filter((c) =>
      `${c.name} ${c.formula}`.toLowerCase().includes(q)
    );
  }, [chemicals, search]);

  return (
    <>
      {/* On-screen toolbar (hidden when printing) */}
      <div
        className="no-print"
        style={{
          position: "fixed",
          top: 0,
          left: 0,
          right: 0,
          zIndex: 100,
          background: "#1a1a1a",
          color: "white",
          padding: "10px 20px",
          display: "flex",
          alignItems: "center",
          gap: "14px",
          flexWrap: "wrap",
        }}
      >
        <span style={{ fontSize: 14, fontWeight: 600 }}>Lab Wizard — QR Labels</span>
        <input
          type="text"
          placeholder="filter by name or formula…"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          style={{
            flex: 1,
            minWidth: 150,
            background: "white",
            color: "#1a1a1a",
            border: "none",
            padding: "6px 12px",
            borderRadius: 4,
            fontSize: 13,
            fontFamily: "inherit",
          }}
        />
        <span style={{ fontSize: 12, opacity: 0.7 }}>
          {filtered.length} labels · {Math.ceil(filtered.length / 40)} page
          {Math.ceil(filtered.length / 40) > 1 ? "s" : ""}
        </span>
        <button
          onClick={() => window.print()}
          style={{
            background: "white",
            color: "#1a1a1a",
            border: "none",
            padding: "8px 20px",
            fontSize: 14,
            fontWeight: 600,
            borderRadius: 4,
            cursor: "pointer",
            fontFamily: "inherit",
          }}
        >
          🖨 Print labels
        </button>
        <button
          onClick={onClose}
          style={{
            background: "transparent",
            color: "white",
            border: "1px solid white",
            padding: "7px 16px",
            fontSize: 13,
            borderRadius: 4,
            cursor: "pointer",
            fontFamily: "inherit",
          }}
        >
          ← Back
        </button>
      </div>

      {/* Print-only label sheets (portaled to body so print CSS can hide everything else) */}
      <QrLabelPortal chemicals={filtered} />
    </>
  );
}

function QrLabelPortal({ chemicals }: { chemicals: ReturnType<typeof useLabStore.getState>["chemicals"] }) {
  if (typeof document === "undefined") return null;

  // Chunk into pages of 40
  const pages: (typeof chemicals)[] = [];
  for (let i = 0; i < chemicals.length; i += 40) {
    pages.push(chemicals.slice(i, i + 40));
  }
  // Ensure at least one page even if empty
  if (pages.length === 0) pages.push([]);

  return createPortal(
    <div className="qr-print-only">
      {pages.map((page, pi) => (
        <div key={pi} className="qr-page">
          <div className="qr-grid">
            {page.map((c) => (
              <div key={c.id} className="qr-label">
                <div className="qr-code">
                  <QRCodeSVG
                    value={`labwizard:chemical:${c.qr_code}`}
                    size={80}
                    level="M"
                  />
                </div>
                <div className="qr-text">
                  <div className="qr-name">{c.name}</div>
                  {c.formula && <div className="qr-formula">{c.formula}</div>}
                </div>
              </div>
            ))}
          </div>
        </div>
      ))}
    </div>,
    document.body
  );
}
