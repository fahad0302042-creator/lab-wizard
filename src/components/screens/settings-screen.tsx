"use client";

import { useTheme } from "next-themes";
import { toast } from "sonner";
import { useLabStore } from "@/lib/store";
import {
  SectionTitle,
  NotebookCard,
  CircledButton,
} from "@/components/notebook/primitives";
import { SunIcon, MoonIcon } from "@/components/notebook/icons";

export function SettingsScreen() {
  const { theme, setTheme } = useTheme();
  const user = useLabStore((s) => s.user);
  const signOut = useLabStore((s) => s.signOut);
  const resetAll = useLabStore((s) => s.resetAll);
  const chemicalsCount = useLabStore((s) => s.chemicals.length);
  const apparatusCount = useLabStore((s) => s.apparatus.length);
  const logsCount = useLabStore((s) => s.logs.length);
  const counts = { chemicals: chemicalsCount, apparatus: apparatusCount, logs: logsCount };

  const isDark = theme === "dark";

  const handleSignOut = () => {
    signOut();
    toast.success("signed out — see you soon");
  };

  const handleReset = () => {
    if (
      !confirm(
        "Reset ALL data? This wipes chemicals, apparatus, and logs from your browser. Cannot be undone."
      )
    )
      return;
    resetAll();
    toast.success("all data wiped — fresh notebook");
  };

  return (
    <div className="pb-24">
      <div className="mb-4">
        <SectionTitle>settings</SectionTitle>
      </div>

      {/* Theme toggle */}
      <NotebookCard tilt={0} className="mb-4">
        <div className="flex items-center justify-between">
          <div>
            <h3
              className="font-display text-2xl font-bold"
              style={{ color: "var(--ink)" }}
            >
              appearance
            </h3>
            <p
              className="font-body text-sm"
              style={{ color: "var(--ink-muted)" }}
            >
              {isDark ? "under desk lamp — night mode" : "daylight — paper mode"}
            </p>
          </div>
          <button
            onClick={() => setTheme(isDark ? "light" : "dark")}
            className="flex items-center gap-2 px-3 py-1.5"
            style={{
              border: "2px solid var(--ink)",
              borderRadius: "999px",
              color: "var(--ink)",
            }}
            aria-label="toggle theme"
          >
            {isDark ? (
              <>
                <MoonIcon width="18" height="18" />
                <span className="font-display text-base font-semibold">night</span>
              </>
            ) : (
              <>
                <SunIcon width="18" height="18" />
                <span className="font-display text-base font-semibold">day</span>
              </>
            )}
          </button>
        </div>
      </NotebookCard>

      {/* User info */}
      <NotebookCard tilt={0} className="mb-4">
        <h3
          className="font-display text-2xl font-bold mb-2"
          style={{ color: "var(--ink)" }}
        >
          you
        </h3>
        <div className="font-body text-sm space-y-1">
          <div>
            <span style={{ color: "var(--ink-muted)" }}>name: </span>
            <span style={{ color: "var(--ink)" }}>{user?.name ?? "—"}</span>
          </div>
          <div>
            <span style={{ color: "var(--ink-muted)" }}>email: </span>
            <span style={{ color: "var(--ink)" }}>{user?.email ?? "—"}</span>
          </div>
        </div>
        <div className="mt-3">
          <CircledButton onClick={handleSignOut} variant="danger">
            sign out
          </CircledButton>
        </div>
      </NotebookCard>

      {/* About */}
      <NotebookCard tilt={0} className="mb-4">
        <h3
          className="font-display text-2xl font-bold mb-2"
          style={{ color: "var(--ink)" }}
        >
          about
        </h3>
        <div className="font-body text-sm space-y-1" style={{ color: "var(--ink-muted)" }}>
          <p>
            <span style={{ color: "var(--ink)" }}>lab wizard</span> — v1.0 (notebook edition)
          </p>
          <p>your chemistry lab inventory, hand-written.</p>
          <p>
            currently tracking{" "}
            <strong style={{ color: "var(--ink)" }}>{counts.chemicals}</strong> chemicals,{" "}
            <strong style={{ color: "var(--ink)" }}>{counts.apparatus}</strong> apparatus,{" "}
            <strong style={{ color: "var(--ink)" }}>{counts.logs}</strong> log entries.
          </p>
          <p className="pt-2">
            data is stored locally in your browser. a Supabase backend can be wired in later — the data layer is isolated in <code style={{ color: "var(--ink)" }}>lib/store.ts</code>.
          </p>
        </div>
      </NotebookCard>

      {/* Danger zone */}
      <NotebookCard tilt={0} className="mb-4">
        <h3
          className="font-display text-2xl font-bold mb-2"
          style={{ color: "var(--margin-red)" }}
        >
          danger zone
        </h3>
        <p className="font-body text-sm mb-3" style={{ color: "var(--ink-muted)" }}>
          wipes everything — chemicals, apparatus, logs, account. you'll get a fresh empty notebook.
        </p>
        <button
          onClick={handleReset}
          className="font-display text-lg font-semibold underline"
          style={{ color: "var(--margin-red)", textUnderlineOffset: "3px" }}
        >
          reset all data
        </button>
      </NotebookCard>
    </div>
  );
}
