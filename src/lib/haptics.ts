"use client";

/** Haptic feedback — vibrates on supported devices (Android only). */

export function haptic(pattern: number | number[] = 10) {
  if (typeof navigator !== "undefined" && "vibrate" in navigator) {
    try {
      navigator.vibrate(pattern);
    } catch {
      // ignore — not supported
    }
  }
}

/** Short tap — for button presses */
export function hapticTap() {
  haptic(10);
}

/** Double tap — for successful actions */
export function hapticSuccess() {
  haptic([10, 30, 10]);
}

/** Long buzz — for errors/warnings */
export function hapticError() {
  haptic([50, 50, 50]);
}
