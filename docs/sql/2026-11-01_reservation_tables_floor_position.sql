-- 座位圖（老闆 2026-11-01）：每張桌在平面圖上的格子位置與大小；pos_x／pos_y 為 null＝還沒排，App 照 sort 自動排
-- 在 Supabase SQL Editor 執行一次即可（只加欄位，不動既有資料）
alter table public.reservation_tables
  add column if not exists pos_x integer,
  add column if not exists pos_y integer,
  add column if not exists w integer not null default 1,
  add column if not exists h integer not null default 1;
