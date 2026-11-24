// =====================================================================
// form-desktop.js -- Form Ambil / Transfer / Input versi desktop
//
// Sesuai mockup desktop-ambil.png, desktop-transfer.png, desktop-input.png:
//   - kiri  : form dua kolom per bagian, qty pakai tombol - / +,
//             status pakai tombol RFU / NOT RFU, nama + NRP di bawah
//   - kanan : panel ringkasan (part dipilih / perpindahan / stok yang ada)
//
// Kolom asli (<input>, <select>) tetap dipakai script.js untuk menyimpan;
// file ini hanya menambah tampilan. Di HP panel kanan, tombol status, dan
// tombol - / + disembunyikan lewat CSS (tata-letak.css).
// File ini dimuat SETELAH script.js, wo.js, dan aging.js.
// =====================================================================

const QTY_MIN = 1;


// ---------- Bantuan ----------

function nilai(id){
  return document.getElementById(id).value.trim();
}

function samaTeks(a, b){
  return String(a || '').trim().toLowerCase() === String(b || '').trim().toLowerCase();
}

function partById(id){
  return id ? parts.find(p => String(p.id) === String(id)) : null;
}

// "214 hari" + tanggal, atau "-" kalau stok kosong
function agingTeksHtml(p){
  const hari = hariAging(p);
  if(hari === null) return '-';
  return `<b>${hari}</b> hari<span class="fp-sub mono">${tanggalAging(p)}</span>`;
}

function baris(label, isi){
  return `<div class="fp-baris"><span>${label}</span><span>${isi}</span></div>`;
}

function labelPart(p){
  return `<span class="rk-unit mono">${esc(p.unit)}</span>${statusBadge(p.status)}${chipWoHtml({ wo: p.wo })}`;
}

function kotakPartHtml(judul, p){
  return `
    <div class="fp-bagian">
      <div class="fp-judul">${judul}</div>
      <div class="fp-nama">${esc(p.desc)}</div>
      <div class="fp-pn mono">${esc(p.pn)}</div>
      <div class="fp-label">${labelPart(p)}</div>
    </div>`;
}

function panelKosongHtml(judul){
  return `<div class="fp-bagian"><div class="fp-judul">${judul}</div><div class="fp-kosong">Belum ada part dipilih.</div></div>`;
}


// ---------- Panel Ambil ----------

function panelAmbilHtml(){
  const p = partById(ambilSelectedPartId);
  if(!p) return panelKosongHtml('Part dipilih');

  const qty = Number(nilai('ax_qty'));
  const sisa = qty > 0 ? p.qty - qty : null;
  const sisaHtml = sisa === null ? '-' : `<b class="${sisa < 0 ? 'fp-kurang' : ''}">${sisa}</b>`;

  return kotakPartHtml('Part dipilih', p) + `
    <div class="fp-bagian">
      ${baris('Stok tersedia', `<b>${p.qty}</b>`)}
      ${baris('Setelah diambil', sisaHtml)}
      ${baris('Lokasi', esc(p.loc || '-'))}
      ${baris('Aging', agingTeksHtml(p))}
    </div>`;
}


// ---------- Panel Transfer ----------

// Baris stok tujuan yang sudah ada (kunci sama seperti di database)
function barisTujuanTransfer(p, lokasi, status, wo){
  return parts.find(x =>
    x.unit === p.unit && samaTeks(x.pn, p.pn) && samaTeks(x.loc, lokasi)
    && x.status === status && (x.wo || '') === (wo || ''));
}

// Aging di tujuan mengikuti aturan sql/04-aging.sql:
// baris tujuan sudah ada -> aging-nya tetap; status sama -> ikut dibawa; beda -> 0
function agingTujuanHtml(p, lokasi, status, wo){
  const tujuan = lokasi ? barisTujuanTransfer(p, lokasi, status, wo) : null;
  if(tujuan) return agingTeksHtml(tujuan);
  if(status === p.status) return agingTeksHtml(p);
  return '<b>0</b> hari';
}

function titikRuteHtml(kunci, lokasi, status, woHtml, tujuan){
  return `
    <div class="fp-titik"><i class="${tujuan ? 'tujuan' : ''}"></i>${tujuan ? '' : '<s></s>'}</div>
    <div class="fp-rute-isi">
      <div class="fp-judul kecil">${kunci}</div>
      <div class="fp-lokasi">${lokasi}</div>
      <div class="fp-label">${statusBadge(status)}${woHtml}</div>
    </div>`;
}

function panelTransferHtml(){
  const p = partById(tfSelectedPartId);
  if(!p) return panelKosongHtml('Part dipilih');

  const lokasi = nilai('tf_loc').toUpperCase();
  const status = document.getElementById('tf_status').value;
  const woBaru = bacaWo('tf_wo');
  const woTujuan = woBaru || p.wo || '';
  const woLama = woTujuan !== (p.wo || '') ? p.wo : null;
  const qty = Number(nilai('tf_qty'));

  const rute = `
    <div class="fp-bagian">
      <div class="fp-judul">Perpindahan</div>
      <div class="fp-rute">
        ${titikRuteHtml('Dari', esc(p.loc || '-'), p.status, chipWoHtml({ wo: p.wo }), false)}
        ${titikRuteHtml('Ke', lokasi ? esc(lokasi) : '<span class="fp-kosong">-</span>', status, chipWoHtml({ wo: woTujuan, wo_lama: woLama }), true)}
      </div>
    </div>`;

  return kotakPartHtml('Part dipilih', p) + rute + `
    <div class="fp-bagian">
      ${baris('Qty dipindah', qty > 0 ? `<b class="${qty > p.qty ? 'fp-kurang' : ''}">${qty}</b> dari ${p.qty}` : `- dari ${p.qty}`)}
      ${baris('Aging di tujuan', agingTujuanHtml(p, lokasi, status, woTujuan))}
    </div>`;
}


// ---------- Panel Input ----------

function panelInputHtml(){
  const unit = document.getElementById('in_unit').value;
  const pn = nilai('in_pn');
  const ada = pn ? parts.filter(p => p.unit === unit && samaTeks(p.pn, pn)) : [];
  if(ada.length === 0){
    return `<div class="fp-bagian"><div class="fp-judul">Sudah ada di stok</div><div class="fp-kosong">Belum ada.</div></div>`;
  }

  // Baris yang akan bertambah qty-nya kalau disimpan (lokasi, status, WO sama)
  const lokasi = nilai('in_loc'), status = document.getElementById('in_status').value, wo = bacaWo('in_wo');
  const daftar = ada.map(p => {
    const cocok = samaTeks(p.loc, lokasi) && p.status === status && (p.wo || '') === wo;
    return `
      <div class="fp-ada ${cocok ? 'cocok' : ''}">
        <div><b class="fp-ada-lok">${esc(p.loc || '-')}</b><div class="fp-label">${statusBadge(p.status)}${chipWoHtml({ wo: p.wo })}</div></div>
        <div class="fp-ada-qty">${p.qty}</div>
      </div>`;
  }).join('');

  return `
    <div class="fp-bagian">
      <div class="fp-judul">Sudah ada di stok</div>
      <div class="fp-nama">${esc(ada[0].desc)}</div>
      <div class="fp-pn mono">${esc(ada[0].pn)} · ${esc(unit)}</div>
    </div>
    <div class="fp-bagian">${daftar}</div>`;
}


// ---------- Nama + NRP (dari akun login, auth.js) ----------

function isiNamaDesktop(){
  if(typeof karyawanLogin === 'undefined' || !karyawanLogin) return;
  document.querySelectorAll('.who-v2').forEach(el => {
    el.querySelector('.who-ini').textContent = inisial(karyawanLogin.nama);
    el.querySelector('.who-nama').textContent = karyawanLogin.nama;
    el.querySelector('.who-nrp').textContent = karyawanLogin.nrp;
  });
}


// ---------- Tombol status RFU / NOT RFU ----------
// Nilai tetap disimpan di <select> (tf_status / in_status).

function tandaiTombolStatusForm(){
  document.querySelectorAll('.seg-status').forEach(grup => {
    const pilih = document.getElementById(grup.dataset.untuk).value;
    grup.querySelectorAll('button').forEach(b => b.classList.toggle('on', b.dataset.nilai === pilih));
  });
}

document.querySelectorAll('.seg-status button').forEach(b => {
  b.addEventListener('click', () => {
    const pilih = document.getElementById(b.parentElement.dataset.untuk);
    pilih.value = b.dataset.nilai;
    pilih.dispatchEvent(new Event('change', { bubbles: true }));
  });
});


// ---------- Tombol qty - / + ----------

document.querySelectorAll('.qs-btn').forEach(b => {
  b.addEventListener('click', () => {
    const kolom = document.getElementById(b.dataset.untuk);
    const baru = Math.max(QTY_MIN, (Number(kolom.value) || 0) + Number(b.dataset.langkah));
    kolom.value = baru;
    kolom.dispatchEvent(new Event('input', { bubbles: true }));
  });
});


// ---------- Gambar ulang ----------
// Dipanggil tiap ada isian berubah, dan dari script.js setelah part
// dipilih / form dikosongkan (nilai yang diubah lewat kode tidak memicu event).

function perbaruiFormDesktop(){
  document.getElementById('ax_panel').innerHTML = panelAmbilHtml();
  document.getElementById('tf_panel').innerHTML = panelTransferHtml();
  document.getElementById('in_panel').innerHTML = panelInputHtml();
  tandaiTombolStatusForm();
  isiNamaDesktop();
}

['input', 'change'].forEach(jenis => {
  document.addEventListener(jenis, e => {
    if(e.target.closest && e.target.closest('.form-v2')) perbaruiFormDesktop();
  });
});
perbaruiFormDesktop();
