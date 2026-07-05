"use client";

import { useRef, useState, type ReactNode } from "react";

/**
 * PullToRefresh — pull down on mobile to trigger a refresh.
 *
 * Shows a hand-drawn spinner (↻) that rotates as you pull.
 * Triggers onRefresh when pulled past the threshold.
 */
export function PullToRefresh({
  children,
  onRefresh,
}: {
  children: ReactNode;
  onRefresh: () => Promise<void> | void;
}) {
  const [pull, setPull] = useState(0);
  const [refreshing, setRefreshing] = useState(false);
  const startY = useRef(0);
  const pulling = useRef(false);

  const THRESHOLD = 70;

  const onTouchStart = (e: React.TouchEvent) => {
    if (window.scrollY > 0) return; // only when at top
    startY.current = e.touches[0].clientY;
    pulling.current = true;
  };

  const onTouchMove = (e: React.TouchEvent) => {
    if (!pulling.current || refreshing) return;
    const dy = e.touches[0].clientY - startY.current;
    if (dy > 0 && window.scrollY <= 0) {
      const resisted = Math.min(dy * 0.5, 100); // resistance
      setPull(resisted);
    }
  };

  const onTouchEnd = async () => {
    pulling.current = false;
    if (pull >= THRESHOLD) {
      setRefreshing(true);
      setPull(THRESHOLD);
      try {
        await onRefresh();
      } finally {
        setRefreshing(false);
        setPull(0);
      }
    } else {
      setPull(0);
    }
  };

  const rotation = (pull / THRESHOLD) * 360;

  return (
    <div
      onTouchStart={onTouchStart}
      onTouchMove={onTouchMove}
      onTouchEnd={onTouchEnd}
      style={{ position: "relative", minHeight: "100%" }}
    >
      {/* Pull indicator */}
      {(pull > 0 || refreshing) && (
        <div
          style={{
            position: "absolute",
            top: `${pull - 40}px`,
            left: "50%",
            transform: `translateX(-50%)`,
            fontSize: "24px",
            color: "var(--ink-muted)",
            fontFamily: "var(--font-display), cursive",
            fontWeight: 700,
            opacity: Math.min(pull / THRESHOLD, 1),
            pointerEvents: "none",
            zIndex: 10,
          }}
        >
          <span
            style={{
              display: "inline-block",
              transform: `rotate(${refreshing ? "360deg" : `${rotation}deg`})`,
              transition: refreshing ? "transform 0.8s linear infinite" : "none",
            }}
          >
            ↻
          </span>
          {refreshing ? " refreshing…" : pull >= THRESHOLD ? " release!" : ""}
        </div>
      )}
      {children}
    </div>
  );
}
