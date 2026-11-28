// =====================================================================
// log-admin.js -- Menu "Log Admin" (khusus admin)
//
// Menampilkan catatan setiap perubahan yang dilakukan admin:
//   Edit Stok, Ubah WO, Hapus Part, Edit Riwayat.
// Tiap catatan berisi: waktu, nama + NRP admin, aksi, part (unit + PN),
// dan kolom yang berubah (nilai lama -> baru). Untuk Hapus Part, yang
// ditampilkan isi terakhir baris sebelum dihapus.
//
// Catatan ditulis oleh database (lihat sql/08-log-admin.sql), bukan oleh
// web, jadi tidak bisa terlewat. Dari web, log hanya bisa dibaca.
//
// File ini dimuat SETELAH script.js (butuh sb, esc, isAdmin, ICON_*).
// =====================================================================

const LOG_PAGE_SIZE = 20;

const AKSI_LOG = {
  edit_stok:    { label: 'Edit Stok' },
  ubah_wo:      { label: 'Ubah WO' },
  hapus_part:   { label: 'Hapus Part' },
  edit_riwayat: { label: 'Edit Riwayat' },
};

// Nama kolom di database -> label yang tampil di kartu
const LABEL_KOLOM_LOG = {
  unit: 'Unit', pn: 'Parts Number', desc: 'Deskripsi', loc: 'Lokasi',
  qty: 'Qty', status: 'Status', remarks: 'Remarks', wo: 'WO',
  note: 'Keterangan', nama: 'Nama',
};

const IKON_AKSI_LOG = {
  edit_stok:    '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M4 20h4L19 9l-4-4L4 16v4Z"/><path d="m13.5 6.5 4 4"/></svg>',
  ubah_wo:      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M5 9h14M5 15h14M10 4 8 20M16 4l-2 16"/></svg>',
  hapus_part:   '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M4 7h16"/><path d="M10 11v6M14 11v6"/><path d="M6 7l1 13h10l1-13"/><path d="M9 7V4h6v3"/></svg>',
  edit_riwayat: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 21a9 9 0 1 1 9-9"/><path d="M12 7v5l3 2"/><path d="M15 21h2l4-4-2-2-4 4v2Z"/></svg>',
};
const IKON_PANAH_LOG = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12h14"/><path d="m13 6 6 6-6 6"/></svg>';

let logPage = 1;
let logRows = [];
let logTotal = 0;


// ---------- Menu hanya untuk admin ----------
// Dipanggil dari bukaAplikasi() (auth.js) setiap kali karyawan masuk.
function aturMenuLogAdmin(){
  document.getElementById('tabBtnLog').hidden = !isAdmin;
  if(!isAdmin && document.body.dataset.tab === 'log') switchTab('stok');
}


// ---------- Ambil data ----------

async function loadLogPage(page){
  const { data, error } = await sb.rpc('get_log_admin', {
    p_page: page,
    p_page_size: LOG_PAGE_SIZE,
    p_dari: document.getElementById('log_dari').value || null,
    p_sampai: document.getElementById('log_sampai').value || null,
    p_nrp: document.getElementById('log_admin').value || null,
  });
  if(error){ toast('Gagal memuat log: ' + error.message); return; }

  logPage = page;
  logRows = data.rows || [];
  logTotal = data.total || 0;
  isiPilihanAdmin(data.admin || []);
  renderLog();
}

// Pilihan "Semua Admin" diisi dari admin yang pernah tercatat di log
function isiPilihanAdmin(daftar){
  const el = document.getElementById('log_admin');
  const dipilih = el.value;
  el.innerHTML = '<option value="">Semua Admin</option>' +
    daftar.map(a => `<option value="${esc(a.nrp)}">${esc(a.nama)}</option>`).join('');
  el.value = dipilih;
}


// ---------- Kartu ----------

function nilaiLog(v){
  if(v === null || v === undefined || v === '') return '<i class="lg-kosong">kosong</i>';
  return esc(String(v));
}

// Satu baris perubahan: "Lokasi   R-03 -> R-05"
// Untuk Hapus Part hanya nilai lama (isi terakhir) yang ditampilkan.
function barisPerubahanHtml(p, hapus){
  const label = LABEL_KOLOM_LOG[p.kolom] || p.kolom;
  const nilai = hapus
    ? `<span>${nilaiLog(p.lama)}</span>`
    : `<span class="lg-lama">${nilaiLog(p.lama)}</span>${IKON_PANAH_LOG}<span>${nilaiLog(p.baru)}</span>`;
  return `<div class="lg-baris"><dt>${label}</dt><dd>${nilai}</dd></div>`;
}

function kartuLogHtml(r){
  const aksi = AKSI_LOG[r.aksi] || { label: r.aksi };
  const hapus = r.aksi === 'hapus_part';
  return `
    <div class="rk lg">
      <div class="rk-ikon lg-ikon">${IKON_AKSI_LOG[r.aksi] || ''}</div>
      <div class="rk-isi">
        <div class="rk-kepala">
          <div>
            <div class="rk-nama">${esc(r.desc || '-')}</div>
            <div class="rk-pn mono">${esc(r.pn || '-')}</div>
          </div>
          <div class="lg-aksi${hapus ? ' hapus' : ''}">${aksi.label}</div>
        </div>
        ${r.unit ? `<div class="rk-label"><span class="rk-unit mono">${esc(r.unit)}</span></div>` : ''}
        ${hapus ? '<div class="lg-judul">Isi sebelum dihapus</div>' : ''}
        <dl class="lg-perubahan">${(r.perubahan || []).map(p => barisPerubahanHtml(p, hapus)).join('')}</dl>
        <div class="rk-meta">
          <div>${ICON_USER}<span>${esc(r.nama)} <em class="mono">${esc(r.nrp)}</em></span></div>
          <div>${ICON_CLOCK}<span class="mono">${waktuRiwayat(r.waktu)}</span></div>
        </div>
      </div>
    </div>`;
}

function renderLog(){
  const el = document.getElementById('logList');
  if(logRows.length === 0){
    el.innerHTML = `<div class="empty"><div class="big">${ICON_NOTE}</div>Belum ada perubahan oleh admin.</div>`;
    document.getElementById('logPagination').innerHTML = '';
    return;
  }
  el.innerHTML = logRows.map(kartuLogHtml).join('');
  const jumlahHalaman = Math.max(1, Math.ceil(logTotal / LOG_PAGE_SIZE));
  renderPaginationControls('logPagination', logPage, jumlahHalaman, logTotal, 'catatan', loadLogPage);
}


// ---------- Pasang event ----------

document.getElementById('tabBtnLog').addEventListener('click', () => loadLogPage(1));
['log_dari', 'log_sampai', 'log_admin'].forEach(id => {
  document.getElementById(id).addEventListener('change', () => loadLogPage(1));
});
