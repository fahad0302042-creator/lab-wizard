"use client";

// Supabase client — uses hardcoded PUBLIC values.
// These are safe to expose client-side (that's what NEXT_PUBLIC_ means).
// The anon key only allows row-level-security-protected access.

import { createClient, type SupabaseClient } from "@supabase/supabase-js";

// Hardcoded values — the app always connects to this Supabase project.
// These are public values (anon key), safe to include in client-side code.
const SUPABASE_URL = "https://gfutwkckawfzfiqbcdks.supabase.co";
const SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImdmdXR3a2NrYXdmemZpcWJjZGtzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODMyMTM2ODgsImV4cCI6MjA5ODc4OTY4OH0.pXr7HYOCno9iVtscPqxfrH8Pk1LXzayJiDCq6tkNF5M";

let cached: SupabaseClient | null = null;

export function getSupabase(): SupabaseClient | null {
  if (cached) return cached;

  try {
    cached = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
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

// Export the values for other modules that need them
export const SUPABASE_CONFIG = {
  url: SUPABASE_URL,
  anonKey: SUPABASE_ANON_KEY,
};
