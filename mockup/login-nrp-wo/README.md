# Mockup: Login NRP + Kolom WO

Mockup tampilan (belum diterapkan ke web dan database). Buka `mockup-login-nrp.html` di browser untuk mencoba alurnya, atau `papan-mockup.html` untuk melihat semua layar sekaligus.

## Login NRP
- Masuk memakai NRP + password. Password awal `0000`, dan wajib diganti saat login pertama.
- Admin ditentukan dari kolom `admin` di tabel `karyawan` (isi `ya`).
- Keluar otomatis setelah tidak ada aktivitas: **12 jam** untuk karyawan, **4 jam** untuk admin, tanpa peringatan.
- Tombol "Login" di header diganti lingkaran inisial yang membuka menu (nama, NRP, label Admin, Ganti password, Keluar).
- Kolom nama di form Ambil / Transfer / Input terisi otomatis dari akun yang login dan dikunci.

## Kolom WO (work order)
- Format nomor: `2000xxxxx`. Kolom ini boleh kosong karena tidak semua part punya WO.
- **Input**: kolom No. WO di bawah Parts Description.
- **Ambil**: kolom No. WO paling atas, di atas Parts Number. Saat diketik, muncul saran baris part yang WO-nya cocok, dan memilih salah satu akan mengisi Parts Number.
- **Transfer**: kolom No. WO di bawah Lokasi Tujuan. Kalau dikosongkan, WO lama tetap dipakai. WO hanya berganti kalau diisi nomor baru.
- **Riwayat**: WO tampil sebagai label di samping unit/status. Kalau kosong ditampilkan `WO –`. Untuk transfer yang mengganti WO, tampil WO lama (dicoret) → WO baru.

## Riwayat
- Kartu: ikon jenis (Input / Ambil / Transfer), nama part, PN, unit, status, WO, lokasi (transfer: asal → tujuan), keterangan, nama + NRP, waktu, dan qty berwarna.
- Filter: tombol Semua / Input / Ambil / Transfer, serta dropdown Unit (dikelompokkan Excavator / Bulldozer) yang bisa dicari.

## Aging komponen
- Tab Stok menampilkan sudah berapa hari tiap baris part berada di status RFU / NOT RFU. Hari 0 dihitung dari tanggal part diinput (`created_at` baris stok).
- Warna aging: 0–30 hari hijau, 31–90 hari oranye, lebih dari 90 hari merah (batas masih usulan).
- Panel ringkasan: rata-rata dan aging terlama, serta jumlah part per rentang (dengan rincian RFU / NOT RFU). Klik rentang untuk menyaring daftar.
- HP: kartu part dengan unit, status, WO, lokasi, dan bar aging. Desktop: tabel dengan kolom Aging yang bisa diurutkan, plus tombol Export.
- Pencarian juga mencakup WO.

## Rencana perubahan database (menunggu persetujuan)
- Tabel baru `karyawan`: `nrp`, `nama`, `admin` (`ya` / kosong), `wajib_ganti_password`, `aktif`.
- Kolom baru `wo` (kosong) di tabel stok dan riwayat. Data part lama akan diisi manual.
- Baris stok dipisah per WO: part yang sama di lokasi + status yang sama tapi WO-nya berbeda menjadi baris sendiri.
- Fungsi yang perlu diubah: `input_barang`, `ambil_barang`, `transfer_stok`, `update_part`, `update_riwayat`, `get_all_data`, `get_riwayat_page`. Parameter WO dibuat opsional supaya WA bot v2 tetap jalan.

Nama dan NRP di mockup hanya contoh.
