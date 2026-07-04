# Lab Wizard — Supabase Setup Guide

This app works in two modes:

1. **Mock mode** (default) — data is stored in your browser's localStorage. Any email + password works. Good for demos.
2. **Supabase mode** — real auth + database. Multi-device sync. Set up by following this guide.

---

## Step 1 — Create a Supabase project

1. Go to [supabase.com](https://supabase.com) and sign in (free tier is fine)
2. Click **New Project** → name it `lab-wizard` → choose a region → set a database password
3. Wait ~2 minutes for provisioning to finish

## Step 2 — Run the SQL schema

1. In your Supabase dashboard, go to **SQL Editor** → **New query**
2. Open the file `supabase-schema.sql` from this project
3. Copy the entire contents, paste into the SQL editor
4. Click **Run** — this creates the `chemicals`, `apparatus`, and `consumption_logs` tables, indexes, and Row Level Security policies (each user can only see their own rows)

## Step 3 — Get your API keys

1. In Supabase dashboard, go to **Settings** → **API**
2. Copy:
   - **Project URL** — looks like `https://abcdefghijklm.supabase.co`
   - **anon public key** — a long JWT string

## Step 4 — Add env vars to your deployment

### Local development
Create a `.env.local` file in the project root:
```bash
NEXT_PUBLIC_SUPABASE_URL=https://your-project.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=your-anon-key-here
```

### Vercel deployment
1. Push the project to GitHub
2. Import into Vercel
3. In Vercel → Settings → Environment Variables, add:
   - `NEXT_PUBLIC_SUPABASE_URL`
   - `NEXT_PUBLIC_SUPABASE_ANON_KEY`
4. Redeploy

## Step 5 — Create users

Users can sign up directly in the app (the sign-up form creates a real Supabase Auth user), OR you can pre-create users in the Supabase dashboard:
- Go to **Authentication** → **Users** → **Add user**
- Enter email + password

## Step 6 — Test

1. Open the app — the auth screen now says "sign in with your email + password" instead of "demo mode"
2. Sign in with a real user
3. Add chemicals, consume, restock — data now persists to Supabase
4. Sign in on another device/browser — your data is there

---

## How it works

- **`src/lib/supabase.ts`** — creates the Supabase client from env vars. Returns `null` if not configured (triggers mock mode).
- **`src/lib/store.ts`** — Zustand store. Every method checks `getSupabase()`:
  - If configured → writes to Supabase (auth, tables, RLS)
  - If not configured → falls back to localStorage
- **Row Level Security** — every table has `user_id` and RLS policies that restrict access to the current user's rows only. Users can never see each other's data.
- **Session restore** — on app mount, `restoreSession()` checks for an existing Supabase session and loads data if found.

## Troubleshooting

**"Sign in failed" / "Invalid credentials"**
- For Supabase mode, the user must exist in Supabase Auth. Create them via sign-up or the dashboard.

**Data not loading after sign-in**
- Check the browser console for RLS errors. Make sure you ran the SQL schema including the RLS policies.

**Camera/scan not working**
- Camera requires HTTPS. Vercel provides this automatically. For local testing, use `localhost` (Chrome allows camera on localhost).

**Want to switch back to mock mode**
- Delete or rename `.env.local` — the app automatically falls back to localStorage.
