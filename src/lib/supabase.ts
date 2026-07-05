"use client";

// Supabase client — reads from env vars.
// Returns null if not configured, so the store can fall back to mock mode.

import { createClient, type SupabaseClient } from "@supabase/supabase-js";

let cached: SupabaseClient | null = null;
let checked = false;

export function getSupabase(): SupabaseClient | null {
  if (checked) return cached;
  checked = true;

  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

  if (!url || !anonKey || url === "your-supabase-url" || anonKey === "your-anon-key") {
    // Not configured — app runs in mock/localStorage mode
    return null;
  }

  try {
    cached = createClient(url, anonKey, {
      auth: {
        persistSession: true,
        autoRefreshToken: true,
        detectSessionInUrl: true,
      },
    });
    return cached;
  } catch {
    return null;
  }
}

export function isSupabaseConfigured(): boolean {
  return getSupabase() !== null;
}
