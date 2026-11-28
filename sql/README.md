# SQL Cetok Online

File SQL dijalankan manual di **Supabase Dashboard > SQL Editor**, berurutan sesuai nomor.

| File | Isi | Status |
|---|---|---|
| `01-login-nrp.sql` | Tabel `karyawan`, fungsi login NRP, fungsi admin cek kolom `admin = 'ya'` | sudah dijalankan (23 Nov 2026) |
| `02-data-karyawan.sql` | Daftar akun karyawan | **tidak disimpan di GitHub** (repo publik, berisi data pribadi) |
| `03-wo.sql` | Kolom WO di stok & riwayat, NRP pencatat di riwayat, fungsi `ubah_wo_part` (admin) | belum dijalankan |
| `04-aging.sql` | Kolom `aging_sejak` di stok + trigger reset saat status berganti | belum dijalankan (setelah 03) |
| `05-riwayat-jenis.sql` | Filter Riwayat: Ambil dan Transfer dipisah | belum dijalankan (setelah 03) |
| `06-wo-ambil.sql` | WO pengambilan di riwayat (terpisah dari WO input), format WO 12 angka bebas awalan | belum dijalankan (setelah 05) |
| `07-lokasi-tampil.sql` | Set `is_filtered = false` untuk part di 7 lokasi (termasuk LEMARI HIJAU, LEMARI PLANNER, VENDOR) | belum dijalankan |

## Urutan pasang login NRP

1. Jalankan `01-login-nrp.sql`.
2. Jalankan `02-data-karyawan.sql` (disimpan terpisah, bukan di repo ini).
3. Baru setelah itu merge kode web (`auth.js`, dll). Kalau kode web naik duluan, semua orang tidak bisa masuk.

## Urutan pasang WO

1. Jalankan `03-wo.sql` **sebelum** merge kode web WO. Kode web lama tetap jalan
   setelah SQL ini (parameter baru semuanya boleh kosong), jadi aman dijalankan duluan.
2. Merge kode web (`wo.js`, dll).
3. Isi WO part lama lewat panel part > Edit data (khusus admin), atau sekaligus lewat SQL:

```sql
update public.stok set wo = '200012345678' where id = '...';
```

## Urutan pasang Aging

1. Jalankan `04-aging.sql` (setelah `03-wo.sql`), lalu merge kode web Aging.
2. Part lama diberi tanggal aging perkiraan: transaksi masuk paling awal di riwayat
   untuk part + lokasi + status yang sama, kalau tidak ada pakai `updated_at`.

## Urutan pasang WO pengambilan

1. Jalankan `06-wo-ambil.sql` **sebelum** merge kode web WO pengambilan.
   Kode web lama tetap jalan setelah SQL ini (`p_wo_ambil` boleh kosong).
2. Merge kode web.

## Kelola akun sehari-hari (SQL Editor)

```sql
-- tambah karyawan baru (PIN awal 0000, wajib ganti saat masuk)
select public.buat_akun_karyawan('12345678', 'NAMA LENGKAP', null, 'PLANT', 'MEKANIK');

-- lupa PIN -> kembali ke 0000
select public.reset_pin_karyawan('12345678');

-- jadikan admin / cabut admin
update public.karyawan set admin = 'ya' where nrp = '12345678';
update public.karyawan set admin = null where nrp = '12345678';

-- karyawan keluar / pindah (tidak bisa masuk lagi, riwayat tetap ada)
update public.karyawan set aktif = false where nrp = '12345678';
```
