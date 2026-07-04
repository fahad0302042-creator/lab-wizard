"use client";

import { useState } from "react";
import { motion } from "framer-motion";
import { toast } from "sonner";
import { useLabStore } from "@/lib/store";
import { isSupabaseConfigured } from "@/lib/supabase";
import { BigFlaskDoodle } from "@/components/notebook/icons";
import { RuledInput, CircledButton } from "@/components/notebook/primitives";

export function AuthScreen() {
  const signIn = useLabStore((s) => s.signIn);
  const signUp = useLabStore((s) => s.signUp);
  const [mode, setMode] = useState<"signin" | "signup">("signin");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [name, setName] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const usingSupabase = isSupabaseConfigured();

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);
    if (!email.trim() || !email.includes("@")) {
      setError("hmm, that email doesn't look right");
      return;
    }
    if (password.length < 4) {
      setError("password needs at least 4 chars");
      return;
    }
    if (mode === "signup" && !name.trim()) {
      setError("add your name so we can say hi properly");
      return;
    }

    setBusy(true);
    try {
      if (mode === "signin") {
        await signIn(email.trim(), password);
      } else {
        await signUp(email.trim(), password, name.trim());
      }
      toast.success("welcome to your lab notebook!");
    } catch (err) {
      const msg = err instanceof Error ? err.message : "something went wrong";
      setError(msg);
    } finally {
      setBusy(false);
    }
  };

  return (
    <div
      className="min-h-screen flex items-center justify-center p-4"
      style={{ background: "var(--desk)" }}
    >
      <motion.div
        initial={{ opacity: 0, y: 12, rotate: -2 }}
        animate={{ opacity: 1, y: 0, rotate: -1.2 }}
        transition={{ type: "spring", stiffness: 120, damping: 14 }}
        className="nb-card w-full max-w-sm p-7 relative"
      >

        <div className="flex flex-col items-center text-center mb-5">
          <div style={{ color: "var(--margin-red)" }}>
            <BigFlaskDoodle />
          </div>
          <h1
            className="font-display font-bold mt-2"
            style={{ fontSize: "40px", color: "var(--ink)" }}
          >
            lab wizard
          </h1>
          <p
            className="font-body text-sm mt-1"
            style={{ color: "var(--ink-muted)" }}
          >
            your chemistry lab notebook
          </p>
        </div>

        <form onSubmit={submit} className="flex flex-col gap-4">
          {mode === "signup" && (
            <RuledInput
              label="your name"
              name="name"
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="Ms. Reyes"
              autoComplete="name"
            />
          )}
          <RuledInput
            label="email"
            name="email"
            type="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            placeholder="you@school.edu"
            autoComplete="email"
          />
          <RuledInput
            label="password"
            name="password"
            type="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            placeholder="••••••"
            autoComplete={mode === "signin" ? "current-password" : "new-password"}
          />

          {error && (
            <p
              className="font-display text-lg font-semibold"
              style={{ color: "var(--margin-red)" }}
            >
              {error}
            </p>
          )}

          <div className="flex items-center justify-between mt-2">
            <button
              type="button"
              onClick={() => {
                setMode(mode === "signin" ? "signup" : "signin");
                setError(null);
              }}
              className="font-body text-sm underline"
              style={{ color: "var(--ink-muted)", textUnderlineOffset: "3px" }}
            >
              {mode === "signin" ? "need an account?" : "have one already?"}
            </button>
            <CircledButton type="submit" disabled={busy}>
              {busy ? "…" : mode === "signin" ? "sign in" : "sign up"}
            </CircledButton>
          </div>
        </form>

        <p
          className="font-body text-xs text-center mt-5"
          style={{ color: "var(--ink-muted)" }}
        >
          {usingSupabase
            ? "sign in with your email + password."
            : "demo mode — any email + password works. data is saved in your browser."}
        </p>
      </motion.div>
    </div>
  );
}
