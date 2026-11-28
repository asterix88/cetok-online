-- 08-trigger-lokasi-tampil.sql
-- Trigger is_filtered: part di lokasi berikut otomatis tampil di cetok-online,
-- termasuk part baru atau part yang lokasinya diubah.
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
