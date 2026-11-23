// =====================================================================
// auth.js -- Login dengan NRP + auto-logout
//
// Alur singkat:
//   1. Halaman dibuka  -> cek sesi login yang tersimpan (mulaiAuth)
//   2. Belum login     -> layar "Masuk" (NRP + password)
//   3. Password masih 0000 -> layar "Password baru" (wajib ganti)
//   4. Sudah login     -> aplikasi dibuka, nama otomatis terisi & terkunci
//   5. Tidak ada aktivitas 12 jam (admin 4 jam) -> keluar otomatis, tanpa
//      peringatan
//
// Butuh: script.js dimuat lebih dulu (variabel sb, isAdmin, init(),
// updateAdminUI(), toast(), esc()).
// Database: lihat sql/01-login-nrp.sql (tabel karyawan & fungsi-fungsinya).
// =====================================================================


// ---- Pengaturan (ubah di sini saja) ---------------------------------

// Akun di Supabase memakai email buatan: <NRP>@cetok.local
const EMAIL_DOMAIN = '@cetok.local';

// Supabase mewajibkan password minimal 6 karakter. Karyawan mengetik
// password pendek (mis. 0000), web menambahkan awalan ini sebelum dikirim.
// HARUS sama dengan awalan di sql/01-login-nrp.sql ('cetok-0000').
const PASSWORD_PREFIX = 'cetok-';
const PASSWORD_AWAL = '0000';
const PASSWORD_MIN = 4;

// Batas tidak aktif sebelum keluar otomatis
const BATAS_DIAM_KARYAWAN_JAM = 12;
const BATAS_DIAM_ADMIN_JAM = 4;

// Penyimpanan waktu aktivitas terakhir (di browser)
const KUNCI_AKTIVITAS = 'cetok_aktivitas_terakhir';
const JEDA_SIMPAN_AKTIVITAS_MS = 60 * 1000;  // simpan paling sering 1x per menit
const JEDA_CEK_DIAM_MS = 60 * 1000;          // cek batas diam tiap 1 menit

const JAM_MS = 60 * 60 * 1000;


// ---- Data karyawan yang sedang login ----------------------------------

// Isi: { nrp, nama, admin (true/false), wajib_ganti_password }
let karyawanLogin = null;
let dataSudahDimuat = false;

// Nama untuk kolom Nama di form Ambil/Transfer/Input (dipakai script.js juga)
function namaLogin(){
  return karyawanLogin ? karyawanLogin.nama : '';
}

// "ANAS KUSUMA AJI" -> "AK"
function inisial(nama){
  const kata = String(nama || '').trim().split(/\s+/).filter(Boolean);
  return kata.slice(0, 2).map(k => k[0]).join('').toUpperCase();
}


// ---- Pindah layar -----------------------------------------------------

const elLayarMasuk = document.getElementById('layarMasuk');
const elLayarPasswordBaru = document.getElementById('layarPasswordBaru');

function tampilkanLayarMasuk(pesan){
  document.body.classList.remove('cek-sesi');
  document.body.classList.add('belum-masuk');
  elLayarPasswordBaru.hidden = true;
  elLayarMasuk.hidden = false;
  document.getElementById('masuk_password').value = '';
  document.getElementById('masukError').textContent = pesan || '';
  document.getElementById('masuk_nrp').focus();
}

// wajib = true  -> password awal, tidak bisa dibatalkan
// wajib = false -> dibuka dari menu "Ganti password", ada tombol Batal
function tampilkanLayarPasswordBaru(wajib){
  document.body.classList.remove('cek-sesi');
  document.body.classList.add('belum-masuk');
  elLayarMasuk.hidden = true;
  elLayarPasswordBaru.hidden = false;
  document.getElementById('pbInisial').textContent = inisial(karyawanLogin.nama);
  document.getElementById('pbNama').textContent = karyawanLogin.nama;
  document.getElementById('pbNrp').textContent = karyawanLogin.nrp;
  document.getElementById('pb_password').value = '';
  document.getElementById('pb_ulangi').value = '';
  document.getElementById('pbError').textContent = '';
  document.getElementById('btnBatalPassword').hidden = wajib;
  document.getElementById('pb_password').focus();
}

function bukaAplikasi(){
  document.body.classList.remove('cek-sesi', 'belum-masuk');
  elLayarMasuk.hidden = true;
  elLayarPasswordBaru.hidden = true;

  isAdmin = karyawanLogin.admin;
  isiNamaOtomatis();
  isiMenuAkun();
  catatAktivitas(true);

  if(!dataSudahDimuat){
    dataSudahDimuat = true;
    init();            // dari script.js: muat stok & riwayat
  } else {
    updateAdminUI();   // data sudah ada, cukup gambar ulang tombol admin
  }
}


// ---- Masuk ------------------------------------------------------------

async function masuk(nrp, password){
  const { error } = await sb.auth.signInWithPassword({
    email: nrp + EMAIL_DOMAIN,
    password: PASSWORD_PREFIX + password
  });
  if(error) throw new Error('NRP atau password salah.');

  const profil = await ambilProfil();
  if(!profil){
    await sb.auth.signOut();
    throw new Error('NRP ini belum terdaftar atau sudah tidak aktif.');
  }
  karyawanLogin = profil;
  catatAktivitas(true);
  lanjutSetelahMasuk();
}

// Ambil data karyawan dari tabel karyawan (lewat fungsi profil_saya)
async function ambilProfil(){
  const { data, error } = await sb.rpc('profil_saya');
  if(error) throw new Error(error.message);
  return data;  // null kalau tidak terdaftar / tidak aktif
}

function lanjutSetelahMasuk(){
  if(karyawanLogin.wajib_ganti_password){
    tampilkanLayarPasswordBaru(true);
  } else {
    bukaAplikasi();
  }
}

document.getElementById('formMasuk').addEventListener('submit', async (e)=>{
  e.preventDefault();
  const nrp = document.getElementById('masuk_nrp').value.trim();
  const password = document.getElementById('masuk_password').value;
  const errEl = document.getElementById('masukError');
  const btn = document.getElementById('btnMasuk');

  if(!/^[0-9]+$/.test(nrp)){ errEl.textContent = 'NRP hanya berisi angka.'; return; }
  if(!password){ errEl.textContent = 'Password wajib diisi.'; return; }

  errEl.textContent = '';
  btn.disabled = true; btn.textContent = 'Masuk...';
  try{
    await masuk(nrp, password);
  }catch(err){
    errEl.textContent = err.message;
  }finally{
    btn.disabled = false; btn.textContent = 'Masuk';
  }
});

document.getElementById('btnLupaPassword').addEventListener('click', ()=>{
  document.getElementById('masukError').textContent = 'Minta admin untuk reset password.';
});


// ---- Password baru ----------------------------------------------------

// Mengembalikan pesan kesalahan, atau '' kalau password boleh dipakai
function cekPasswordBaru(pw, ulangi){
  if(pw.length < PASSWORD_MIN) return `Password minimal ${PASSWORD_MIN} karakter.`;
  if(pw === PASSWORD_AWAL) return 'Password tidak boleh ' + PASSWORD_AWAL + '.';
  if(pw === karyawanLogin.nrp) return 'Password tidak boleh sama dengan NRP.';
  if(pw !== ulangi) return 'Ulangi password belum sama.';
  return '';
}

document.getElementById('formPasswordBaru').addEventListener('submit', async (e)=>{
  e.preventDefault();
  const pw = document.getElementById('pb_password').value;
  const ulangi = document.getElementById('pb_ulangi').value;
  const errEl = document.getElementById('pbError');
  const btn = document.getElementById('btnSimpanPassword');

  const salah = cekPasswordBaru(pw, ulangi);
  if(salah){ errEl.textContent = salah; return; }

  errEl.textContent = '';
  btn.disabled = true; btn.textContent = 'Menyimpan...';
  try{
    const { error } = await sb.auth.updateUser({ password: PASSWORD_PREFIX + pw });
    if(error) throw error;
    const { error: errTandai } = await sb.rpc('selesai_ganti_password');
    if(errTandai) throw errTandai;

    karyawanLogin.wajib_ganti_password = false;
    toast('Password tersimpan');
    bukaAplikasi();
  }catch(err){
    errEl.textContent = 'Gagal menyimpan password: ' + (err.message || err);
  }finally{
    btn.disabled = false; btn.textContent = 'Simpan';
  }
});

document.getElementById('btnBatalPassword').addEventListener('click', bukaAplikasi);


// ---- Keluar -----------------------------------------------------------

async function keluar(pesan){
  karyawanLogin = null;
  isAdmin = false;
  try{ localStorage.removeItem(KUNCI_AKTIVITAS); }catch(e){}
  tutupMenuAkun();
  tampilkanLayarMasuk(pesan);
  try{ await sb.auth.signOut(); }catch(e){ /* sesi sudah habis, abaikan */ }
}

// Keluar dari tab/perangkat lain, atau sesi kedaluwarsa
sb.auth.onAuthStateChange((event)=>{
  if(event === 'SIGNED_OUT' && karyawanLogin) keluar();
});


// ---- Nama otomatis di form --------------------------------------------

function isiNamaOtomatis(){
  ['ax_nama', 'tf_nama', 'in_nama'].forEach(id=>{
    document.getElementById(id).value = namaLogin();
  });
}


// ---- Menu akun (lingkaran inisial di header) ---------------------------

const elAkunBtn = document.getElementById('akunBtn');
const elAkunMenu = document.getElementById('akunMenu');

function isiMenuAkun(){
  const ini = inisial(karyawanLogin.nama);
  document.getElementById('akunInisial').textContent = ini;
  document.getElementById('akunMenuInisial').textContent = ini;
  document.getElementById('akunNama').textContent = karyawanLogin.nama;
  document.getElementById('akunNrp').textContent = karyawanLogin.nrp;
  document.getElementById('akunAdmin').hidden = !karyawanLogin.admin;
  elAkunBtn.title = karyawanLogin.nama;
}

function tutupMenuAkun(){
  elAkunMenu.hidden = true;
  elAkunBtn.setAttribute('aria-expanded', 'false');
}

elAkunBtn.addEventListener('click', (e)=>{
  e.stopPropagation();
  const buka = elAkunMenu.hidden;
  elAkunMenu.hidden = !buka;
  elAkunBtn.setAttribute('aria-expanded', String(buka));
});
document.addEventListener('click', (e)=>{
  if(!elAkunMenu.hidden && !elAkunMenu.contains(e.target)) tutupMenuAkun();
});
document.addEventListener('keydown', (e)=>{
  if(e.key === 'Escape') tutupMenuAkun();
});

document.getElementById('btnGantiPassword').addEventListener('click', ()=>{
  tutupMenuAkun();
  tampilkanLayarPasswordBaru(false);
});
document.getElementById('btnKeluar').addEventListener('click', ()=> keluar());


// ---- Auto-logout karena tidak aktif -------------------------------------
// Waktu aktivitas terakhir disimpan di browser. Kalau web dibuka lagi
// (atau HP dinyalakan lagi) dan sudah lewat batas, langsung keluar.

let terakhirDisimpan = 0;

function batasDiamMs(){
  const jam = karyawanLogin && karyawanLogin.admin ? BATAS_DIAM_ADMIN_JAM : BATAS_DIAM_KARYAWAN_JAM;
  return jam * JAM_MS;
}

function catatAktivitas(paksa){
  if(!karyawanLogin) return;
  const sekarang = Date.now();
  if(!paksa && sekarang - terakhirDisimpan < JEDA_SIMPAN_AKTIVITAS_MS) return;
  terakhirDisimpan = sekarang;
  try{ localStorage.setItem(KUNCI_AKTIVITAS, String(sekarang)); }catch(e){}
}

function sudahLewatBatasDiam(){
  let terakhir = 0;
  try{ terakhir = Number(localStorage.getItem(KUNCI_AKTIVITAS)) || 0; }catch(e){}
  if(!terakhir) return false;  // belum pernah tercatat, anggap baru aktif
  return Date.now() - terakhir > batasDiamMs();
}

function cekBatasDiam(){
  if(karyawanLogin && sudahLewatBatasDiam()) keluar();
}

['pointerdown', 'keydown', 'scroll', 'touchstart'].forEach(jenis=>{
  window.addEventListener(jenis, ()=> catatAktivitas(false), { passive: true });
});
document.addEventListener('visibilitychange', ()=>{
  if(document.visibilityState === 'visible') cekBatasDiam();
});
setInterval(cekBatasDiam, JEDA_CEK_DIAM_MS);


// ---- Mulai: cek sesi yang tersimpan saat halaman dibuka -----------------

async function mulaiAuth(){
  // Logo di layar Masuk diambil dari logo header (supaya tidak dobel di HTML)
  const logo = document.querySelector('header.top .logo-icon');
  document.querySelectorAll('.auth-logo').forEach(img => { if(logo) img.src = logo.src; });

  try{
    const { data } = await sb.auth.getSession();
    if(!data.session){ tampilkanLayarMasuk(); return; }

    const profil = await ambilProfil();
    if(!profil){ await keluar(); return; }  // mis. sesi akun admin bersama yang lama
    karyawanLogin = profil;

    if(sudahLewatBatasDiam()){ await keluar(); return; }
    lanjutSetelahMasuk();
  }catch(e){
    tampilkanLayarMasuk('Gagal terhubung ke server. Coba lagi.');
  }
}

mulaiAuth();
