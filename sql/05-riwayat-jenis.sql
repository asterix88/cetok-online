-- =====================================================================
-- 05-riwayat-jenis.sql
-- Filter jenis di tab Riwayat: Semua / Input / Ambil / Transfer.
--
-- Sebelumnya p_jenis hanya 'masuk' atau 'keluar', sehingga Transfer ikut
-- tercampur di "Ambil" (transfer dicatat sebagai baris 'keluar' dengan
-- keterangan "TRANSFER KE ..."). Sekarang:
--   p_jenis = 'masuk'    -> Input
--   p_jenis = 'keluar'   -> Ambil saja (tanpa transfer)
--   p_jenis = 'transfer' -> Transfer saja
--   p_jenis = null       -> semua
--
-- Hanya fungsi get_riwayat_page yang diganti, parameternya sama.
-- Jalankan SETELAH 03-wo.sql. Aman dijalankan lebih dari sekali.
-- =====================================================================


-- ---------------------------------------------------------------------
-- get_riwayat_page (versi 03-wo.sql + baris bertanda JENIS)
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
           or (p_jenis = 'keluar'   and r.jenis = 'keluar' and r.keterangan not ilike 'TRANSFER KE %')   -- JENIS: Ambil saja
           or (p_jenis = 'transfer' and r.jenis = 'keluar' and r.keterangan ilike 'TRANSFER KE %'))     -- JENIS: Transfer saja
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
