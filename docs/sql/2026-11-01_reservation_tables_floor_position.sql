-- 座位圖（老闆 2026-11-01）：在 Supabase SQL Editor 整段貼上執行一次即可（只加欄位、補資料，不刪任何東西）
-- ① 欄位：位置（pos_x／pos_y／w／h，已於 2026-11-01 加好）、桌形（shape：round 圓／square 方）、樓層（floor：1F／2F／3F）
alter table public.reservation_tables
  add column if not exists pos_x integer,
  add column if not exists pos_y integer,
  add column if not exists w integer not null default 1,
  add column if not exists h integer not null default 1,
  add column if not exists shape text not null default 'round',
  add column if not exists floor text not null default '1F';

-- ② 隱城二樓：照 iCHEF 2F 座位表（位置已於 2026-11-01 寫入；這裡補樓層與方桌）
update public.reservation_tables t set floor = '2F'
from public.stores s where s.id = t.store_id and s.name = '隱城' and t.name !~ '^S';
update public.reservation_tables t set shape = 'square'
from public.stores s where s.id = t.store_id and s.name = '隱城' and t.name in ('F1', 'A9', 'A10', 'A11', 'A12');

-- ③ 隱城一樓：照 iCHEF 1F 座位表 —— S5／S6／S7 一排在上、S1／S2 中間、S3／S4 下面；S5～S7 原本 App 沒有，補上
insert into public.reservation_tables (store_id, name, seats, combinable, sort, active, pos_x, pos_y, floor)
select s.id, v.name, 1, true, v.sort, true, v.x, v.y, '1F'
from public.stores s, (values ('S5', 65, 3, 0), ('S6', 66, 4, 0), ('S7', 67, 5, 0)) as v(name, sort, x, y)
where s.name = '隱城' and not exists (select 1 from public.reservation_tables t where t.store_id = s.id and t.name = v.name);
with pos(name, x, y) as (values ('S1', 3, 3), ('S2', 5, 3), ('S3', 3, 5), ('S4', 5, 5))
update public.reservation_tables t set pos_x = p.x, pos_y = p.y, floor = '1F'
from pos p, public.stores s where s.id = t.store_id and s.name = '隱城' and t.name = p.name;
