-- 07-lokasi-tampil.sql
-- Part di lokasi berikut tampil di cetok-online.
--   1. Trigger: part baru / pindah lokasi otomatis ikut aturan ini
--   2. Update: part yang sudah ada langsung tampil
--
-- Cek dulu nama trigger yang ada (hasil yang diharapkan: trg_set_is_filtered):
--   select tgname, tgfoid::regproc from pg_trigger
--   where tgrelid = 'public.stok'::regclass and not tgisinternal;

create or replace function public.set_is_filtered()
returns trigger
language plpgsql
as $$
begin
  new.is_filtered := upper(trim(coalesce(new.lokasi, ''))) not in (
    'FABRIKASI',
    'LAYDOWN',
    'LEMARI HIJAU',
    'LEMARI PLANNER',
    'LOGISTIK',
    'TRACKINDO',
    'VENDOR'
  );
  return new;
end;
$$;

drop trigger if exists trg_set_is_filtered on public.stok;
create trigger trg_set_is_filtered
  before insert or update of lokasi on public.stok
  for each row execute function public.set_is_filtered();

update public.stok
set is_filtered = false
where upper(trim(lokasi)) in (
  'FABRIKASI',
  'LAYDOWN',
  'LEMARI HIJAU',
  'LEMARI PLANNER',
  'LOGISTIK',
  'TRACKINDO',
  'VENDOR'
);
