"use client";

import { useRef, useState, type ReactNode } from "react";

/**
 * SwipeableCard — swipe left to reveal a "quick consume" action.
 *
 * On touch: drag the card left to reveal the action strip.
 * On desktop: the action strip is always visible on the right edge (subtle).
 *
 * Clicks/taps on the card itself pass through to the children normally.
 */

interface SwipeableCardProps {
  children: ReactNode;
  actionLabel: string;
  actionColor: string;
  onAction: () => void;
}

export function SwipeableCard({
  children,
  actionLabel,
  actionColor,
  onAction,
}: SwipeableCardProps) {
  const [offset, setOffset] = useState(0);
  const [showAction, setShowAction] = useState(false);
  const [dragging, setDragging] = useState(false);
  const startX = useRef(0);
  const startY = useRef(0);
  const draggingRef = useRef(false);
  const isHorizontal = useRef(false);
  const moved = useRef(false);

  const ACTION_WIDTH = 90;

  const onTouchStart = (e: React.TouchEvent) => {
    startX.current = e.touches[0].clientX;
    startY.current = e.touches[0].clientY;
    draggingRef.current = true;
    setDragging(true);
    isHorizontal.current = false;
    moved.current = false;
  };

  const onTouchMove = (e: React.TouchEvent) => {
    if (!draggingRef.current) return;
    const dx = e.touches[0].clientX - startX.current;
    const dy = e.touches[0].clientY - startY.current;
    // Determine direction on first significant move
    if (!isHorizontal.current && (Math.abs(dx) > 8 || Math.abs(dy) > 8)) {
      isHorizontal.current = Math.abs(dx) > Math.abs(dy);
      moved.current = true;
    }
    if (isHorizontal.current) {
      const clamped = Math.max(-ACTION_WIDTH, Math.min(0, dx));
      setOffset(clamped);
    }
  };

  const onTouchEnd = () => {
    draggingRef.current = false;
    setDragging(false);
    if (offset < -ACTION_WIDTH / 2) {
      setOffset(-ACTION_WIDTH);
      setShowAction(true);
    } else {
      setOffset(0);
      setShowAction(false);
    }
  };

  const handleActionClick = (e: React.MouseEvent) => {
    e.stopPropagation();
    onAction();
    setOffset(0);
    setShowAction(false);
  };

  return (
    <div style={{ position: "relative" }}>
      {/* Action strip behind the card — springs in when revealed */}
      {showAction && (
        <div
          onClick={handleActionClick}
          style={{
            position: "absolute",
            top: 0,
            right: 0,
            bottom: 0,
            width: ACTION_WIDTH,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            background: actionColor,
            color: "white",
            fontFamily: "var(--font-display), cursive",
            fontSize: "16px",
            fontWeight: 700,
            cursor: "pointer",
            borderRadius: "0 8px 8px 0",
            transform: "scaleX(1)",
            transformOrigin: "right center",
            transition: "transform 0.3s cubic-bezier(0.34, 1.56, 0.64, 1)",
            zIndex: 3,
          }}
        >
          {actionLabel}
        </div>
      )}

      {/* The card itself — slides left on swipe, clicks pass through to children */}
      <div
        onTouchStart={onTouchStart}
        onTouchMove={onTouchMove}
        onTouchEnd={onTouchEnd}
        style={{
          transform: `translateX(${offset}px)`,
          transition: dragging ? "none" : "transform 0.25s ease",
          position: "relative",
          zIndex: 2,
          background: "var(--card-fill)",
        }}
      >
        {children}
      </div>
    </div>
  );
}
