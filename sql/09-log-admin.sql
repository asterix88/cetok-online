-- =====================================================================
-- 09-log-admin.sql -- Log perubahan yang dilakukan admin
--
-- Yang dicatat (hanya lewat fungsi admin di web):
--   edit_stok     update_part      (Edit baris stok)
--   ubah_wo       ubah_wo_part     (Ubah WO)
--   ubah_aging    ubah_aging_part  (Ubah tanggal aging, dari 08-ubah-aging.sql)
--   hapus_part    delete_part      (Hapus part)
--   edit_riwayat  update_riwayat   (Edit riwayat)
-- Reset PIN dan tambah akun TIDAK dicatat.
--
-- Cara kerja:
--   1. Setiap fungsi admin di atas memberi tanda "aksi admin" selama
--      transaksinya berjalan (set_config cetok.aksi_admin).
--   2. Trigger di tabel stok dan riwayat membaca tanda itu. Kalau ada,
--      kolom yang berubah (lama -> baru) disimpan ke tabel log_admin.
--      Ambil / Transfer / Input biasa tidak memberi tanda, jadi tidak
--      ikut tercatat walaupun dilakukan oleh admin.
--   3. Web membaca log lewat get_log_admin (khusus admin).
--
-- Isi:
--   1. Tabel log_admin (tidak bisa diubah atau dihapus)
--   2. Fungsi bantu ringkas_stok, ringkas_riwayat, beda_kolom, catat_log_admin
--   3. Trigger di stok dan riwayat
--   4. Tanda aksi admin di fungsi admin yang sudah ada
--   5. get_log_admin (dibaca web)
--
-- Aman dijalankan lebih dari sekali. Jalankan SETELAH 01 dan 03.
-- Kalau 08-ubah-aging.sql baru dijalankan belakangan, jalankan file ini
-- sekali lagi supaya Ubah Aging juga tercatat.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. TABEL log_admin
-- ---------------------------------------------------------------------
-- perubahan: daftar kolom yang berubah, contoh
--   [{"kolom":"qty","lama":"4","baru":"6"}, {"kolom":"loc","lama":"RAK A-03","baru":"RAK A-05"}]
-- Untuk hapus_part, "baru" selalu kosong (isi baris sebelum dihapus).
create table if not exists public.log_admin (
  id         bigint generated always as identity primary key,
  waktu      timestamptz not null default now(),
  nrp        text,
  nama       text,
  aksi       text not null,
  tabel      text not null,
  data_id    uuid,
  unit       text,
  pn         text,
  deskripsi  text,
  perubahan  jsonb not null
);

create index if not exists log_admin_waktu_idx on public.log_admin (waktu desc);

-- Tidak ada akses langsung dari web; hanya lewat get_log_admin.
alter table public.log_admin enable row level security;
revoke all on public.log_admin from anon, authenticated;

-- Log tidak boleh diubah atau dihapus, termasuk dari SQL Editor.
create or replace function public.tolak_ubah_log_admin()
returns trigger
language plpgsql
as $$
begin
  raise exception 'Log admin tidak boleh diubah atau dihapus';
end;
$$;

drop trigger if exists trg_log_admin_kunci on public.log_admin;
create trigger trg_log_admin_kunci
  before update or delete on public.log_admin
  for each row execute function public.tolak_ubah_log_admin();


-- ---------------------------------------------------------------------
-- 2. FUNGSI BANTU
-- ---------------------------------------------------------------------

-- Kolom stok yang dicatat, dengan nama pendek yang dipakai web.
-- Aging disimpan sebagai tanggal WIB (dd/mm/yyyy), bukan jam.
create or replace function public.ringkas_stok(r public.stok)
returns jsonb
language sql
stable
as $$
  select jsonb_build_object(
    'unit',    r.unit_model,
    'pn',      r.parts_number,
    'desc',    r.parts_description,
    'loc',     r.lokasi,
    'qty',     r.quantity,
    'status',  r.status_rfu,
    'remarks', r.remarks,
    'wo',      r.wo,
    'aging',   to_char(r.aging_sejak at time zone 'Asia/Jakarta', 'DD/MM/YYYY')
  );
$$;

-- Kolom riwayat yang bisa diedit admin.
create or replace function public.ringkas_riwayat(r public.riwayat)
returns jsonb
language sql
stable
as $$
  select jsonb_build_object(
    'unit', r.unit_model,
    'pn',   r.parts_number,
    'desc', r.parts_description,
    'note', r.keterangan,
    'nama', r.nama
  );
$$;

-- Bandingkan dua ringkasan, urut sesuai p_kolom.
-- Hasil: [{"kolom":..., "lama":..., "baru":...}] hanya untuk yang berbeda.
-- p_baru null = baris dihapus: semua kolom yang berisi ikut dicatat.
create or replace function public.beda_kolom(p_lama jsonb, p_baru jsonb, p_kolom text[])
returns jsonb
language sql
immutable
as $$
  select coalesce(jsonb_agg(
           jsonb_build_object('kolom', k, 'lama', p_lama -> k, 'baru', p_baru -> k)
           order by urutan), '[]'::jsonb)
  from unnest(p_kolom) with ordinality as daftar(k, urutan)
  where case
          when p_baru is null then coalesce(p_lama ->> k, '') <> ''
          else (p_lama -> k) is distinct from (p_baru -> k)
        end;
$$;

-- Tulis satu baris log atas nama admin yang sedang login.
create or replace function public.catat_log_admin(
  p_aksi text, p_tabel text, p_id uuid, p_ringkas jsonb, p_perubahan jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if jsonb_array_length(p_perubahan) = 0 then
    return;  -- disimpan tanpa ada yang berubah: tidak perlu dicatat
  end if;

  insert into log_admin (nrp, nama, aksi, tabel, data_id, unit, pn, deskripsi, perubahan)
  select k.nrp, k.nama, p_aksi, p_tabel, p_id,
         p_ringkas ->> 'unit', p_ringkas ->> 'pn', p_ringkas ->> 'desc', p_perubahan
  from (select 1) satu
  left join karyawan k on k.user_id = auth.uid();
end;
$$;


-- ---------------------------------------------------------------------
-- 3. TRIGGER DI STOK DAN RIWAYAT
-- ---------------------------------------------------------------------
-- Hanya mencatat kalau ada tanda aksi admin (lihat bagian 4).

create or replace function public.log_admin_stok()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_aksi  text := nullif(current_setting('cetok.aksi_admin', true), '');
  v_kolom text[] := array['unit', 'pn', 'desc', 'loc', 'qty', 'status', 'remarks', 'wo', 'aging'];
  -- Saat hapus, unit/PN/deskripsi sudah tampil di judul kartu
  v_kolom_hapus text[] := array['loc', 'qty', 'status', 'remarks', 'wo', 'aging'];
begin
  if v_aksi is null then
    return null;
  end if;

  if tg_op = 'DELETE' then
    perform catat_log_admin(v_aksi, 'stok', old.id, ringkas_stok(old),
                            beda_kolom(ringkas_stok(old), null, v_kolom_hapus));
  else
    perform catat_log_admin(v_aksi, 'stok', new.id, ringkas_stok(new),
                            beda_kolom(ringkas_stok(old), ringkas_stok(new), v_kolom));
  end if;
  return null;
end;
$$;

drop trigger if exists trg_log_admin_stok on public.stok;
create trigger trg_log_admin_stok
  after update or delete on public.stok
  for each row execute function public.log_admin_stok();


create or replace function public.log_admin_riwayat()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_aksi  text := nullif(current_setting('cetok.aksi_admin', true), '');
  v_kolom text[] := array['unit', 'pn', 'desc', 'note', 'nama'];
begin
  if v_aksi is null then
    return null;
  end if;

  perform catat_log_admin(v_aksi, 'riwayat', new.id, ringkas_riwayat(new),
                          beda_kolom(ringkas_riwayat(old), ringkas_riwayat(new), v_kolom));
  return null;
end;
$$;

drop trigger if exists trg_log_admin_riwayat on public.riwayat;
create trigger trg_log_admin_riwayat
  after update on public.riwayat
  for each row execute function public.log_admin_riwayat();


-- ---------------------------------------------------------------------
-- 4. TANDA AKSI ADMIN DI FUNGSI YANG SUDAH ADA
-- ---------------------------------------------------------------------
-- Supaya isi fungsi di database tidak berubah, blok ini mengambil
-- definisi yang sekarang dan hanya menambah satu baris sebelum
-- pengecekan admin:
--     perform set_config('cetok.aksi_admin', '<aksi>', true);
--     if not public.is_admin() then
-- Tanda (true = lokal) hilang sendiri saat transaksi selesai.
-- Fungsi yang belum ada (mis. 08 belum dijalankan) dilewati dengan pesan.
do $$
declare
  v_pasangan  text[][] := array[
    array['update_part',     'edit_stok'],
    array['ubah_wo_part',    'ubah_wo'],
    array['ubah_aging_part', 'ubah_aging'],
    array['delete_part',     'hapus_part'],
    array['update_riwayat',  'edit_riwayat']
  ];
  v_cek   text := 'if not public.is_admin() then';
  v_fungsi text;
  v_aksi  text;
  v_def   text;
  v_ada   boolean;
begin
  for i in 1 .. array_length(v_pasangan, 1) loop
    v_fungsi := v_pasangan[i][1];
    v_aksi   := v_pasangan[i][2];
    v_ada    := false;

    for v_def in
      select pg_get_functiondef(p.oid)
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = v_fungsi
    loop
      v_ada := true;
      if position('cetok.aksi_admin' in v_def) > 0 then
        continue;  -- sudah diberi tanda sebelumnya
      end if;
      if position(v_cek in v_def) = 0 then
        raise exception 'Fungsi % tidak punya baris "%". Cek manual.', v_fungsi, v_cek;
      end if;
      execute replace(v_def, v_cek,
        format('perform set_config(%L, %L, true);', 'cetok.aksi_admin', v_aksi)
        || E'\n  ' || v_cek);
    end loop;

    if not v_ada then
      raise notice 'Fungsi % belum ada, dilewati. Jalankan file ini lagi setelah fungsinya dibuat.', v_fungsi;
    end if;
  end loop;
end;
$$;


-- ---------------------------------------------------------------------
-- 5. get_log_admin: satu halaman log, terbaru di atas (khusus admin)
-- ---------------------------------------------------------------------
-- p_dari / p_sampai : tanggal WIB, boleh kosong
-- p_nrp             : NRP admin, boleh kosong (= semua admin)
-- Hasil: { rows: [...], total: n, admin: [{nrp, nama}] }
create or replace function public.get_log_admin(
  p_page      integer default 1,
  p_page_size integer default 20,
  p_dari      date    default null,
  p_sampai    date    default null,
  p_nrp       text    default null
)
returns json
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_hasil json;
begin
  if not public.is_admin() then
    raise exception 'Hanya admin yang boleh melihat log';
  end if;

  with terpilih as (
    select *
    from log_admin
    where (p_dari   is null or (waktu at time zone 'Asia/Jakarta')::date >= p_dari)
      and (p_sampai is null or (waktu at time zone 'Asia/Jakarta')::date <= p_sampai)
      and (p_nrp    is null or nrp = p_nrp)
  )
  select json_build_object(
    'rows', coalesce((
      select json_agg(json_build_object(
               'id', id, 'waktu', waktu, 'nrp', nrp, 'nama', nama, 'aksi', aksi,
               'unit', unit, 'pn', pn, 'desc', deskripsi, 'perubahan', perubahan
             ) order by waktu desc)
      from (
        select * from terpilih
        order by waktu desc
        limit p_page_size offset (greatest(p_page, 1) - 1) * p_page_size
      ) halaman
    ), '[]'::json),
    'total', (select count(*) from terpilih),
    'admin', coalesce((
      select json_agg(json_build_object('nrp', nrp, 'nama', nama) order by nama)
      from (select distinct nrp, nama from log_admin where nrp is not null) a
    ), '[]'::json)
  ) into v_hasil;

  return v_hasil;
end;
$$;


-- ---------------------------------------------------------------------
-- 6. HAK AKSES FUNGSI
-- ---------------------------------------------------------------------
revoke execute on function public.get_log_admin(integer, integer, date, date, text) from public, anon;
grant  execute on function public.get_log_admin(integer, integer, date, date, text) to authenticated;

-- Fungsi bantu tidak dipanggil dari web.
revoke execute on function
  public.catat_log_admin(text, text, uuid, jsonb, jsonb),
  public.ringkas_stok(public.stok),
  public.ringkas_riwayat(public.riwayat),
  public.beda_kolom(jsonb, jsonb, text[])
from public, anon, authenticated;
