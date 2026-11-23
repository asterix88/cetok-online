-- =====================================================================
-- 01-login-nrp.sql
-- Login dengan NRP untuk web Cetok Online (Stock Component TRACK).
--
-- Jalankan SEKALI di: Supabase Dashboard > SQL Editor > New query.
-- Aman dijalankan ulang (pakai "if not exists" / "create or replace").
--
-- Isi file ini:
--   1. Tabel karyawan
--   2. Fungsi bantu: is_admin, profil_saya, selesai_ganti_password
--   3. Fungsi kelola akun (dipakai dari SQL Editor):
--        buat_akun_karyawan, reset_password_karyawan
--   4. Fungsi admin lama (update_part, delete_part, update_riwayat)
--      sekarang hanya boleh dipakai karyawan dengan admin = 'ya'
--
-- Catatan password:
--   Supabase mewajibkan password minimal 6 karakter, sedangkan password
--   awal kita 0000 (4 karakter). Jadi web menambahkan awalan "cetok-"
--   sebelum dikirim ke Supabase (0000 -> cetok-0000). Karyawan tetap
--   mengetik 0000. Awalan yang sama dipakai di auth.js (PASSWORD_PREFIX)
--   dan di fungsi buat/reset di bawah. Kalau diganti, ganti di keduanya.
--
-- WA bot v2 TIDAK terpengaruh: fungsi input_barang, ambil_barang,
-- transfer_stok, get_all_data, get_riwayat_page tidak diubah.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. TABEL KARYAWAN
-- ---------------------------------------------------------------------
-- Satu baris = satu karyawan yang boleh masuk ke web.
--   nrp                  : nomor karyawan, dipakai untuk login
--   nama                 : otomatis mengisi kolom nama di Ambil/Transfer/Input
--   admin                : isi 'ya' kalau admin, selain itu kosongkan
--   departemen, jabatan  : info saja (tidak dipakai untuk hak akses)
--   wajib_ganti_password : true = harus ganti password saat masuk berikutnya
--   aktif                : false = tidak bisa masuk lagi (tanpa hapus data)
--   user_id              : akun login di Supabase Auth (diisi otomatis)
create table if not exists public.karyawan (
  nrp                  text primary key check (nrp ~ '^[0-9]+$'),
  nama                 text not null,
  admin                text,
  departemen           text,
  jabatan              text,
  wajib_ganti_password boolean not null default true,
  aktif                boolean not null default true,
  user_id              uuid unique references auth.users (id) on delete set null,
  created_at           timestamptz not null default now()
);

-- Data karyawan hanya dibaca lewat fungsi di bawah, tidak langsung dari web.
alter table public.karyawan enable row level security;
revoke all on public.karyawan from anon, authenticated;


-- ---------------------------------------------------------------------
-- 2. FUNGSI BANTU (dipanggil dari web)
-- ---------------------------------------------------------------------

-- Apakah yang sedang login adalah admin aktif?
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from karyawan
    where user_id = auth.uid()
      and aktif
      and lower(trim(coalesce(admin, ''))) = 'ya'
  );
$$;

-- Data karyawan yang sedang login (untuk header, nama otomatis, dll).
-- Hasil kosong (null) = akun ini tidak terdaftar / sudah tidak aktif.
create or replace function public.profil_saya()
returns json
language sql
stable
security definer
set search_path = public
as $$
  select json_build_object(
    'nrp',                  nrp,
    'nama',                 nama,
    'admin',                lower(trim(coalesce(admin, ''))) = 'ya',
    'wajib_ganti_password', wajib_ganti_password
  )
  from karyawan
  where user_id = auth.uid() and aktif;
$$;

-- Dipanggil web setelah karyawan berhasil mengganti password awal.
create or replace function public.selesai_ganti_password()
returns void
language sql
security definer
set search_path = public
as $$
  update karyawan set wajib_ganti_password = false where user_id = auth.uid();
$$;


-- ---------------------------------------------------------------------
-- 3. KELOLA AKUN (jalankan dari SQL Editor)
-- ---------------------------------------------------------------------
-- Contoh pemakaian:
--   select public.buat_akun_karyawan('12345678', 'BUDI SANTOSO', 'ya', 'PLANT', 'PLANNER');  -- admin
--   select public.buat_akun_karyawan('10458821', 'AGUS RIYADI', null, 'PLANT', 'MEKANIK');   -- karyawan
--   select public.reset_password_karyawan('10458821');                   -- lupa password
--   update public.karyawan set aktif = false where nrp = '10458821';     -- nonaktifkan
--   update public.karyawan set admin = 'ya'  where nrp = '10458821';     -- jadikan admin

-- Buat akun login baru dengan password awal 0000.
create or replace function public.buat_akun_karyawan(
  p_nrp   text,
  p_nama       text,
  p_admin      text default null,
  p_departemen text default null,
  p_jabatan    text default null
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_nrp     text := trim(p_nrp);
  v_email   text := trim(p_nrp) || '@cetok.local';
  v_user_id uuid := gen_random_uuid();
begin
  -- Dari web, hanya admin yang boleh. Dari SQL Editor (tanpa login) boleh.
  if auth.uid() is not null and not public.is_admin() then
    raise exception 'Unauthorized: fitur ini khusus admin';
  end if;
  if exists (select 1 from karyawan where nrp = v_nrp) then
    raise exception 'NRP % sudah terdaftar', v_nrp;
  end if;

  -- Akun login di Supabase Auth (langsung aktif, tanpa konfirmasi email)
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at,
    confirmation_token, email_change, email_change_token_new, recovery_token
  ) values (
    '00000000-0000-0000-0000-000000000000', v_user_id, 'authenticated', 'authenticated',
    v_email, crypt('cetok-0000', gen_salt('bf')),
    now(), '{"provider":"email","providers":["email"]}', '{}',
    now(), now(),
    '', '', '', ''
  );

  insert into auth.identities (
    id, user_id, provider_id, identity_data, provider, created_at, updated_at
  ) values (
    gen_random_uuid(), v_user_id, v_user_id::text,
    jsonb_build_object('sub', v_user_id::text, 'email', v_email, 'email_verified', true),
    'email', now(), now()
  );

  insert into karyawan (nrp, nama, admin, departemen, jabatan, user_id)
  values (
    v_nrp,
    trim(p_nama),
    nullif(trim(coalesce(p_admin, '')), ''),
    nullif(trim(coalesce(p_departemen, '')), ''),
    nullif(trim(coalesce(p_jabatan, '')), ''),
    v_user_id
  );
end;
$$;

-- Kembalikan password ke 0000 dan wajibkan ganti saat masuk berikutnya.
create or replace function public.reset_password_karyawan(p_nrp text)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_user_id uuid;
begin
  if auth.uid() is not null and not public.is_admin() then
    raise exception 'Unauthorized: fitur ini khusus admin';
  end if;

  select user_id into v_user_id from karyawan where nrp = trim(p_nrp);
  if v_user_id is null then
    raise exception 'NRP % tidak ditemukan', p_nrp;
  end if;

  update auth.users
  set encrypted_password = crypt('cetok-0000', gen_salt('bf')),
      updated_at = now()
  where id = v_user_id;

  update karyawan set wajib_ganti_password = true where nrp = trim(p_nrp);
end;
$$;


-- ---------------------------------------------------------------------
-- 4. FUNGSI ADMIN: sekarang cek kolom admin, bukan sekadar "sudah login"
-- ---------------------------------------------------------------------
-- Sebelumnya cukup login (akun admin bersama). Sekarang semua karyawan
-- login, jadi fungsi ini harus memeriksa admin = 'ya'.
-- Isi fungsi selain baris pengecekan admin SAMA dengan versi sebelumnya.

create or replace function public.update_part(
  p_id      uuid,
  p_unit    text,
  p_pn      text,
  p_desc    text,
  p_loc     text,
  p_qty     integer,
  p_status  text,
  p_remarks text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status text;
begin
  if not public.is_admin() then
    raise exception 'Unauthorized: fitur ini khusus admin';
  end if;
  if p_unit is null or trim(p_unit) = '' then
    raise exception 'Unit model wajib diisi';
  end if;
  if p_pn is null or trim(p_pn) = '' or p_desc is null or trim(p_desc) = '' then
    raise exception 'Parts Number dan Description wajib diisi';
  end if;
  if p_qty is null or p_qty < 0 then
    raise exception 'Quantity tidak boleh minus';
  end if;

  v_status := case when p_qty = 0 then null
                   else coalesce(nullif(upper(trim(p_status)), ''), 'RFU') end;

  update stok
  set unit_model        = trim(p_unit),
      parts_number      = upper(trim(p_pn)),
      parts_description = upper(trim(p_desc)),
      lokasi            = upper(nullif(trim(p_loc), '')),
      quantity          = p_qty,
      status_rfu        = v_status,
      remarks           = upper(nullif(trim(p_remarks), '')),
      updated_at        = now()
  where id = p_id;

  if not found then
    raise exception 'Part tidak ditemukan';
  end if;
exception
  when unique_violation then
    raise exception 'Sudah ada part yang sama di lokasi dan status ini. Pakai Transfer atau gabungkan qty-nya.';
end;
$$;

create or replace function public.delete_part(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Unauthorized: fitur ini khusus admin';
  end if;

  delete from stok where id = p_id;
end;
$$;

create or replace function public.update_riwayat(
  p_id                uuid,
  p_unit_model        text,
  p_parts_number      text,
  p_parts_description text,
  p_keterangan        text,
  p_nama              text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Unauthorized: fitur ini khusus admin';
  end if;
  if p_nama is null or trim(p_nama) = '' then
    raise exception 'Nama wajib diisi';
  end if;

  update riwayat
  set unit_model        = coalesce(nullif(trim(p_unit_model), ''), unit_model),
      parts_number      = coalesce(upper(nullif(trim(p_parts_number), '')), parts_number),
      parts_description = coalesce(upper(nullif(trim(p_parts_description), '')), parts_description),
      keterangan        = upper(coalesce(trim(p_keterangan), '')),
      nama              = trim(p_nama)
  where id = p_id;

  if not found then
    raise exception 'Riwayat tidak ditemukan';
  end if;
end;
$$;


-- ---------------------------------------------------------------------
-- 5. HAK AKSES FUNGSI
-- ---------------------------------------------------------------------
-- Fungsi baru: hanya untuk yang sudah login. Pengunjung tanpa login
-- (anon) dan WA bot tidak bisa memanggilnya.
revoke execute on function
  public.is_admin(),
  public.profil_saya(),
  public.selesai_ganti_password(),
  public.buat_akun_karyawan(text, text, text, text, text),
  public.reset_password_karyawan(text)
from public, anon;

grant execute on function
  public.is_admin(),
  public.profil_saya(),
  public.selesai_ganti_password(),
  public.buat_akun_karyawan(text, text, text, text, text),
  public.reset_password_karyawan(text)
to authenticated;
