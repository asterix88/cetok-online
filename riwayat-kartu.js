// =====================================================================
// riwayat-kartu.js -- Kartu Riwayat (HP & desktop)
//
// Sesuai mockup riwayat-desktop.png dan riwayat-hp.png:
//   - ikon jenis (Input / Ambil / Transfer) di kiri
//   - nama part + parts number, label unit / status / WO
//   - lokasi (transfer: asal -> tujuan), keterangan, nama + NRP, waktu
//   - jenis + qty berwarna di kanan, tombol "..." (Edit) khusus admin
//   - filter jenis berupa tombol Semua / Input / Ambil / Transfer
//
// Bentuk kartunya sama; CSS (tata-letak.css) yang menyesuaikan ukuran
// untuk HP. File ini dimuat SETELAH script.js dan wo.js.
// =====================================================================

// Transfer dicatat sebagai baris 'keluar' dengan keterangan
// "TRANSFER KE <lokasi tujuan> (<status>)" + " - <catatan>" kalau ada.
const AWALAN_TRANSFER = 'TRANSFER KE ';
const POLA_KETERANGAN_TRANSFER = /^TRANSFER KE (.+?) \((RFU|NOT RFU)\)(?: - (.*))?$/;

const JENIS_RIWAYAT = {
  input:    { label: 'Input',    tanda: '+' },
  ambil:    { label: 'Ambil',    tanda: '-' },
  transfer: { label: 'Transfer', tanda: ''  },
};

const IKON_JENIS = {
  input:    '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="M12 5v14M5 12h14"/></svg>',
  ambil:    '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3v10"/><path d="m8 7 4-4 4 4"/><path d="M4 13v6a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-6"/></svg>',
  transfer: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="m17 2 4 4-4 4"/><path d="M3 11v-1a4 4 0 0 1 4-4h14"/><path d="m7 22-4-4 4-4"/><path d="M21 13v1a4 4 0 0 1-4 4H3"/></svg>',
};
const IKON_PANAH_LOKASI = '<svg class="rk-panah" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12h14"/><path d="m13 6 6 6-6 6"/></svg>';
const IKON_LAINNYA = '<svg viewBox="0 0 24 24" fill="currentColor"><circle cx="5" cy="12" r="1.6"/><circle cx="12" cy="12" r="1.6"/><circle cx="19" cy="12" r="1.6"/></svg>';


// ---------- Bantuan ----------

// 'input' | 'ambil' | 'transfer'
function jenisRiwayat(t){
  if(t.type === 'masuk') return 'input';
  return String(t.note || '').startsWith(AWALAN_TRANSFER) ? 'transfer' : 'ambil';
}

// Pecah keterangan transfer jadi lokasi tujuan + catatan.
// Kalau formatnya tidak dikenali, seluruh keterangan dianggap catatan.
function bacaKeteranganTransfer(note){
  const cocok = POLA_KETERANGAN_TRANSFER.exec(note || '');
  if(!cocok) return { tujuan: '', catatan: note || '' };
  return { tujuan: cocok[1], catatan: cocok[3] || '' };
}

// "23/11/2026 · 13.20"
function waktuRiwayat(ts){
  const d = new Date(ts);
  const dua = n => String(n).padStart(2, '0');
  return `${dua(d.getDate())}/${dua(d.getMonth() + 1)}/${d.getFullYear()} · ${dua(d.getHours())}.${dua(d.getMinutes())}`;
}


// ---------- Kartu ----------

function kartuRiwayatHtml(t){
  const jenis = jenisRiwayat(t);
  const info = JENIS_RIWAYAT[jenis];

  let lokasi = esc(t.loc || '-');
  let catatan = t.note || '';
  if(jenis === 'transfer'){
    const tf = bacaKeteranganTransfer(t.note);
    if(tf.tujuan) lokasi += IKON_PANAH_LOKASI + esc(tf.tujuan);
    catatan = tf.catatan;
  }

  const meta = [
    `<div>${ICON_PIN}<span>${lokasi}</span></div>`,
    catatan ? `<div>${ICON_NOTE}<span>${esc(catatan)}</span></div>` : '',
    t.nama ? `<div>${ICON_USER}<span>${esc(t.nama)}${t.nrp ? ` <em class="mono">${esc(t.nrp)}</em>` : ''}</span></div>` : '',
    `<div>${ICON_CLOCK}<span class="mono">${waktuRiwayat(t.ts)}</span></div>`,
  ].join('');

  return `
    <div class="rk">
      <div class="rk-ikon ${jenis}">${IKON_JENIS[jenis]}</div>
      <div class="rk-isi">
        <div class="rk-kepala">
          <div>
            <div class="rk-nama">${esc(t.desc)}</div>
            <div class="rk-pn mono">${esc(t.pn)}</div>
          </div>
          <div class="rk-qty ${jenis}"><span>${info.label}</span><b>${info.tanda}${t.qty}</b></div>
        </div>
        <div class="rk-label"><span class="rk-unit mono">${esc(t.unit)}</span>${statusBadge(t.status)}${chipWoHtml(t)}</div>
        <div class="rk-meta">${meta}</div>
      </div>
      ${isAdmin ? `<button type="button" class="rk-lainnya" onclick="openEditRiwayat('${t.id}')" aria-label="Edit riwayat" title="Edit">${IKON_LAINNYA}</button>` : ''}
    </div>`;
}


// ---------- Filter jenis (tombol) ----------
// Tombol hanya tampilan; nilai tetap disimpan di <select id="filterType">
// supaya loadRiwayatPage() tidak perlu diubah.

function tandaiTombolJenis(){
  const nilai = document.getElementById('filterType').value;
  document.querySelectorAll('#riwayatJenis button').forEach(b => b.classList.toggle('on', b.dataset.jenis === nilai));
}

document.querySelectorAll('#riwayatJenis button').forEach(b => {
  b.addEventListener('click', () => {
    const pilih = document.getElementById('filterType');
    pilih.value = b.dataset.jenis;
    pilih.dispatchEvent(new Event('change'));
    tandaiTombolJenis();
  });
});
document.getElementById('filterType').addEventListener('change', tandaiTombolJenis);
