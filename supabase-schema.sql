-- Lab Wizard — Supabase schema
-- Run this in the Supabase SQL Editor (Dashboard → SQL → New query)
-- Creates tables, indexes, and Row Level Security policies.

-- =============================================================================
-- TABLES
-- =============================================================================

-- Chemicals (reagents with QR codes)
create table if not exists public.chemicals (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  formula text not null default '',
  unit text not null default 'mL',
  quantity numeric not null default 0,
  initial_quantity numeric not null default 0,
  notes text not null default '',
  qr_code text not null default gen_random_uuid(),
  created_at timestamptz not null default now()
);

-- Apparatus (no QR codes, no condition — quantity + breakage log only)
create table if not exists public.apparatus (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  category text not null default 'other',
  quantity numeric not null default 0,
  initial_quantity numeric not null default 0,
  notes text not null default '',
  created_at timestamptz not null default now()
);

-- Consumption / restock / breakage logs
create table if not exists public.consumption_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  item_id uuid not null,
  item_type text not null check (item_type in ('chemical', 'apparatus')),
  action text not null check (action in ('consume', 'restock', 'breakage')),
  amount numeric not null default 0,
  note text not null default '',
  logged_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

-- =============================================================================
-- INDEXES
-- =============================================================================

create index if not exists idx_chemicals_user on public.chemicals(user_id);
create index if not exists idx_apparatus_user on public.apparatus(user_id);
create index if not exists idx_logs_user on public.consumption_logs(user_id);
create index if not exists idx_logs_user_month on public.consumption_logs(user_id, (logged_at::date));
create index if not exists idx_logs_item on public.consumption_logs(item_id);

-- =============================================================================
-- ROW LEVEL SECURITY
-- Each user can only see & modify their own rows.
-- =============================================================================

alter table public.chemicals enable row level security;
alter table public.apparatus enable row level security;
alter table public.consumption_logs enable row level security;

-- Chemicals policies
drop policy if exists "chemicals_select_own" on public.chemicals;
create policy "chemicals_select_own" on public.chemicals
  for select using (auth.uid() = user_id);

drop policy if exists "chemicals_insert_own" on public.chemicals;
create policy "chemicals_insert_own" on public.chemicals
  for insert with check (auth.uid() = user_id);

drop policy if exists "chemicals_update_own" on public.chemicals;
create policy "chemicals_update_own" on public.chemicals
  for update using (auth.uid() = user_id);

drop policy if exists "chemicals_delete_own" on public.chemicals;
create policy "chemicals_delete_own" on public.chemicals
  for delete using (auth.uid() = user_id);

-- Apparatus policies
drop policy if exists "apparatus_select_own" on public.apparatus;
create policy "apparatus_select_own" on public.apparatus
  for select using (auth.uid() = user_id);

drop policy if exists "apparatus_insert_own" on public.apparatus;
create policy "apparatus_insert_own" on public.apparatus
  for insert with check (auth.uid() = user_id);

drop policy if exists "apparatus_update_own" on public.apparatus;
create policy "apparatus_update_own" on public.apparatus
  for update using (auth.uid() = user_id);

drop policy if exists "apparatus_delete_own" on public.apparatus;
create policy "apparatus_delete_own" on public.apparatus
  for delete using (auth.uid() = user_id);

-- Consumption logs policies
drop policy if exists "logs_select_own" on public.consumption_logs;
create policy "logs_select_own" on public.consumption_logs
  for select using (auth.uid() = user_id);

drop policy if exists "logs_insert_own" on public.consumption_logs;
create policy "logs_insert_own" on public.consumption_logs
  for insert with check (auth.uid() = user_id);

drop policy if exists "logs_update_own" on public.consumption_logs;
create policy "logs_update_own" on public.consumption_logs
  for update using (auth.uid() = user_id);

drop policy if exists "logs_delete_own" on public.consumption_logs;
create policy "logs_delete_own" on public.consumption_logs
  for delete using (auth.uid() = user_id);

-- =============================================================================
-- DONE
-- After running this, create a user in Auth → Users (or via the app's sign-up),
-- then set NEXT_PUBLIC_SUPABASE_URL and NEXT_PUBLIC_SUPABASE_ANON_KEY in .env
-- =============================================================================
