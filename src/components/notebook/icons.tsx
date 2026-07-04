// Hand-drawn SVG icons for the Notebook design system.
// Simple line doodles — the persistent bottom nav especially benefits
// from carrying the design language rather than using default lucide icons.

import type { SVGProps } from "react";

type IconProps = SVGProps<SVGSVGElement>;

const base = {
  fill: "none",
  stroke: "currentColor",
  strokeWidth: 1.8,
  strokeLinecap: "round" as const,
  strokeLinejoin: "round" as const,
  viewBox: "0 0 24 24",
};

export function FlaskIcon(props: IconProps) {
  return (
    <svg {...base} {...props}>
      <path d="M9 3h6" />
      <path d="M10 3v6L5.5 18a2 2 0 0 0 1.8 3h9.4a2 2 0 0 0 1.8-3L14 9V3" />
      <path d="M7.5 14h9" />
      <circle cx="10" cy="17" r="0.6" fill="currentColor" />
      <circle cx="13" cy="18.5" r="0.5" fill="currentColor" />
    </svg>
  );
}

export function BeakerIcon(props: IconProps) {
  return (
    <svg {...base} {...props}>
      <path d="M8 3h8" />
      <path d="M9 3v7l-3 8a1.5 1.5 0 0 0 1.4 2h9.2a1.5 1.5 0 0 0 1.4-2l-3-8V3" />
      <path d="M7 16h10" />
    </svg>
  );
}

export function ClipboardIcon(props: IconProps) {
  return (
    <svg {...base} {...props}>
      <path d="M9 4h6v2H9z" />
      <path d="M9 5H6.5a1.5 1.5 0 0 0-1.5 1.5v13A1.5 1.5 0 0 0 6.5 21h11a1.5 1.5 0 0 0 1.5-1.5v-13A1.5 1.5 0 0 0 17.5 5H15" />
      <path d="M8 10h8M8 13h8M8 16h5" />
    </svg>
  );
}

export function ScanIcon(props: IconProps) {
  return (
    <svg {...base} {...props}>
      <path d="M4 8V6a2 2 0 0 1 2-2h2" />
      <path d="M16 4h2a2 2 0 0 1 2 2v2" />
      <path d="M20 16v2a2 2 0 0 1-2 2h-2" />
      <path d="M8 20H6a2 2 0 0 1-2-2v-2" />
      <path d="M7 12h10" strokeDasharray="2 2" />
    </svg>
  );
}

export function ChartIcon(props: IconProps) {
  return (
    <svg {...base} {...props}>
      <path d="M4 20h16" />
      <path d="M7 20v-6" />
      <path d="M12 20V8" />
      <path d="M17 20v-9" />
      <path d="M4 4l4 3 4-2 5 3 3-2" />
    </svg>
  );
}

export function HomeIcon(props: IconProps) {
  return (
    <svg {...base} {...props}>
      <path d="M5 11l7-6 7 6" />
      <path d="M6 10v9h12v-9" />
      <path d="M10 19v-5h4v5" />
    </svg>
  );
}

export function PlusIcon(props: IconProps) {
  return (
    <svg {...base} {...props}>
      <path d="M12 5v14M5 12h14" />
    </svg>
  );
}

export function SearchIcon(props: IconProps) {
  return (
    <svg {...base} {...props}>
      <circle cx="10.5" cy="10.5" r="6" />
      <path d="M15 15l5 5" />
    </svg>
  );
}

export function ShareIcon(props: IconProps) {
  return (
    <svg {...base} {...props}>
      <circle cx="6" cy="12" r="2.5" />
      <circle cx="18" cy="6" r="2.5" />
      <circle cx="18" cy="18" r="2.5" />
      <path d="M8.2 10.8l7.6-3.6M8.2 13.2l7.6 3.6" />
    </svg>
  );
}

export function PrintIcon(props: IconProps) {
  return (
    <svg {...base} {...props}>
      <path d="M7 9V3h10v6" />
      <path d="M5 9h14a2 2 0 0 1 2 2v6h-4" />
      <path d="M5 17H3v-6a2 2 0 0 1 2-2" />
      <path d="M7 14h10v7H7z" />
    </svg>
  );
}

export function MinusIcon(props: IconProps) {
  return (
    <svg {...base} {...props}>
      <path d="M5 12h14" />
    </svg>
  );
}

export function QrIcon(props: IconProps) {
  return (
    <svg {...base} {...props}>
      <path d="M4 4h6v6H4z" />
      <path d="M14 4h6v6h-6z" />
      <path d="M4 14h6v6H4z" />
      <path d="M14 14h2v2h-2zM18 14h2v2h-2zM14 18h2v2h-2zM18 18h2v2h-2z" />
    </svg>
  );
}

export function CloseIcon(props: IconProps) {
  return (
    <svg {...base} {...props}>
      <path d="M6 6l12 12M18 6L6 18" />
    </svg>
  );
}

export function PencilIcon(props: IconProps) {
  return (
    <svg {...base} {...props}>
      <path d="M4 20l4-1 11-11-3-3L5 16l-1 4z" />
      <path d="M14 5l3 3" />
    </svg>
  );
}

export function TrashIcon(props: IconProps) {
  return (
    <svg {...base} {...props}>
      <path d="M5 7h14" />
      <path d="M9 7V5a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v2" />
      <path d="M7 7l1 13h8l1-13" />
    </svg>
  );
}

export function SunIcon(props: IconProps) {
  return (
    <svg {...base} {...props}>
      <circle cx="12" cy="12" r="4" />
      <path d="M12 3v2M12 19v2M3 12h2M19 12h2M5.6 5.6l1.4 1.4M17 17l1.4 1.4M18.4 5.6L17 7M7 17l-1.4 1.4" />
    </svg>
  );
}

export function MoonIcon(props: IconProps) {
  return (
    <svg {...base} {...props}>
      <path d="M19 14a8 8 0 1 1-9-11 6 6 0 0 0 9 11z" />
    </svg>
  );
}

export function ArrowRightIcon(props: IconProps) {
  return (
    <svg {...base} {...props}>
      <path d="M5 12h14M13 6l6 6-6 6" />
    </svg>
  );
}

export function ArrowLeftIcon(props: IconProps) {
  return (
    <svg {...base} {...props}>
      <path d="M19 12H5M11 18l-6-6 6-6" />
    </svg>
  );
}

export function StarIcon(props: IconProps) {
  return (
    <svg {...base} {...props}>
      <path d="M12 4l2.5 5 5.5.8-4 4 1 5.5L12 16.5 7 19.3l1-5.5-4-4 5.5-.8z" />
    </svg>
  );
}

export function PackageIcon(props: IconProps) {
  return (
    <svg {...base} {...props}>
      <path d="M4 8l8-4 8 4-8 4-8-4z" />
      <path d="M4 8v8l8 4 8-4V8" />
      <path d="M12 12v8" />
    </svg>
  );
}

/** Big standalone flask doodle for the auth screen. */
export function BigFlaskDoodle(props: IconProps) {
  return (
    <svg
      {...base}
      strokeWidth={2}
      width="80"
      height="80"
      {...props}
    >
      <path d="M11 4h2" />
      <path d="M11.5 4v8L6 19a2 2 0 0 0 1.8 3h8.4A2 2 0 0 0 18 19l-5.5-7V4" />
      <path d="M8 16h8" />
      <circle cx="9.5" cy="18" r="0.8" fill="currentColor" />
      <circle cx="13" cy="19.5" r="0.6" fill="currentColor" />
      <circle cx="11" cy="20" r="0.5" fill="currentColor" />
    </svg>
  );
}

/** Hand-drawn wavy underline squiggle for section titles. */
export function Squiggle(props: IconProps) {
  return (
    <svg
      fill="none"
      stroke="currentColor"
      strokeWidth={2}
      strokeLinecap="round"
      viewBox="0 0 120 8"
      width="120"
      height="8"
      {...props}
    >
      <path d="M2 5 C 12 1, 22 1, 32 5 S 52 9, 62 5 S 82 1, 92 5 S 112 9, 118 5" />
    </svg>
  );
}

/** Hand-drawn curved arrow with arrowhead, for margin notes pointing at cards. */
export function MarginArrow(props: IconProps) {
  return (
    <svg
      fill="none"
      stroke="currentColor"
      strokeWidth={1.8}
      strokeLinecap="round"
      strokeLinejoin="round"
      viewBox="0 0 60 40"
      width="60"
      height="40"
      {...props}
    >
      <path d="M5 8 C 20 8, 35 15, 45 28" />
      <path d="M38 25 L 46 30 L 42 22" />
    </svg>
  );
}

/** Simple paperclip doodle — matches reference: tall, top-right of card. */
export function PaperclipDoodle(props: IconProps) {
  return (
    <svg
      fill="none"
      stroke="currentColor"
      strokeWidth={2.5}
      strokeLinecap="round"
      strokeLinejoin="round"
      viewBox="0 0 28 46"
      width="28"
      height="46"
      {...props}
    >
      <path d="M8 8 C8 3 20 3 20 10 L20 32 C20 38 12 38 12 32 L12 14" />
    </svg>
  );
}
