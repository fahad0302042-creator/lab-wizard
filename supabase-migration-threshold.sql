-- Lab Wizard — Add low_stock_threshold column
-- Run this in Supabase SQL Editor to add the low-stock threshold column
-- to your existing chemicals and apparatus tables.

-- Add low_stock_threshold to chemicals (default 0 = not set)
alter table public.chemicals
  add column if not exists low_stock_threshold numeric not null default 0;

-- Add low_stock_threshold to apparatus (default 0 = not set)
alter table public.apparatus
  add column if not exists low_stock_threshold numeric not null default 0;

-- Done! Existing items will have low_stock_threshold = 0 (not set).
-- You can set thresholds per-item via the Edit screen in the app.
