-- 07-lokasi-tampil.sql
-- Tampilkan di cetok-online semua part di lokasi berikut.
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
