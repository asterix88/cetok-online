-- =====================================================================
-- 04-aging.sql
-- Aging komponen: berapa hari part sudah berada di status sekarang.
--
-- Aturan:
--   - Hari 0 = tanggal part diinput (baris stok baru dibuat).
--   - Status berganti (RFU <-> NOT RFU, atau dari kosong ke RFU/NOT RFU
--     saat stok habis lalu diisi lagi) -> aging mulai lagi dari 0.
--   - Tambah qty ke baris yang sudah ada, ambil, ganti lokasi/WO
--     -> aging TIDAK berubah.
--   - Transfer ke lokasi lain dengan status sama -> aging ikut dibawa.
--
-- Isi file ini:
--   1. Kolom baru stok.aging_sejak (tanggal mulai aging)
--   2. Isi aging_sejak untuk part yang sudah ada (perkiraan dari riwayat)
--   3. Trigger: aging_sejak di-reset otomatis saat status berganti
--   4. transfer_stok: baris tujuan baru membawa aging_sejak dari asal
--   5. get_all_data: kirim aging_sejak ke web
--
-- Jalankan SETELAH 03-wo.sql (fungsi no. 4 dan 5 adalah versi 03-wo.sql
-- ditambah baris bertanda "AGING"). Aman dijalankan lebih dari sekali.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. Kolom tanggal mulai aging. Baris baru otomatis = waktu dibuat.
-- ---------------------------------------------------------------------
alter table public.stok add column if not exists aging_sejak timestamptz;
alter table public.stok alter column aging_sejak set default now();


-- ---------------------------------------------------------------------
-- 2. Part lama: aging_sejak diperkirakan dari riwayat, yaitu transaksi
--    'masuk' paling awal untuk part + lokasi + status yang sama.
--    Kalau tidak ketemu di riwayat, pakai updated_at.
--    Hanya mengisi yang masih kosong, jadi aman dijalankan ulang.
-- ---------------------------------------------------------------------
update public.stok s
set aging_sejak = coalesce(
  (select min(r.created_at)
   from public.riwayat r
   where r.jenis = 'masuk'
     and r.unit_model = s.unit_model
     and lower(r.parts_number) = lower(s.parts_number)
     and upper(coalesce(r.lokasi, '')) = upper(coalesce(s.lokasi, ''))
     and r.status_rfu = s.status_rfu),
  s.updated_at,
  now()
)
where s.aging_sejak is null;

alter table public.stok alter column aging_sejak set not null;


-- ---------------------------------------------------------------------
-- 3. Trigger reset aging saat status berganti ke RFU / NOT RFU.
--    (Status jadi kosong karena stok habis -> tidak di-reset; nanti
--     di-reset saat stoknya diisi lagi dengan status baru.)
-- ---------------------------------------------------------------------
create or replace function public.reset_aging_saat_ganti_status()
returns trigger
language plpgsql
as $$
begin
  if new.status_rfu is not null and new.status_rfu is distinct from old.status_rfu then
    new.aging_sejak := now();
  end if;
  return new;
end;
$$;

drop trigger if exists stok_reset_aging on public.stok;
create trigger stok_reset_aging
  before update of status_rfu on public.stok
  for each row
  execute function public.reset_aging_saat_ganti_status();


-- ---------------------------------------------------------------------
-- 4. transfer_stok (versi 03-wo.sql + AGING)
--    Baris tujuan yang BARU dibuat membawa aging_sejak dari baris asal
--    kalau statusnya sama. Kalau status berganti, mulai dari 0 (now()).
--    Baris tujuan yang sudah ada: aging-nya tetap (tidak diubah).
-- ---------------------------------------------------------------------
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
  v_dest_aging timestamptz;
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

  -- AGING: status sama -> bawa tanggal aging asal, status beda -> mulai 0
  v_dest_aging := case when v_dest_status = v_row.status_rfu then v_row.aging_sejak else now() end;

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
      and coalesce(wo,'') = coalesce(v_dest_wo,'')
    for update;

  if v_dest_id is not null then
    update stok set quantity = quantity + p_qty, updated_at = now() where id = v_dest_id;
  else
    insert into stok (unit_model, parts_number, parts_description, lokasi, quantity, status_rfu, wo, aging_sejak)
    values (v_row.unit_model, v_row.parts_number, v_row.parts_description, v_dest_loc, p_qty, v_dest_status, v_dest_wo,
            v_dest_aging);                                            -- AGING
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
-- 5. get_all_data (versi 03-wo.sql + AGING): kirim aging_sejak per part
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
        'aging_sejak', s.aging_sejak                                   -- AGING
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
        'wo', r.wo, 'wo_lama', r.wo_lama, 'nrp', r.nrp
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
-- Cek hasil (boleh dijalankan terpisah): 10 part dengan aging terlama
--   select parts_number, lokasi, status_rfu, aging_sejak,
--          current_date - aging_sejak::date as hari
--   from public.stok where quantity > 0 order by aging_sejak limit 10;
-- ---------------------------------------------------------------------
