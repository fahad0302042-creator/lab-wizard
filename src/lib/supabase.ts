"use client";

// Supabase client — reads from env vars first, falls back to hardcoded values.
// The anon key is safe to expose client-side (that's what NEXT_PUBLIC_ means).
// Returns null if neither env vars nor fallbacks are available.

import { createClient, type SupabaseClient } from "@supabase/supabase-js";

// Hardcoded fallback — used when Turbopack doesn't inline env vars correctly
// (happens in some sandbox/preview environments). These are PUBLIC values.
const FALLBACK_URL = "https://gfutwkckawfzfiqbcdks.supabase.co";
const FALLBACK_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImdmdXR3a2NrYXdmemZpcWJjZGtzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODMyMTM2ODgsImV4cCI6MjA5ODc4OTY4OH0.pXr7HYOCno9iVtscPqxfrH8Pk1LXzayJiDCq6tkNF5M";

let cached: SupabaseClient | null = null;
let checked = false;

export function getSupabase(): SupabaseClient | null {
  if (checked) return cached;
  checked = true;

  // Try env vars first, then fall back to hardcoded values
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL || FALLBACK_URL;
  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || FALLBACK_KEY;

  if (!url || !anonKey || url === "your-supabase-url" || anonKey === "your-anon-key") {
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
