-- 07-lokasi-tampil.sql
-- Part di lokasi berikut tampil di cetok-online.
--   1. Fungsi trigger sync_stok_is_filtered (trigger trg_stok_is_filtered):
--      daftar lokasi ditambah LEMARI HIJAU, LEMARI PLANNER, VENDOR.
--      Part baru / pindah lokasi otomatis ikut aturan ini.
--   2. Update: part yang sudah ada di lokasi tersebut langsung tampil.

create or replace function public.sync_stok_is_filtered()
returns trigger
language plpgsql
as $function$
begin
  NEW.is_filtered := not (
    upper(trim(coalesce(NEW.lokasi, ''))) = any (array[
      'FABRIKASI',
      'LAYDOWN',
      'LEMARI HIJAU',
      'LEMARI PLANNER',
      'LOGISTIK',
      'TRACKINDO',
      'VENDOR'
    ])
  );
  return NEW;
end;
$function$;

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
