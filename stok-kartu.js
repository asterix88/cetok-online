// =====================================================================
// stok-kartu.js -- Kartu stok untuk layar HP (< 900px)
//
// Sesuai mockup hp-stok.png:
//   kiri  : nama part, parts number, unit + status, lokasi · WO
//   kanan : qty besar, aging "N hari" + tanggal mulai aging
// Desktop tetap memakai tabel. Keduanya diisi oleh renderStokSheet()
// (script.js); CSS yang memilih mana yang tampil.
// File ini dimuat SETELAH script.js, wo.js, dan aging.js.
// =====================================================================

function kartuStokHtml(p, q){
  const lokasi = esc(p.loc || '-');
  const wo = p.wo ? ` · WO <span class="mono">${hl(p.wo, q)}</span>` : '';
  const hari = hariAging(p);
  const aging = hari === null ? '' : `
      <div class="sk-aging"><b>${hari}</b> hari</div>
      <div class="sk-tgl mono">${tanggalAging(p)}</div>`;
  const catatan = p.remarks ? `<div class="sk-baris sk-catatan">${esc(p.remarks)}</div>` : '';

  return `
    <div class="sk" data-id="${esc(p.id)}" tabindex="0">
      <div class="sk-kiri">
        <div class="sk-nama">${hl(p.desc, q)}</div>
        <div class="sk-pn mono">${fmtPN(p.pn, q)}</div>
        <div class="sk-baris"><span class="mono">${esc(p.unit)}</span> ${statusBadge(p.status)}</div>
        <div class="sk-baris">${lokasi}${wo}</div>
        ${catatan}
      </div>
      <div class="sk-kanan">
        <div class="sk-qty ${p.qty <= 0 ? 'habis' : ''}">${p.qty}</div>
        ${aging}
      </div>
    </div>`;
}

// Ketuk kartu -> buka panel aksi part (sama seperti klik baris tabel)
const elStokKartu = document.getElementById('stokKartu');
elStokKartu.addEventListener('click', (e)=>{
  const kartu = e.target.closest('.sk[data-id]');
  if(kartu) openPartSheet(kartu.dataset.id);
});
elStokKartu.addEventListener('keydown', (e)=>{
  if((e.key === 'Enter' || e.key === ' ') && e.target.matches('.sk[data-id]')){
    e.preventDefault(); openPartSheet(e.target.dataset.id);
  }
});
