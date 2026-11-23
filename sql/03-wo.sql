-- =====================================================================
-- 03-wo.sql
-- Nomor WO (work order) di stok dan riwayat, plus NRP pencatat di riwayat.
--
-- Isi file ini:
--   1. Kolom baru: stok.wo, riwayat.wo, riwayat.wo_lama, riwayat.nrp
--   2. Index unik stok ditambah WO -> baris stok dipisah per WO
--   3. Fungsi bantu: rapikan_wo() dan nrp_saya()
--   4. input_barang   : tambah parameter p_wo (boleh kosong)
--   5. ambil_barang   : WO ikut tercatat di riwayat (parameter tidak berubah)
--   6. transfer_stok  : tambah parameter p_wo (kosong = WO lama dipakai terus)
--   7. ubah_wo_part   : khusus admin, isi/ganti WO part yang sudah ada
--   8. get_all_data & get_riwayat_page: kirim WO (dan NRP) ke web
--
-- Fungsi 4-8 ditulis ulang dari definisi LIVE di Supabase (23 Nov 2026),
-- bukan dari file referensi lama. Yang berubah hanya bagian bertanda "WO"
-- atau "NRP". Bot WA v2 tetap jalan karena parameter baru punya default.
--
-- Aman dijalankan lebih dari sekali.
-- Jalankan SETELAH 01-login-nrp.sql (butuh tabel karyawan & is_admin()).
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. Kolom baru (semua mulai kosong; WO part lama diisi admin sendiri)
-- ---------------------------------------------------------------------
--   stok.wo         : nomor WO part di baris stok ini
--   riwayat.wo      : nomor WO saat transaksi terjadi
--   riwayat.wo_lama : WO sebelum transfer, hanya diisi kalau WO diganti
--   riwayat.nrp     : NRP karyawan yang login (kosong kalau dari bot WA)
alter table public.stok    add column if not exists wo      text;
alter table public.riwayat add column if not exists wo      text;
alter table public.riwayat add column if not exists wo_lama text;
alter table public.riwayat add column if not exists nrp     text;


-- ---------------------------------------------------------------------
-- 2. Index unik stok: unit + parts number + lokasi + status + WO.
--    Part yang sama di lokasi & status yang sama tapi WO-nya beda
--    sekarang jadi baris terpisah (tidak digabung).
-- ---------------------------------------------------------------------
drop index if exists public.stok_unit_pn_loc_status_uidx;
create unique index if not exists stok_unit_pn_loc_status_wo_uidx
  on public.stok (unit_model, lower(parts_number), lower(coalesce(lokasi, '')), status_rfu, coalesce(wo, ''));


-- ---------------------------------------------------------------------
-- 3a. rapikan_wo: bersihkan isian WO dari form.
--     Kosong -> null. Selain itu wajib 9 angka diawali 2000 (cth 200041587).
-- ---------------------------------------------------------------------
create or replace function public.rapikan_wo(p_wo text)
returns text
language plpgsql
immutable
as $$
declare
  v_wo text := nullif(trim(p_wo), '');
begin
  if v_wo is null then
    return null;
  end if;
  if v_wo !~ '^2000[0-9]{5}$' then
    raise exception 'Format WO harus 9 angka diawali 2000, cth: 200041587';
  end if;
  return v_wo;
end;
$$;


-- ---------------------------------------------------------------------
-- 3b. nrp_saya: NRP karyawan yang sedang login.
--     Null kalau yang memanggil bukan karyawan (misalnya bot WA).
-- ---------------------------------------------------------------------
create or replace function public.nrp_saya()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select nrp from karyawan where user_id = auth.uid() and aktif;
$$;


-- ---------------------------------------------------------------------
-- 4. input_barang + p_wo
--    Parameter bertambah, jadi versi lama (8 parameter) dihapus dulu
--    supaya tidak ada dua versi yang bikin bingung saat dipanggil.
-- ---------------------------------------------------------------------
drop function if exists public.input_barang(text, text, text, text, integer, text, text, text);

create or replace function public.input_barang(
  p_unit text, p_pn text, p_desc text, p_loc text, p_qty integer, p_nama text,
  p_status text default 'RFU', p_remarks text default null,
  p_wo text default null
)
returns void
language plpgsql
security definer
as $function$
declare
  v_status text;
  v_wo text;
  v_existing_id uuid;
begin
  if p_pn is null or trim(p_pn) = '' or p_desc is null or trim(p_desc) = '' then
    raise exception 'Parts Number dan Description wajib diisi';
  end if;
  if p_qty is null or p_qty <= 0 then
    raise exception 'Quantity harus lebih dari 0';
  end if;
  if p_nama is null or trim(p_nama) = '' then
    raise exception 'Nama penginput wajib diisi';
  end if;

  p_pn := upper(trim(p_pn));
  p_desc := upper(trim(p_desc));
  p_loc := upper(nullif(trim(p_loc), ''));
  p_remarks := upper(nullif(trim(p_remarks), ''));
  v_status := coalesce(nullif(p_status,''), 'RFU');
  v_wo := public.rapikan_wo(p_wo);                                    -- WO

  -- Baris kosong (qty 0) dengan status lain dipakai ulang, asal WO-nya sama
  select id into v_existing_id
  from stok
  where unit_model = p_unit
    and lower(parts_number) = lower(p_pn)
    and lower(coalesce(lokasi,'')) = lower(coalesce(p_loc,''))
    and coalesce(wo,'') = coalesce(v_wo,'')                           -- WO
    and quantity = 0
    and status_rfu <> v_status
  limit 1;

  if v_existing_id is not null then
    update stok
    set quantity = p_qty,
        status_rfu = v_status,
        parts_description = p_desc,
        remarks = coalesce(p_remarks, remarks),
        updated_at = now()
    where id = v_existing_id;
  else
    insert into stok (unit_model, parts_number, parts_description, lokasi, quantity, status_rfu, remarks, wo)
    values (p_unit, p_pn, p_desc, p_loc, p_qty, v_status, p_remarks, v_wo)
    on conflict (unit_model, lower(parts_number), lower(coalesce(lokasi, '')), status_rfu, coalesce(wo, ''))
    do update set
      quantity = stok.quantity + excluded.quantity,
      parts_description = excluded.parts_description,
      remarks = coalesce(excluded.remarks, stok.remarks),
      updated_at = now();
  end if;

  insert into riwayat (jenis, unit_model, parts_number, parts_description, qty, keterangan, nama, status_rfu, lokasi, wo, nrp)
  values ('masuk', p_unit, p_pn, p_desc, p_qty, coalesce(p_remarks, ''), p_nama, v_status, p_loc, v_wo, public.nrp_saya());
end;
$function$;


-- ---------------------------------------------------------------------
-- 5. ambil_barang: parameter sama, WO baris stok + NRP ikut ke riwayat
-- ---------------------------------------------------------------------
create or replace function public.ambil_barang(p_id uuid, p_qty integer, p_note text, p_nama text)
returns void
language plpgsql
security definer
as $function$
declare
  v_row stok%rowtype;
  v_new_qty integer;
begin
  if p_qty is null or p_qty <= 0 then
    raise exception 'Quantity harus lebih dari 0';
  end if;
  if p_note is null or trim(p_note) = '' then
    raise exception 'Keterangan keperluan wajib diisi';
  end if;
  if p_nama is null or trim(p_nama) = '' then
    raise exception 'Nama pengambil wajib diisi';
  end if;

  p_note := upper(trim(p_note));

  select * into v_row from stok where id = p_id for update;

  if not found then
    raise exception 'Part tidak ditemukan di stok';
  end if;
  if p_qty > v_row.quantity then
    raise exception 'Stok tidak cukup. Stok tersedia: %', v_row.quantity;
  end if;

  v_new_qty := v_row.quantity - p_qty;

  update stok
  set quantity = v_new_qty,
      status_rfu = case when v_new_qty <= 0 then NULL else status_rfu end,
      updated_at = now()
  where id = v_row.id;

  insert into riwayat (jenis, unit_model, parts_number, parts_description, qty, keterangan, nama, status_rfu, lokasi, wo, nrp)
  values ('keluar', v_row.unit_model, v_row.parts_number, v_row.parts_description, p_qty, p_note, p_nama, v_row.status_rfu, v_row.lokasi,
          v_row.wo, public.nrp_saya());                               -- WO + NRP
end;
$function$;


-- ---------------------------------------------------------------------
-- 6. transfer_stok + p_wo
--    p_wo kosong  -> WO lama ikut pindah.
--    p_wo diisi   -> WO baru menggantikan; WO lama dicatat di riwayat.wo_lama.
--    Boleh transfer di lokasi & status yang sama asal WO-nya diganti.
-- ---------------------------------------------------------------------
drop function if exists public.transfer_stok(uuid, integer, text, text, text, text);

create or replace function public.transfer_stok(
  p_source_id uuid, p_qty integer, p_dest_loc text, p_dest_status text, p_note text, p_nama text,
  p_wo text default null
)
returns void
language plpgsql
security definer
as $function$
declare
  v_row stok%rowtype;
  v_dest_loc text;
  v_dest_status text;
  v_dest_wo text;
  v_wo_lama text;
  v_note text;
  v_new_source_qty integer;
  v_dest_id uuid;
  v_note_suffix text;
begin
  if p_qty is null or p_qty <= 0 then
    raise exception 'Quantity harus lebih dari 0';
  end if;
  if p_nama is null or trim(p_nama) = '' then
    raise exception 'Nama wajib diisi';
  end if;

  -- Samakan dengan input_barang/ambil_barang: teks bebas dipaksa kapital
  -- di level database juga, bukan cuma tampilan.
  v_dest_loc := nullif(upper(trim(p_dest_loc)), '');
  if v_dest_loc is null then
    raise exception 'Lokasi tujuan wajib diisi';
  end if;
  v_dest_status := coalesce(nullif(trim(p_dest_status), ''), 'RFU');
  v_note := nullif(upper(trim(p_note)), '');
  v_note_suffix := case when v_note is not null then ' - ' || v_note else '' end;

  select * into v_row from stok where id = p_source_id for update;
  if not found then
    raise exception 'Part sumber tidak ditemukan';
  end if;
  if p_qty > v_row.quantity then
    raise exception 'Stok tidak cukup. Stok tersedia: %', v_row.quantity;
  end if;

  -- WO tujuan: isian baru, atau WO lama kalau dikosongkan
  v_dest_wo := coalesce(public.rapikan_wo(p_wo), v_row.wo);
  v_wo_lama := case when v_dest_wo is distinct from v_row.wo then v_row.wo end;

  if v_dest_loc = upper(coalesce(v_row.lokasi,''))
     and v_dest_status = v_row.status_rfu
     and v_dest_wo is not distinct from v_row.wo then
    raise exception 'Lokasi, status, dan WO tujuan sama dengan asal';
  end if;

  v_new_source_qty := v_row.quantity - p_qty;
  update stok
  set quantity = v_new_source_qty,
      status_rfu = case when v_new_source_qty <= 0 then NULL else status_rfu end,
      updated_at = now()
  where id = v_row.id;

  -- Cari baris tujuan dengan kunci yang sama persis seperti index unik
  select id into v_dest_id from stok
    where unit_model = v_row.unit_model
      and lower(parts_number) = lower(v_row.parts_number)
      and upper(coalesce(lokasi,'')) = v_dest_loc
      and status_rfu = v_dest_status
      and coalesce(wo,'') = coalesce(v_dest_wo,'')                    -- WO
    for update;

  if v_dest_id is not null then
    update stok set quantity = quantity + p_qty, updated_at = now() where id = v_dest_id;
  else
    insert into stok (unit_model, parts_number, parts_description, lokasi, quantity, status_rfu, wo)
    values (v_row.unit_model, v_row.parts_number, v_row.parts_description, v_dest_loc, p_qty, v_dest_status, v_dest_wo);
  end if;

  insert into riwayat (jenis, unit_model, parts_number, parts_description, qty, keterangan, nama, status_rfu, lokasi, wo, wo_lama, nrp)
  values ('keluar', v_row.unit_model, v_row.parts_number, v_row.parts_description, p_qty,
    'TRANSFER KE ' || v_dest_loc || ' (' || v_dest_status || ')' || v_note_suffix, p_nama, v_row.status_rfu, v_row.lokasi,
    v_dest_wo, v_wo_lama, public.nrp_saya());

  insert into riwayat (jenis, unit_model, parts_number, parts_description, qty, keterangan, nama, status_rfu, lokasi, wo, wo_lama, nrp)
  values ('masuk', v_row.unit_model, v_row.parts_number, v_row.parts_description, p_qty,
    'TRANSFER DARI ' || upper(coalesce(v_row.lokasi, '-')) || ' (' || v_row.status_rfu || ')' || v_note_suffix, p_nama, v_dest_status, v_dest_loc,
    v_dest_wo, v_wo_lama, public.nrp_saya());
end;
$function$;


-- ---------------------------------------------------------------------
-- 7. ubah_wo_part: khusus admin, isi/ganti/kosongkan WO satu baris stok.
--    Dipakai untuk melengkapi WO part lama. Tidak tercatat di riwayat
--    (sama seperti koreksi lewat Edit data).
-- ---------------------------------------------------------------------
create or replace function public.ubah_wo_part(p_id uuid, p_wo text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Hanya admin yang boleh mengubah WO';
  end if;

  update stok
  set wo = public.rapikan_wo(p_wo),
      updated_at = now()
  where id = p_id;

  if not found then
    raise exception 'Part tidak ditemukan di stok';
  end if;
exception
  when unique_violation then
    raise exception 'Sudah ada baris lain dengan part, lokasi, status, dan WO yang sama';
end;
$$;

revoke execute on function public.ubah_wo_part(uuid, text) from public, anon;
grant  execute on function public.ubah_wo_part(uuid, text) to authenticated;


-- ---------------------------------------------------------------------
-- 8a. get_all_data: tambah 'wo' di parts, dan 'wo','wo_lama','nrp' di riwayat
-- ---------------------------------------------------------------------
create or replace function public.get_all_data(p_riwayat_limit integer default 50, p_show_hidden boolean default false)
returns jsonb
language sql
stable
as $function$
  select jsonb_build_object(
    'parts', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', s.id, 'unit', s.unit_model, 'pn', s.parts_number,
        'desc', s.parts_description, 'loc', s.lokasi, 'qty', s.quantity,
        'status', s.status_rfu, 'remarks', s.remarks,
        'wo', s.wo                                                     -- WO
      ) order by s.updated_at desc)
      from stok s
      where (p_show_hidden or s.is_filtered = false)
    ), '[]'::jsonb),
    'transactions', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', r.id, 'ts', extract(epoch from r.created_at) * 1000,
        'type', r.jenis, 'unit', r.unit_model, 'pn', r.parts_number,
        'desc', r.parts_description, 'qty', r.qty, 'note', r.keterangan, 'nama', r.nama,
        'status', r.status_rfu, 'loc', r.lokasi,
        'wo', r.wo, 'wo_lama', r.wo_lama, 'nrp', r.nrp                 -- WO + NRP
      ) order by r.created_at desc)
      from (
        select r.*
        from riwayat r
        where not (r.jenis = 'masuk' and r.keterangan ilike 'TRANSFER DARI %')
          and (
            p_show_hidden
            or not exists (select 1 from stok s where s.parts_number = r.parts_number and s.unit_model = r.unit_model)
            or exists (select 1 from stok s where s.parts_number = r.parts_number and s.unit_model = r.unit_model and s.is_filtered is not true)
          )
        order by r.created_at desc
        limit p_riwayat_limit
      ) r
    ), '[]'::jsonb),
    'riwayatTotal', (
      select count(*) from riwayat r
      where not (r.jenis = 'masuk' and r.keterangan ilike 'TRANSFER DARI %')
        and (
          p_show_hidden
          or not exists (select 1 from stok s where s.parts_number = r.parts_number and s.unit_model = r.unit_model)
          or exists (select 1 from stok s where s.parts_number = r.parts_number and s.unit_model = r.unit_model and s.is_filtered is not true)
        )
    ),
    'riwayatShown', least(p_riwayat_limit, (
      select count(*) from riwayat r
      where not (r.jenis = 'masuk' and r.keterangan ilike 'TRANSFER DARI %')
        and (
          p_show_hidden
          or not exists (select 1 from stok s where s.parts_number = r.parts_number and s.unit_model = r.unit_model)
          or exists (select 1 from stok s where s.parts_number = r.parts_number and s.unit_model = r.unit_model and s.is_filtered is not true)
        )
    ))
  );
$function$;


-- ---------------------------------------------------------------------
-- 8b. get_riwayat_page: kirim 'wo','wo_lama','nrp'; pencarian ikut cek WO
-- ---------------------------------------------------------------------
create or replace function public.get_riwayat_page(
  p_page integer default 1, p_page_size integer default 20, p_jenis text default null,
  p_unit text default null, p_search text default null, p_show_hidden boolean default false
)
returns jsonb
language sql
stable
as $function$
  with filtered as (
    select r.*
    from riwayat r
    where (p_jenis is null or r.jenis = p_jenis)
      and (p_unit is null or r.unit_model = p_unit)
      and (p_search is null or p_search = '' or
           r.parts_number ilike '%' || p_search || '%' or
           r.parts_description ilike '%' || p_search || '%' or
           r.wo ilike '%' || p_search || '%' or                        -- WO
           r.wo_lama ilike '%' || p_search || '%')                     -- WO
      and not (r.jenis = 'masuk' and r.keterangan ilike 'TRANSFER DARI %')
      and (
        p_show_hidden
        or not exists (select 1 from stok s where s.parts_number = r.parts_number and s.unit_model = r.unit_model)
        or exists (select 1 from stok s where s.parts_number = r.parts_number and s.unit_model = r.unit_model and s.is_filtered is not true)
      )
  )
  select jsonb_build_object(
    'rows', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', f.id, 'ts', extract(epoch from f.created_at) * 1000,
        'type', f.jenis, 'unit', f.unit_model, 'pn', f.parts_number,
        'desc', f.parts_description, 'qty', f.qty, 'note', f.keterangan,
        'nama', f.nama, 'status', f.status_rfu, 'loc', f.lokasi,
        'wo', f.wo, 'wo_lama', f.wo_lama, 'nrp', f.nrp                 -- WO + NRP
      ))
      from (
        select * from filtered
        order by created_at desc
        limit p_page_size offset (p_page - 1) * p_page_size
      ) f
    ), '[]'::jsonb),
    'total', (select count(*) from filtered)
  );
$function$;


-- ---------------------------------------------------------------------
-- Cek hasil (boleh dijalankan terpisah):
--   select column_name from information_schema.columns
--   where table_name in ('stok','riwayat') and column_name in ('wo','wo_lama','nrp');
-- ---------------------------------------------------------------------
