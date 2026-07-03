"use client";

import { clsx } from "clsx";
import type { TabKey } from "@/lib/types";
import {
  HomeIcon,
  FlaskIcon,
  BeakerIcon,
  ScanIcon,
  ChartIcon,
} from "@/components/notebook/icons";

interface NavItem {
  key: TabKey;
  label: string;
  Icon: typeof HomeIcon;
}

const NAV: NavItem[] = [
  { key: "home", label: "home", Icon: HomeIcon },
  { key: "chemicals", label: "chems", Icon: FlaskIcon },
  { key: "scan", label: "scan", Icon: ScanIcon },
  { key: "apparatus", label: "gear", Icon: BeakerIcon },
  { key: "reports", label: "reports", Icon: ChartIcon },
];

interface BottomNavProps {
  active: TabKey;
  onChange: (tab: TabKey) => void;
}

export function BottomNav({ active, onChange }: BottomNavProps) {
  return (
    <nav
      className="fixed bottom-0 left-0 right-0 z-40 no-print"
      style={{
        background: "var(--card-fill)",
        borderTop: "1.5px solid var(--border)",
        paddingBottom: "env(safe-area-inset-bottom, 0px)",
      }}
      aria-label="main navigation"
    >
      <div className="max-w-3xl mx-auto grid grid-cols-5">
        {NAV.map(({ key, label, Icon }) => {
          const isActive = active === key;
          const isScan = key === "scan";
          return (
            <button
              key={key}
              onClick={() => onChange(key)}
              className="flex flex-col items-center justify-center gap-0.5 py-2.5"
              style={{
                color: isActive ? "var(--margin-red)" : "var(--ink-muted)",
                minHeight: "56px",
              }}
              aria-current={isActive ? "page" : undefined}
            >
              <div
                style={{
                  transform: isScan ? "none" : isActive ? "rotate(-3deg)" : "none",
                  transition: "transform 0.2s",
                }}
              >
                {isScan ? (
                  <div
                    style={{
                      width: "40px",
                      height: "40px",
                      borderRadius: "999px",
                      border: "2px solid currentColor",
                      display: "flex",
                      alignItems: "center",
                      justifyContent: "center",
                      background: isActive ? "var(--margin-red)" : "transparent",
                      color: isActive ? "var(--card-fill)" : "var(--ink)",
                      marginTop: "-8px",
                      boxShadow: isActive ? "0 2px 0 var(--ink)" : "none",
                    }}
                  >
                    <Icon width="22" height="22" />
                  </div>
                ) : (
                  <Icon width="24" height="24" />
                )}
              </div>
              <span
                className="font-display text-sm font-semibold"
                style={{
                  color: isActive ? "var(--margin-red)" : "var(--ink-muted)",
                  textDecoration: isActive ? "underline" : "none",
                  textUnderlineOffset: "2px",
                }}
              >
                {label}
              </span>
            </button>
          );
        })}
      </div>
    </nav>
  );
}
