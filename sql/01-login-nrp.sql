-- =====================================================================
-- 01-login-nrp.sql
-- Login dengan NRP untuk web Cetok Online (Stock Component TRACK).
--
-- Jalankan SEKALI di: Supabase Dashboard > SQL Editor > New query.
-- Aman dijalankan ulang (pakai "if not exists" / "create or replace").
--
-- Isi file ini:
--   1. Tabel karyawan
--   2. Fungsi bantu: is_admin, profil_saya, selesai_ganti_pin
--   3. Fungsi kelola akun (dipakai dari SQL Editor):
--        buat_akun_karyawan, reset_pin_karyawan
--   4. Fungsi admin lama (update_part, delete_part, update_riwayat)
--      sekarang hanya boleh dipakai karyawan dengan admin = 'ya'
--
-- Catatan PIN:
--   Karyawan masuk dengan PIN 4 angka (awal 0000). Supabase mewajibkan
--   password minimal 6 karakter, jadi web menambahkan awalan "cetok-"
--   sebelum dikirim ke Supabase (PIN 0000 -> password cetok-0000).
--   Karyawan tetap mengetik 4 angka saja. Awalan yang sama dipakai di auth.js (PIN_PREFIX)
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
--   wajib_ganti_pin      : true = harus ganti PIN saat masuk berikutnya
--   aktif                : false = tidak bisa masuk lagi (tanpa hapus data)
--   user_id              : akun login di Supabase Auth (diisi otomatis)
create table if not exists public.karyawan (
  nrp                  text primary key check (nrp ~ '^[0-9]+$'),
  nama                 text not null,
  admin                text,
  departemen           text,
  jabatan              text,
  wajib_ganti_pin      boolean not null default true,
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
    'wajib_ganti_pin', wajib_ganti_pin
  )
  from karyawan
  where user_id = auth.uid() and aktif;
$$;

-- Dipanggil web setelah karyawan berhasil mengganti PIN awal.
create or replace function public.selesai_ganti_pin()
returns void
language sql
security definer
set search_path = public
as $$
  update karyawan set wajib_ganti_pin = false where user_id = auth.uid();
$$;


-- ---------------------------------------------------------------------
-- 3. KELOLA AKUN (jalankan dari SQL Editor)
-- ---------------------------------------------------------------------
-- Contoh pemakaian:
--   select public.buat_akun_karyawan('12345678', 'BUDI SANTOSO', 'ya', 'PLANT', 'PLANNER');  -- admin
--   select public.buat_akun_karyawan('10458821', 'AGUS RIYADI', null, 'PLANT', 'MEKANIK');   -- karyawan
--   select public.reset_pin_karyawan('10458821');                   -- lupa PIN
--   update public.karyawan set aktif = false where nrp = '10458821';     -- nonaktifkan
--   update public.karyawan set admin = 'ya'  where nrp = '10458821';     -- jadikan admin

-- Buat akun login baru dengan PIN awal 0000.
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

-- Kembalikan PIN ke 0000 dan wajibkan ganti saat masuk berikutnya.
create or replace function public.reset_pin_karyawan(p_nrp text)
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

  update karyawan set wajib_ganti_pin = true where nrp = trim(p_nrp);
end;
$$;


-- ---------------------------------------------------------------------
-- 4. FUNGSI ADMIN: sekarang cek kolom admin, bukan sekadar "sudah login"
-- ---------------------------------------------------------------------
-- Sebelumnya cukup login (akun admin bersama). Sekarang semua karyawan
-- login, jadi update_part, delete_part dan update_riwayat harus memeriksa
-- admin = 'ya'.
--
-- Supaya isi fungsi yang sudah ada di database TIDAK berubah sama sekali,
-- blok ini mengambil definisi fungsi yang sekarang, lalu hanya mengganti
-- satu baris pengecekan:
--     if auth.uid() is null then      ->  if not public.is_admin() then
-- Kalau baris itu tidak ditemukan, proses dihentikan supaya bisa dicek manual.
do $$
declare
  v_nama  text;
  v_def   text;
begin
  foreach v_nama in array array['update_part', 'delete_part', 'update_riwayat'] loop
    for v_def in
      select pg_get_functiondef(p.oid)
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = v_nama
    loop
      if position('auth.uid() is null' in v_def) > 0 then
        execute replace(v_def, 'auth.uid() is null', 'not public.is_admin()');
      elsif position('public.is_admin()' in v_def) = 0 then
        raise exception 'Fungsi % tidak punya pengecekan login yang dikenali. Cek manual.', v_nama;
      end if;
      -- kalau sudah berisi public.is_admin(), berarti sudah diubah sebelumnya
    end loop;
  end loop;
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
  public.selesai_ganti_pin(),
  public.buat_akun_karyawan(text, text, text, text, text),
  public.reset_pin_karyawan(text)
from public, anon;

grant execute on function
  public.is_admin(),
  public.profil_saya(),
  public.selesai_ganti_pin(),
  public.buat_akun_karyawan(text, text, text, text, text),
  public.reset_pin_karyawan(text)
to authenticated;
