# SQL Cetok Online

File SQL dijalankan manual di **Supabase Dashboard > SQL Editor**, berurutan sesuai nomor.

| File | Isi | Status |
|---|---|---|
| `01-login-nrp.sql` | Tabel `karyawan`, fungsi login NRP, fungsi admin cek kolom `admin = 'ya'` | belum dijalankan |
| `02-data-karyawan.sql` | Daftar akun karyawan | **tidak disimpan di GitHub** (repo publik, berisi data pribadi) |

## Urutan pasang login NRP

1. Jalankan `01-login-nrp.sql`.
2. Jalankan `02-data-karyawan.sql` (disimpan terpisah, bukan di repo ini).
3. Baru setelah itu merge kode web (`auth.js`, dll). Kalau kode web naik duluan, semua orang tidak bisa masuk.

## Kelola akun sehari-hari (SQL Editor)

```sql
-- tambah karyawan baru (password awal 0000, wajib ganti saat masuk)
select public.buat_akun_karyawan('12345678', 'NAMA LENGKAP', null, 'PLANT', 'MEKANIK');

-- lupa password -> kembali ke 0000
select public.reset_password_karyawan('12345678');

-- jadikan admin / cabut admin
update public.karyawan set admin = 'ya' where nrp = '12345678';
update public.karyawan set admin = null where nrp = '12345678';

-- karyawan keluar / pindah (tidak bisa masuk lagi, riwayat tetap ada)
update public.karyawan set aktif = false where nrp = '12345678';
```
