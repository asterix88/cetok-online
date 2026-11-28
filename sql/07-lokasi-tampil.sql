-- =====================================================================
-- 07-lokasi-tampil.sql
-- Lokasi yang part-nya TAMPIL di cetok-online.vercel.app (dan bot WA).
--
-- Aturan is_filtered (diisi trigger di tabel stok):
--   lokasi ada di daftar di bawah -> is_filtered = false (tampil)
--   lokasi lain                   -> is_filtered = true  (disembunyikan;
--                                    tetap tampil di stock-spareparts)
--
-- Sebelumnya hanya 4 lokasi: LOGISTIK, FABRIKASI, LAYDOWN, TRACKINDO.
-- Sekarang ditambah: LEMARI HIJAU, LEMARI PLANNER, VENDOR.
--
-- Isi file ini:
--   0. Cek trigger yang ada sekarang (jalankan dulu, lihat hasilnya)
--   1. Fungsi lokasi_tampil (daftar lokasi) + set_is_filtered (trigger)
--   2. Trigger dipasang ulang: jalan saat insert dan saat lokasi berubah
--   3. Semua baris stok yang sudah ada dihitung ulang
--
-- Mau tambah/kurangi lokasi nanti: ubah daftar di langkah 1a,
-- lalu jalankan ulang file ini. Aman dijalankan lebih dari sekali.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 0. Cek dulu (boleh dijalankan terpisah): trigger apa saja di tabel stok.
--    Yang diharapkan: trg_set_is_filtered -> set_is_filtered.
--    Kalau ada trigger is_filtered dengan NAMA LAIN, kabari dulu sebelum
--    lanjut, supaya tidak ada dua trigger yang saling menimpa.
--
--   select tgname, tgfoid::regproc as fungsi
--   from pg_trigger
--   where tgrelid = 'public.stok'::regclass and not tgisinternal;
-- ---------------------------------------------------------------------


-- ---------------------------------------------------------------------
-- 1a. lokasi_tampil: daftar lokasi yang tampil (cukup ubah di sini).
--     Huruf besar/kecil dan spasi di ujung diabaikan.
-- ---------------------------------------------------------------------
create or replace function public.lokasi_tampil(p_lokasi text)
returns boolean
language sql
immutable
as $$
  select upper(trim(coalesce(p_lokasi, ''))) in (
    'FABRIKASI',
    'LAYDOWN',
    'LEMARI HIJAU',
    'LEMARI PLANNER',
    'LOGISTIK',
    'TRACKINDO',
    'VENDOR'
  );
$$;


-- ---------------------------------------------------------------------
-- 1b. set_is_filtered: fungsi trigger, memakai daftar di atas
-- ---------------------------------------------------------------------
create or replace function public.set_is_filtered()
returns trigger
language plpgsql
as $$
begin
  new.is_filtered := not public.lokasi_tampil(new.lokasi);
  return new;
end;
$$;


-- ---------------------------------------------------------------------
-- 2. Trigger: dihitung ulang setiap part baru masuk atau lokasinya berubah
-- ---------------------------------------------------------------------
drop trigger if exists trg_set_is_filtered on public.stok;
create trigger trg_set_is_filtered
  before insert or update of lokasi on public.stok
  for each row execute function public.set_is_filtered();


-- ---------------------------------------------------------------------
-- 3. Hitung ulang semua baris yang sudah ada. Hanya kolom is_filtered
--    yang diubah, dan hanya baris yang memang berubah (urutan "Terbaru"
--    tidak ikut berubah).
-- ---------------------------------------------------------------------
update public.stok
set is_filtered = not public.lokasi_tampil(lokasi)
where is_filtered is distinct from (not public.lokasi_tampil(lokasi));


-- ---------------------------------------------------------------------
-- Cek hasil (boleh dijalankan terpisah): jumlah part per lokasi
--   select upper(lokasi) as lokasi, is_filtered, count(*)
--   from public.stok group by 1, 2 order by 1;
-- ---------------------------------------------------------------------
