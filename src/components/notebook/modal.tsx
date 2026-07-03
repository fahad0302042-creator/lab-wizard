"use client";

import { useEffect, type ReactNode } from "react";
import { clsx } from "clsx";
import { CloseIcon } from "./icons";
import { TornEdge } from "./primitives";

interface ModalProps {
  open: boolean;
  onClose: () => void;
  title?: string;
  children: ReactNode;
  footer?: ReactNode;
  /** When true, the modal is styled as a notebook card overlay (torn-edge top, etc.). */
  variant?: "notebook" | "plain";
  size?: "sm" | "md" | "lg";
}

export function Modal({
  open,
  onClose,
  title,
  children,
  footer,
  variant = "notebook",
  size = "md",
}: ModalProps) {
  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
    };
    document.addEventListener("keydown", onKey);
    document.body.style.overflow = "hidden";
    return () => {
      document.removeEventListener("keydown", onKey);
      document.body.style.overflow = "";
    };
  }, [open, onClose]);

  if (!open) return null;

  const maxW =
    size === "sm" ? "max-w-sm" : size === "lg" ? "max-w-2xl" : "max-w-md";

  return (
    <div
      className="fixed inset-0 z-50 flex items-end sm:items-center justify-center p-0 sm:p-4"
      style={{ background: "rgba(43, 42, 40, 0.45)" }}
      onClick={onClose}
    >
      <div
        onClick={(e) => e.stopPropagation()}
        className={clsx(
          "relative w-full overflow-hidden",
          maxW,
          variant === "notebook" ? "nb-card-alt" : "nb-card-alt"
        )}
        style={{
          background: "var(--card-fill)",
          borderColor: "var(--border)",
          maxHeight: "92vh",
          transform: "rotate(0deg)",
        }}
      >
        {variant === "notebook" && <TornEdge className="no-print" />}
        <button
          onClick={onClose}
          aria-label="Close"
          className="absolute top-3 right-3 z-10 p-1"
          style={{ color: "var(--ink-muted)" }}
        >
          <CloseIcon width="20" height="20" />
        </button>

        {title && (
          <div className="px-5 pt-5 pb-2">
            <h2
              className="font-display font-bold leading-none"
              style={{ fontSize: "28px", color: "var(--ink)", transform: "rotate(-1deg)" }}
            >
              {title}
            </h2>
          </div>
        )}

        <div
          className="px-5 py-4 overflow-y-auto nb-scroll"
          style={{ maxHeight: "calc(92vh - 120px)" }}
        >
          {children}
        </div>

        {footer && (
          <div
            className="px-5 py-3 flex items-center justify-end gap-2 flex-wrap"
            style={{
              borderTop: "1.5px dashed var(--ruled-line)",
              background: "color-mix(in srgb, var(--card-fill) 80%, var(--paper))",
            }}
          >
            {footer}
          </div>
        )}
      </div>
    </div>
  );
}
