-- =====================================================================
-- 06-wo-ambil.sql
-- WO pengambilan, terpisah dari WO input.
--
--   WO input      : melekat di baris stok (stok.wo), diisi saat Input
--                   atau diganti saat Transfer. Tidak berubah saat diambil.
--   WO pengambilan: dicatat di riwayat saat part diambil (riwayat.wo_ambil).
--                   Tidak wajib diisi.
--
-- Isi file ini:
--   1. Kolom baru riwayat.wo_ambil
--   2. rapikan_wo  : format WO jadi 12 angka (awalan bebas: 20, 22, 25, ...)
--   3. ambil_barang: tambah parameter p_wo_ambil (boleh kosong)
--   4. get_all_data & get_riwayat_page: kirim 'wo_ambil' ke web,
--      pencarian riwayat ikut cek WO pengambilan
--
-- Bot WA v2 tetap jalan karena p_wo_ambil punya default null.
-- Jalankan SETELAH 03-wo.sql, 04-aging.sql, dan 05-riwayat-jenis.sql.
-- Aman dijalankan lebih dari sekali.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. Kolom baru (mulai kosong)
-- ---------------------------------------------------------------------
alter table public.riwayat add column if not exists wo_ambil text;


-- ---------------------------------------------------------------------
-- 2. rapikan_wo: kosong -> null, selain itu wajib 12 angka.
--    Awalan WO tidak pasti (20, 22, 25, ...), jadi tidak dicek lagi.
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
  if v_wo !~ '^[0-9]{12}$' then
    raise exception 'Format WO harus 12 angka, cth: 200012345678';
  end if;
  return v_wo;
end;
$$;


-- ---------------------------------------------------------------------
-- 3. ambil_barang + p_wo_ambil
--    WO input baris stok tetap ikut tercatat di riwayat.wo (seperti sebelumnya),
--    WO pengambilan dicatat di riwayat.wo_ambil.
-- ---------------------------------------------------------------------
drop function if exists public.ambil_barang(uuid, integer, text, text);

create or replace function public.ambil_barang(
  p_id uuid, p_qty integer, p_note text, p_nama text,
  p_wo_ambil text default null
)
returns void
language plpgsql
security definer
as $function$
declare
  v_row stok%rowtype;
  v_new_qty integer;
  v_wo_ambil text := public.rapikan_wo(p_wo_ambil);                -- WO AMBIL
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

  insert into riwayat (jenis, unit_model, parts_number, parts_description, qty, keterangan, nama, status_rfu, lokasi, wo, wo_ambil, nrp)
  values ('keluar', v_row.unit_model, v_row.parts_number, v_row.parts_description, p_qty, p_note, p_nama, v_row.status_rfu, v_row.lokasi,
          v_row.wo, v_wo_ambil, public.nrp_saya());                   -- WO AMBIL
end;
$function$;


-- ---------------------------------------------------------------------
-- 4a. get_all_data (versi 04-aging.sql + baris bertanda WO AMBIL)
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
        'wo', s.wo,
        'aging_sejak', s.aging_sejak
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
        'wo', r.wo, 'wo_lama', r.wo_lama, 'nrp', r.nrp,
        'wo_ambil', r.wo_ambil                                         -- WO AMBIL
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
-- 4b. get_riwayat_page (versi 05-riwayat-jenis.sql + baris bertanda WO AMBIL)
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
    where (p_jenis is null
           or (p_jenis = 'masuk'    and r.jenis = 'masuk')
           or (p_jenis = 'keluar'   and r.jenis = 'keluar' and r.keterangan not ilike 'TRANSFER KE %')   -- Ambil saja
           or (p_jenis = 'transfer' and r.jenis = 'keluar' and r.keterangan ilike 'TRANSFER KE %'))     -- Transfer saja
      and (p_unit is null or r.unit_model = p_unit)
      and (p_search is null or p_search = '' or
           r.parts_number ilike '%' || p_search || '%' or
           r.parts_description ilike '%' || p_search || '%' or
           r.wo ilike '%' || p_search || '%' or                        -- WO
           r.wo_lama ilike '%' || p_search || '%' or
           r.wo_ambil ilike '%' || p_search || '%')                    -- WO AMBIL
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
        'wo', f.wo, 'wo_lama', f.wo_lama, 'nrp', f.nrp,
        'wo_ambil', f.wo_ambil                                         -- WO AMBIL
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
-- Cek hasil (boleh dijalankan terpisah): 10 pengambilan terakhir
--   select created_at, parts_number, wo, wo_ambil, nama
--   from public.riwayat where jenis = 'keluar' and keterangan not ilike 'TRANSFER KE %'
--   order by created_at desc limit 10;
-- ---------------------------------------------------------------------
