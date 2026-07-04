"use client";

import { useState, useEffect, useRef, useMemo } from "react";
import { motion } from "framer-motion";
import { toast } from "sonner";
import { useLabStore } from "@/lib/store";
import type { Chemical } from "@/lib/types";
import {
  SectionTitle,
  NotebookCard,
  CircledButton,
  RuledInput,
} from "@/components/notebook/primitives";
import { ScanIcon, SearchIcon } from "@/components/notebook/icons";

interface ScannerProps {
  onScanned: (c: Chemical) => void;
}

export function ScannerScreen({ onScanned }: ScannerProps) {
  const chemicals = useLabStore((s) => s.chemicals);
  const recentScans = useLabStore((s) => s.recentScans);
  const pushRecentScan = useLabStore((s) => s.pushRecentScan);
  const [scanning, setScanning] = useState(false);
  const [manualQuery, setManualQuery] = useState("");
  const [error, setError] = useState<string | null>(null);
  const containerRef = useRef<HTMLDivElement>(null);
  const html5QrRef = useRef<{ stop: () => Promise<void> } | null>(null);

  const recentChemicals = useMemo(
    () =>
      recentScans
        .map((id) => chemicals.find((c) => c.id === id))
        .filter((c): c is Chemical => c !== undefined),
    [recentScans, chemicals]
  );

  // Manual search results
  const manualResults = useMemo(() => {
    const q = manualQuery.toLowerCase().trim();
    if (!q) return [];
    return chemicals
      .filter((c) => `${c.name} ${c.formula}`.toLowerCase().includes(q))
      .slice(0, 5);
  }, [chemicals, manualQuery]);

  const stopScanning = async () => {
    try {
      if (html5QrRef.current) {
        await html5QrRef.current.stop();
        html5QrRef.current = null;
      }
    } catch {
      // ignore
    }
    setScanning(false);
  };

  const startScanning = async () => {
    setError(null);
    setScanning(true);
    try {
      const { Html5Qrcode } = await import("html5-qrcode");

      const elementId = "qr-reader-container";
      const html5Qrcode = new Html5Qrcode(elementId);

      html5QrRef.current = {
        stop: async () => {
          try {
            await html5Qrcode.stop();
            await html5Qrcode.clear();
          } catch {
            // already stopped
          }
        },
      };

      const qrboxFn = (_v: unknown, hw: { width: number; height: number }) => {
        const minEdge = Math.min(hw.width, hw.height);
        const size = Math.max(150, Math.floor(minEdge * 0.7));
        return { width: size, height: size };
      };

      await html5Qrcode.start(
        { facingMode: "environment" },
        { fps: 10, qrbox: qrboxFn, aspectRatio: 1 },
        (decodedText: string) => {
          // Expected format: labwizard:chemical:<uuid>
          const match = decodedText.match(/^labwizard:chemical:(.+)$/);
          const qr = match ? match[1] : decodedText;
          const chem = chemicals.find((c) => c.qr_code === qr);
          if (chem) {
            pushRecentScan(chem.id);
            stopScanning();
            onScanned(chem);
          } else {
            toast.error("that QR code isn't in your shelf");
          }
        },
        () => {
          // per-frame failure — ignore
        }
      );
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      if (/permission|notallowed/i.test(msg)) {
        setError("camera permission denied — try the manual search below.");
      } else if (/notfound|no camera/i.test(msg)) {
        setError("no camera found — use the manual search below.");
      } else {
        setError("couldn't start the camera. use the manual search below.");
      }
      setScanning(false);
    }
  };

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      stopScanning();
    };
  }, []);

  const onManualPick = (c: Chemical) => {
    pushRecentScan(c.id);
    onScanned(c);
  };

  return (
    <div className="pb-24">
      <div className="mb-4">
        <SectionTitle>scan a reagent</SectionTitle>
      </div>

      {/* Camera viewport */}
      <NotebookCard tilt={0} className="mb-5">
        <div className="flex flex-col items-center">
          <div
            id="qr-reader-container"
            ref={containerRef}
            className="dashed-hand w-full aspect-square max-w-sm bg-transparent overflow-hidden flex items-center justify-center"
            style={{ minHeight: "240px" }}
          >
            {!scanning && (
              <div className="text-center px-4">
                <ScanIcon
                  width="60"
                  height="60"
                  style={{ color: "var(--ink-muted)", margin: "0 auto" }}
                />
                <p
                  className="font-display text-xl font-bold mt-3"
                  style={{ color: "var(--ink)" }}
                >
                  scan a bottle's QR
                </p>
                <p
                  className="font-body text-sm mt-1"
                  style={{ color: "var(--ink-muted)" }}
                >
                  tap start, then point your camera at the label.
                </p>
              </div>
            )}
          </div>

          {error && (
            <p
              className="font-display text-base font-semibold text-center mt-2 px-4"
              style={{ color: "var(--margin-red)" }}
            >
              {error}
            </p>
          )}

          <div className="mt-3">
            {scanning ? (
              <CircledButton onClick={stopScanning} variant="danger">
                stop
              </CircledButton>
            ) : (
              <CircledButton onClick={startScanning}>
                <ScanIcon width="16" height="16" /> start camera
              </CircledButton>
            )}
          </div>
        </div>
      </NotebookCard>

      {/* Recent scans */}
      {recentChemicals.length > 0 && (
        <div className="mb-5">
          <h3
            className="font-display text-xl font-bold mb-2"
            style={{ color: "var(--ink)", transform: "rotate(-1deg)", display: "inline-block" }}
          >
            recently scanned
          </h3>
          <div className="flex gap-2 overflow-x-auto no-scrollbar pb-1">
            {recentChemicals.map((c) => (
              <button
                key={c.id}
                onClick={() => onManualPick(c)}
                className="shrink-0 px-3 py-1.5"
                style={{
                  background: "var(--card-fill)",
                  border: "1.5px solid var(--border)",
                  borderRadius: "3px 8px 2px 9px / 8px 3px 9px 2px",
                }}
              >
                <span className="font-accent font-bold text-sm" style={{ color: "var(--ink)" }}>
                  {c.name}
                </span>
              </button>
            ))}
          </div>
        </div>
      )}

      {/* Manual search fallback */}
      <div>
        <h3
          className="font-display text-xl font-bold mb-2"
          style={{ color: "var(--ink)", transform: "rotate(-1deg)", display: "inline-block" }}
        >
          or search by name
        </h3>
        <div className="flex items-center gap-2 border-b-2 pb-1 mb-3" style={{ borderColor: "var(--ruled-line)" }}>
          <SearchIcon width="18" height="18" style={{ color: "var(--ink-muted)" }} />
          <input
            value={manualQuery}
            onChange={(e) => setManualQuery(e.target.value)}
            placeholder="type a reagent name…"
            className="flex-1 bg-transparent border-none outline-none font-body text-base"
            style={{ color: "var(--ink)" }}
          />
        </div>

        {manualResults.length > 0 && (
          <div className="flex flex-col gap-2">
            {manualResults.map((c) => (
              <motion.button
                key={c.id}
                initial={{ opacity: 0, y: 4 }}
                animate={{ opacity: 1, y: 0 }}
                onClick={() => onManualPick(c)}
                className="text-left"
              >
                <NotebookCard tilt={0} className="cursor-pointer hover:translate-y-[-1px] transition-transform">
                  <div className="flex items-center justify-between">
                    <div>
                      <span className="font-accent font-bold" style={{ fontSize: "18px", color: "var(--ink)" }}>
                        {c.name}
                      </span>
                      {c.formula && (
                        <span className="font-body text-sm ml-2" style={{ color: "var(--ink-muted)" }}>
                          {c.formula}
                        </span>
                      )}
                    </div>
                    <span className="font-body text-sm" style={{ color: "var(--ink-muted)" }}>
                      {c.quantity} {c.unit}
                    </span>
                  </div>
                </NotebookCard>
              </motion.button>
            ))}
          </div>
        )}

        {manualQuery && manualResults.length === 0 && (
          <p className="font-body text-sm" style={{ color: "var(--ink-muted)" }}>
            no reagents match “{manualQuery}”.
          </p>
        )}
      </div>
    </div>
  );
}
