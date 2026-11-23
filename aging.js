// =====================================================================
// aging.js -- Aging komponen di tab Stok
//
// Aging = jumlah hari part berada di status sekarang (RFU / NOT RFU).
// Tanggal mulainya (aging_sejak) diatur database (sql/04-aging.sql):
// hari 0 = tanggal input, dan kembali ke 0 setiap status berganti.
// Di sini hanya menghitung jumlah hari dan menampilkannya, tanpa warna.
//
// File ini dimuat SETELAH script.js (pakai esc, getFilteredStokRows, dll).
// =====================================================================

const SATU_HARI_MS = 24 * 60 * 60 * 1000;
const URUT_AGING_TERLAMA = 'aging';   // nilai opsi di <select id="stok_urut">


// ---------- Hitung ----------

// Jam 00:00 di hari yang sama (waktu HP), supaya hitungan per tanggal,
// bukan per 24 jam. Input jam 23:00 kemarin = 1 hari hari ini.
function awalHari(tanggal){
  const d = new Date(tanggal);
  d.setHours(0, 0, 0, 0);
  return d;
}

// Part yang stoknya habis atau tidak punya tanggal -> tidak ada aging (null).
function hariAging(p){
  if(!p.aging_sejak || Number(p.qty) <= 0) return null;
  const selisih = awalHari(Date.now()) - awalHari(p.aging_sejak);
  return Math.max(0, Math.round(selisih / SATU_HARI_MS));
}

// Format tanggal dd/mm/yyyy
function tanggalAging(p){
  const d = new Date(p.aging_sejak);
  const dua = n => String(n).padStart(2, '0');
  return `${dua(d.getDate())}/${dua(d.getMonth() + 1)}/${d.getFullYear()}`;
}


// ---------- Tampilan ----------

// Sel kolom Aging (desktop): "12 hari" + tanggal mulai di bawahnya
function selAgingHtml(p){
  const hari = hariAging(p);
  if(hari === null) return '<span class="ag-nil">-</span>';
  return `<b>${hari}</b> hari<span class="ag-tgl mono">${tanggalAging(p)}</span>`;
}

// Teks kecil di bawah qty (tampilan HP)
function agingHpHtml(p){
  const hari = hariAging(p);
  return hari === null ? '' : `<span class="m-aging"><b>${hari}</b> hari</span>`;
}

// Baris "Aging" di panel detail part
function agingPanelHtml(p){
  const hari = hariAging(p);
  return hari === null ? '-' : `${hari} hari <span class="ag-tgl-panel">sejak ${tanggalAging(p)}</span>`;
}


// ---------- Urutan ----------

// Aging terlama di atas. Part tanpa aging (stok habis) ditaruh paling bawah.
function urutkanAgingTerlama(rows){
  const nilai = p => hariAging(p) === null ? -1 : hariAging(p);
  return rows.slice().sort((a, b) => nilai(b) - nilai(a));
}

function pakaiUrutanStok(rows){
  const urut = document.getElementById('stok_urut').value;
  return urut === URUT_AGING_TERLAMA ? urutkanAgingTerlama(rows) : rows;
}
