-- =====================================================================
-- 08-ubah-aging.sql -- Admin boleh mengubah tanggal mulai aging
--
-- Alasan: data sering baru diinput ke web beberapa hari setelah
-- komponen berganti status, jadi aging hitungan otomatis terlalu muda.
-- Admin mengisi tanggal yang benar lewat tombol edit di baris stok.
--
-- Isi:
--   1. ubah_aging_part : khusus admin, ganti stok.aging_sejak satu baris
--
-- Tidak mengubah tabel. Trigger reset aging (04-aging.sql) tetap jalan:
-- web menyimpan status dulu, baru tanggal aging, jadi tanggal yang diisi
-- admin tidak tertimpa reset.
-- Aman dijalankan lebih dari sekali. Jalankan SETELAH 04-aging.sql.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. ubah_aging_part: tanggal dari admin disimpan sebagai jam 00:00 WIB.
--    Tidak tercatat di riwayat (sama seperti koreksi WO / Edit data).
-- ---------------------------------------------------------------------
create or replace function public.ubah_aging_part(p_id uuid, p_tanggal date)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_hari_ini date := (now() at time zone 'Asia/Jakarta')::date;
begin
  if not public.is_admin() then
    raise exception 'Hanya admin yang boleh mengubah aging';
  end if;
  if p_tanggal is null then
    raise exception 'Tanggal aging wajib diisi';
  end if;
  if p_tanggal > v_hari_ini then
    raise exception 'Tanggal aging tidak boleh lewat dari hari ini';
  end if;

  update stok
  set aging_sejak = p_tanggal::timestamp at time zone 'Asia/Jakarta',
      updated_at = now()
  where id = p_id;

  if not found then
    raise exception 'Baris stok tidak ditemukan';
  end if;
end;
$$;

revoke execute on function public.ubah_aging_part(uuid, date) from public, anon;
grant execute on function public.ubah_aging_part(uuid, date) to authenticated;
