"use client";

import { useMemo, useState } from "react";
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

  // Chunk into pages of 40
  const pages: typeof chemicals[] = [];
  for (let i = 0; i < filtered.length; i += 40) {
    pages.push(filtered.slice(i, i + 40));
  }
  if (pages.length === 0) pages.push([]);

  const buildLabelHTML = () => {
    const html = document.querySelector("#qr-labels-content")?.innerHTML || "";
    return `<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>Lab Wizard — QR Labels</title>
<style>
  @page { size: A4; margin: 10mm; }
  html, body { margin: 0; padding: 0; background: white; font-family: 'Helvetica Neue', Arial, sans-serif; }
  * { box-sizing: border-box; }
  .qr-page {
    width: 190mm;
    page-break-after: always;
  }
  .qr-page:last-child { page-break-after: auto; }
  .qr-grid {
    display: grid;
    grid-template-columns: repeat(5, 1fr);
    grid-template-rows: repeat(8, 1fr);
    gap: 3mm;
  }
  .qr-label {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    padding: 1mm;
    border: 0.5px dashed #ccc;
    text-align: center;
  }
  .qr-name {
    font-size: 7pt;
    font-weight: 600;
    color: #1a1a1a;
    line-height: 1.1;
    margin-top: 1mm;
    word-break: break-word;
  }
  .qr-formula {
    font-size: 6pt;
    color: #666;
    margin-top: 0.5mm;
  }
  .print-btn {
    position: fixed; top: 12px; right: 16px; z-index: 999;
    background: #1a1a1a; color: white; border: none; padding: 10px 24px;
    font-size: 14px; font-weight: 600; border-radius: 6px; cursor: pointer;
  }
  @media print { .print-btn { display: none; } }
</style>
</head>
<body>
<button class="print-btn" onclick="window.print()">🖨 Print / Save as PDF</button>
${html}
</body>
</html>`;
  };

  const handlePrint = () => {
    const fullHTML = buildLabelHTML();
    const win = window.open("", "_blank", "width=800,height=900");
    if (!win) {
      // Pop-up blocked — download instead
      handleDownload();
      return;
    }
    win.document.write(fullHTML);
    win.document.close();
    win.focus();
  };

  const handleDownload = () => {
    const fullHTML = buildLabelHTML();
    const blob = new Blob([fullHTML], { type: "text/html" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `lab-wizard-qr-labels-${new Date().toISOString().slice(0, 10)}.html`;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
  };

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
          {filtered.length} labels · {pages.length} page{pages.length > 1 ? "s" : ""}
        </span>
        <button
          onClick={handleDownload}
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
          ⬇ Download labels
        </button>
        <button
          onClick={handlePrint}
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
          🖨 Print
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

      {/* Label sheets — rendered off-screen, used for print */}
      <div
        id="qr-labels-content"
        style={{ position: "absolute", left: "-9999px", top: 0 }}
      >
        {pages.map((page, pi) => (
          <div key={pi} className="qr-page">
            <div className="qr-grid">
              {page.map((c) => (
                <div key={c.id} className="qr-label">
                  <QRCodeSVG
                    value={`labwizard:chemical:${c.qr_code}`}
                    size={80}
                    level="M"
                  />
                  <div className="qr-name">{c.name}</div>
                  {c.formula && <div className="qr-formula">{c.formula}</div>}
                </div>
              ))}
            </div>
          </div>
        ))}
      </div>

      {/* On-screen preview */}
      <div style={{ padding: "70px 20px 20px", maxWidth: 800, margin: "0 auto" }}>
        <p style={{ fontFamily: "var(--font-body), cursive", color: "#666", fontSize: 14, marginBottom: 16 }}>
          {filtered.length} labels · {pages.length} page{pages.length > 1 ? "s" : ""} (40 per A4) · tap "⬇ Download labels" to save, then open the file and print to adhesive sheets.
        </p>
        <div style={{ display: "grid", gridTemplateColumns: "repeat(5, 1fr)", gap: 8 }}>
          {filtered.slice(0, 40).map((c) => (
            <div key={c.id} style={{
              display: "flex",
              flexDirection: "column",
              alignItems: "center",
              padding: 8,
              border: "0.5px dashed #ccc",
              textAlign: "center",
            }}>
              <QRCodeSVG
                value={`labwizard:chemical:${c.qr_code}`}
                size={70}
                level="M"
              />
              <div style={{ fontSize: 8, fontWeight: 600, marginTop: 4, wordBreak: "break-word" }}>
                {c.name}
              </div>
              {c.formula && <div style={{ fontSize: 7, color: "#666" }}>{c.formula}</div>}
            </div>
          ))}
        </div>
        {filtered.length > 40 && (
          <p style={{ fontFamily: "var(--font-body), cursive", color: "#666", fontSize: 12, marginTop: 12, textAlign: "center" }}>
            + {filtered.length - 40} more on page 2… click "Print labels" to see all.
          </p>
        )}
      </div>
    </>
  );
}
