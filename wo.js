// =====================================================================
// wo.js -- Nomor WO (work order)
//
// Format WO: 12 angka, awalan tidak pasti (20, 22, 25, ...), contoh 200012345678.
//
// Ada dua macam WO:
//   - WO input      : melekat di baris part (stok.wo)
//   - WO pengambilan: dicatat di riwayat saat part diambil (riwayat.wo_ambil)
// Dipakai di:
//   - Tab Input    : kolom No. WO di bawah Parts Description
//   - Tab Ambil    : kolom WO Input paling atas, ketik WO -> part disarankan;
//                    kolom WO Pengambilan (opsional) disimpan ke riwayat
//   - Tab Transfer : kolom No. WO di bawah Lokasi Tujuan
//                    (kosong = WO lama ikut pindah, diisi = WO baru)
//   - Tab Stok     : kolom WO + pencarian ikut cek WO
//   - Tab Riwayat  : chip "WO ..." di tiap kartu, + chip "WO AMBIL ..."
//
// Penyimpanan & pengecekan akhir tetap di database (sql/03-wo.sql),
// pengecekan di sini hanya supaya user langsung tahu kalau salah ketik.
// File ini dimuat SETELAH script.js (pakai parts, esc, hl, statusBadge,
// selectAmbilPart dari sana).
// =====================================================================

const PANJANG_WO = 12;
const POLA_WO = /^[0-9]{12}$/;          // 12 angka, sama dengan PANJANG_WO
const CONTOH_WO = '200012345678';
const PESAN_WO_SALAH = `Format WO harus ${PANJANG_WO} angka, cth: ${CONTOH_WO}`;
const MIN_KETIK_SARAN_WO = 2;   // saran part baru muncul setelah 2 angka diketik

const IKON_PANAH_WO = '<svg class="wo-panah" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12h14"/><path d="m13 6 6 6-6 6"/></svg>';


// ---------- Bantuan umum ----------

// Ambil isi kolom WO (tanpa spasi). Kosong -> ''.
function bacaWo(idKolom){
  const el = document.getElementById(idKolom);
  return el ? el.value.trim() : '';
}

// WO kosong dianggap benar (WO tidak wajib). Kalau diisi, harus sesuai format.
function woBenar(wo){
  return wo === '' || POLA_WO.test(wo);
}


// ---------- Tampilan ----------

// Isi sel WO di tabel stok (desktop). Kosong ditampilkan "-".
function selWoHtml(p, q){
  return p.wo ? `<span class="mono">${hl(p.wo, q)}</span>` : '<span class="wo-nil">-</span>';
}

// Baris kecil "WO 22xxxxxxx" di sel deskripsi (tampilan HP). Kosong = tidak ditampilkan.
function barisWoHpHtml(p, q){
  return p.wo ? `<span class="m-wo">WO <span class="mono">${hl(p.wo, q)}</span></span>` : '';
}

// Chip WO di kartu riwayat:
//   tanpa WO           -> [WO –]
//   WO biasa           -> [WO 200012345678]
//   transfer ganti WO  -> [WO 200039220 -> 200046102]  (yang lama dicoret)
function chipWoHtml(t){
  if(!t.wo && !t.wo_lama){
    return '<span class="wo-chip kosong"><b>WO</b><span>–</span></span>';
  }
  const lama = t.wo_lama ? `<span class="mono lama">${esc(t.wo_lama)}</span>${IKON_PANAH_WO}` : '';
  return `<span class="wo-chip"><b>WO</b>${lama}<span class="mono">${esc(t.wo || '–')}</span></span>`;
}

// Chip WO pengambilan di kartu riwayat Ambil. Kosong = tidak ditampilkan.
function chipWoAmbilHtml(t){
  if(!t.wo_ambil) return '';
  return `<span class="wo-chip"><b>WO AMBIL</b><span class="mono">${esc(t.wo_ambil)}</span></span>`;
}


// ---------- Tab Ambil: ketik WO -> saran part ----------

function sarankanPartDariWo(){
  const q = bacaWo('ax_wo');
  const kotak = document.getElementById('ax_wo_matches');
  if(q.length < MIN_KETIK_SARAN_WO){ kotak.innerHTML = ''; return; }

  const cocok = parts.filter(p => p.wo && p.wo.includes(q));
  if(cocok.length === 0){
    kotak.innerHTML = '<div class="wo-tidak-ada">Tidak ada part dengan WO ini.</div>';
    return;
  }
  // WO lengkap dan hanya satu part -> langsung dipilih, tidak perlu klik
  if(cocok.length === 1 && cocok[0].wo === q){
    pilihPartDariWo(cocok[0].id);
    return;
  }
  kotak.innerHTML = `<div class="suggest-scroll">` + cocok.map(p => `
    <button type="button" class="btn btn-outline saran-wo" onclick="pilihPartDariWo('${p.id}')">
      <span class="mono">${hl(p.wo, q)}</span> — ${esc(p.desc)}
      <span class="saran-wo-info"><span class="mono">${esc(p.pn)}</span> · ${esc(p.unit)} · ${esc(p.loc || '-')} · stok ${p.qty} ${statusBadge(p.status)}</span>
    </button>`).join('') + `</div>`;
}

function pilihPartDariWo(id){
  document.getElementById('ax_wo_matches').innerHTML = '';
  selectAmbilPart(id);   // isi Parts Number + kartu part (script.js)
  document.getElementById('ax_qty').focus();
}

document.getElementById('ax_wo').addEventListener('input', sarankanPartDariWo);


// ---------- Tab Transfer ----------

// Setelah part dipilih: kolom WO dikosongkan, placeholder menunjukkan WO
// yang sekarang (kalau dibiarkan kosong, WO itu yang ikut pindah).
function siapkanWoTransfer(p){
  const kolom = document.getElementById('tf_wo');
  kolom.value = '';
  kolom.placeholder = p && p.wo ? p.wo : 'cth: ' + CONTOH_WO;
}
