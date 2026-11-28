// =====================================================================
// edit-baris.js -- Edit data stok langsung di baris (khusus admin)
//
// Desktop (tabel): ikon pensil di kolom paling kanan setiap baris.
// HP (kartu)     : ikon pensil di kanan kartu.
// Klik pensil -> kolom di baris itu jadi isian, pensil diganti 3 ikon:
//   ✓ simpan, ✗ batal, sampah = hapus (minta konfirmasi dulu).
//
// Simpan lewat RPC yang sudah ada: update_part, ubah_wo_part, delete_part
// (lihat runScript di script.js), plus ubah_aging_part (sql/08-ubah-aging.sql)
// untuk tanggal mulai aging, mis. kalau input ke web terlambat dari
// tanggal komponen berganti status.
// Hanya satu baris yang bisa diedit dalam satu waktu.
// File ini dimuat SETELAH script.js, wo.js, aging.js, dan stok-kartu.js.
// =====================================================================

const EB_IKON = {
  edit:   '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round"><path d="M12 20h9"/><path d="M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4Z"/></svg>',
  simpan: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M20 6 9 17l-5-5"/></svg>',
  batal:  '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round"><path d="M18 6 6 18M6 6l12 12"/></svg>',
  hapus:  '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round"><path d="M3 6h18"/><path d="M8 6V4h8v2"/><path d="M19 6l-1 14H6L5 6"/><path d="M10 11v6M14 11v6"/></svg>'
};

// Baris yang sedang diedit. draft = isian yang sudah diketik, supaya tidak
// hilang kalau tabel digambar ulang (mis. ada perubahan stok dari HP lain).
const ebState = { id: null, draft: null, tanyaHapus: false, sibuk: false };

function ebPart(){ return parts.find(p => String(p.id) === String(ebState.id)); }
function ebSedangEdit(id){ return ebState.id !== null && String(ebState.id) === String(id); }


// ---- Potongan HTML ----------------------------------------------------

function ebTombol(jenis, label){
  return `<button type="button" class="eb-btn ${jenis}" data-eb="${jenis}" aria-label="${label}" title="${label}">${EB_IKON[jenis]}</button>`;
}
function ebTombolBiasaHtml(){
  return `<span class="eb-tombol">${ebTombol('edit', 'Edit')}</span>`;
}
function ebTombolEditHtml(){
  return `<span class="eb-tombol">${ebTombol('simpan', 'Simpan')}${ebTombol('batal', 'Batal')}${ebTombol('hapus', 'Hapus')}</span>`;
}
function ebKonfirmasiHtml(){
  return `<span class="eb-konfirmasi">Hapus baris ini?
    <button type="button" class="eb-teks-btn" data-eb="batal-hapus">Batal</button>
    <button type="button" class="eb-teks-btn merah" data-eb="ya-hapus">Hapus</button></span>`;
}
function ebOpsiUnit(pilih){
  return ['Excavator', 'Bulldozer'].map(cat => `<optgroup label="${cat}">` +
    UNIT_MODELS.filter(u => u.cat === cat)
      .map(u => `<option value="${esc(u.code)}" ${u.code === pilih ? 'selected' : ''}>${esc(u.code)}</option>`).join('') +
    '</optgroup>').join('');
}
function ebOpsiStatus(pilih){
  return [['', 'Tanpa status'], ['RFU', 'RFU'], ['NOT RFU', 'NOT RFU']]
    .map(([v, t]) => `<option value="${v}" ${v === pilih ? 'selected' : ''}>${t}</option>`).join('');
}

// Tanggal 'yyyy-mm-dd' menurut jam HP/laptop (untuk isian type="date")
function ebTanggalIso(waktu){
  const d = new Date(waktu);
  const dua = n => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${dua(d.getMonth() + 1)}-${dua(d.getDate())}`;
}

// Satu isian. nama = kunci di draft (unit, pn, desc, status, wo, loc, qty, remarks, aging)
function ebIsian(nama, d, kelas, label){
  const k = `class="eb-in ${kelas}" data-isi="${nama}" aria-label="${label}"`;
  if(nama === 'unit')   return `<select ${k}>${ebOpsiUnit(d.unit)}</select>`;
  if(nama === 'status') return `<select ${k}>${ebOpsiStatus(d.status)}</select>`;
  if(nama === 'qty')    return `<input ${k} type="number" min="0" inputmode="numeric" value="${esc(d.qty)}">`;
  if(nama === 'wo')     return `<input ${k} inputmode="numeric" maxlength="${PANJANG_WO}" autocomplete="off" value="${esc(d.wo)}">`;
  if(nama === 'aging')  return `<input ${k} type="date" max="${ebTanggalIso(Date.now())}" value="${esc(d.aging)}">`;
  if(nama === 'loc')    return `<input ${k} list="loc_datalist" autocomplete="off" value="${esc(d.loc)}">`;
  return `<input ${k} autocomplete="off" value="${esc(d[nama])}">`;
}

// Draft awal = data baris saat pensil diklik
function ebDraftDari(p){
  return {
    unit: p.unit || '', pn: p.pn || '', desc: p.desc || '', status: (p.status || '').toUpperCase(),
    wo: p.wo || '', loc: p.loc || '', qty: String(p.qty ?? 0), remarks: p.remarks || '',
    aging: p.aging_sejak ? ebTanggalIso(p.aging_sejak) : ''
  };
}

// Desktop: isi kolom-kolom baris tabel yang sedang diedit
function ebIsiBarisTabel(tr){
  const d = ebState.draft;
  tr.classList.add('eb-edit');
  tr.querySelector('td.part-col').innerHTML =
    ebIsian('desc', d, 'desc', 'Parts description') + ebIsian('pn', d, 'pn', 'Parts number');
  tr.querySelector('td.unit-col').innerHTML = ebIsian('unit', d, 'unit', 'Unit');
  tr.querySelector('td.status-col').innerHTML = ebIsian('status', d, 'status', 'Status');
  tr.querySelector('td.wo-col').innerHTML = ebIsian('wo', d, 'wo', 'WO');
  tr.querySelector('td.loc').innerHTML = ebIsian('loc', d, 'lok', 'Lokasi');
  tr.querySelector('td.qty').innerHTML = ebIsian('qty', d, 'qty', 'Qty');
  tr.querySelector('td.ket-col').innerHTML = ebIsian('remarks', d, 'ket', 'Keterangan');
  tr.querySelector('td.ag-col').innerHTML = ebIsian('aging', d, 'tgl', 'Aging sejak');
  tr.querySelector('td.eb-aksi').innerHTML = ebTombolEditHtml();
  if(ebState.tanyaHapus){
    tr.insertAdjacentHTML('afterend',
      `<tr class="eb-konf" data-untuk="${esc(ebState.id)}"><td colspan="${tr.children.length}">${ebKonfirmasiHtml()}</td></tr>`);
  }
}

// HP: ganti isi kartu yang sedang diedit dengan form
function ebIsiKartu(kartu){
  const d = ebState.draft;
  const isian = (nama, label, penuh) =>
    `<label class="${penuh ? 'penuh' : ''}">${label}${ebIsian(nama, d, '', label)}</label>`;
  kartu.classList.add('eb-edit');
  kartu.innerHTML = `
    <div class="eb-form">
      ${isian('desc', 'Parts description', true)}
      ${isian('pn', 'Parts number', true)}
      ${isian('unit', 'Unit')}
      ${isian('status', 'Status')}
      ${isian('loc', 'Lokasi')}
      ${isian('qty', 'Qty')}
      ${isian('wo', 'WO')}
      ${isian('aging', 'Aging sejak')}
      ${isian('remarks', 'Keterangan', true)}
    </div>
    <div class="eb-kaki">${ebState.tanyaHapus ? ebKonfirmasiHtml() : ebTombolEditHtml()}</div>`;
}


// ---- Dipanggil dari renderStokSheet (script.js) -------------------------

// Sel kolom aksi untuk satu baris tabel (kosong kalau bukan admin)
function ebSelAksiHtml(){
  return isAdmin ? `<td class="eb-aksi">${ebTombolBiasaHtml()}</td>` : '';
}

// Setelah tabel & kartu digambar: tampilkan kolom aksi untuk admin, pasang
// pensil di kartu HP, dan buka lagi baris yang sedang diedit (kalau ada).
function ebSetelahRender(){
  document.getElementById('thAksi').hidden = !isAdmin;
  if(!isAdmin){ ebState.id = null; return; }

  document.querySelectorAll('#stokKartu .sk[data-id]').forEach(k => {
    k.insertAdjacentHTML('beforeend', ebTombolBiasaHtml());
  });

  if(ebState.id === null) return;
  if(!ebPart()){ ebTutup(); return; }   // baris sudah dihapus orang lain
  const tr = document.querySelector(`#stokTableBody tr[data-id="${CSS.escape(String(ebState.id))}"]`);
  const kartu = document.querySelector(`#stokKartu .sk[data-id="${CSS.escape(String(ebState.id))}"]`);
  if(tr) ebIsiBarisTabel(tr);
  if(kartu) ebIsiKartu(kartu);
}


// ---- Aksi -------------------------------------------------------------

function ebMulai(id){
  ebState.id = id;
  ebState.draft = ebDraftDari(ebPart());
  ebState.tanyaHapus = false;
  renderStokSheet();
  // fokus ke isian pertama yang terlihat (tabel di desktop, kartu di HP)
  const isian = [...document.querySelectorAll('.eb-edit [data-isi]')].find(el => el.offsetParent !== null);
  if(isian) isian.focus();
}

function ebTutup(){
  ebState.id = null; ebState.draft = null; ebState.tanyaHapus = false;
  renderStokSheet();
}

function ebTanyaHapus(ya){
  ebState.tanyaHapus = ya;
  renderStokSheet();
}

// Cek isian sebelum disimpan. Mengembalikan pesan salah, atau '' kalau aman.
function ebCekDraft(d){
  if(!d.pn.trim() || !d.desc.trim()) return 'Parts number dan description wajib diisi.';
  const qty = Number(d.qty);
  if(d.qty === '' || !Number.isInteger(qty) || qty < 0) return 'Qty harus angka bulat 0 atau lebih.';
  if(!woBenar(d.wo.trim())) return PESAN_WO_SALAH;
  if(!d.aging) return 'Tanggal aging wajib diisi.';
  if(d.aging > ebTanggalIso(Date.now())) return 'Tanggal aging tidak boleh lewat dari hari ini.';
  return '';
}

async function ebJalankan(kerja){
  if(ebState.sibuk) return;
  ebState.sibuk = true;
  try{
    const { data, pesan } = await kerja();
    parts = data.parts;
    ebState.id = null; ebState.draft = null; ebState.tanyaHapus = false;
    toast(pesan);
    populateLocationFilter();
    render();
  }catch(e){
    toast(e.message || 'Gagal menyimpan. Cek koneksi lalu coba lagi.', 'error');
  }finally{
    ebState.sibuk = false;
  }
}

function ebSimpan(){
  const p = ebPart(), d = ebState.draft;
  const salah = ebCekDraft(d);
  if(salah){ toast(salah, 'error'); return; }
  ebJalankan(async ()=>{
    let data = await runScript('updatePart', p.id, d.unit, d.pn.trim(), d.desc.trim(),
      d.loc.trim(), Number(d.qty), d.status, d.remarks.trim());
    // WO disimpan lewat RPC terpisah (ubah_wo_part), hanya kalau berubah
    const wo = d.wo.trim();
    if(wo !== (p.wo || '')) data = await runScript('ubahWoPart', p.id, wo);
    // Aging disimpan paling akhir, supaya tidak tertimpa reset otomatis
    // saat status berganti (trigger di sql/04-aging.sql)
    const agingAwal = p.aging_sejak ? ebTanggalIso(p.aging_sejak) : '';
    if(d.aging !== agingAwal) data = await runScript('ubahAgingPart', p.id, d.aging);
    return { data, pesan: 'Perubahan data stok tersimpan' };
  });
}

function ebHapus(){
  const p = ebPart();
  ebJalankan(async ()=>({
    data: await runScript('deletePart', p.id),
    pesan: `Berhasil menghapus ${p.pn}`
  }));
}


// ---- Event ------------------------------------------------------------

// Cari id baris dari elemen yang diklik (baris tabel, baris konfirmasi, atau kartu)
function ebIdDari(el){
  const konf = el.closest('tr.eb-konf');
  if(konf) return konf.dataset.untuk;
  const baris = el.closest('#stokTableBody tr[data-id], #stokKartu .sk[data-id]');
  return baris ? baris.dataset.id : null;
}

// Dipasang di fase capture supaya klik tombol / isian tidak ikut
// membuka panel detail part (listener klik baris ada di script.js).
document.getElementById('tab-stok').addEventListener('click', (e)=>{
  const id = ebIdDari(e.target);
  if(id === null) return;
  const tombol = e.target.closest('[data-eb]');
  if(!tombol && !ebSedangEdit(id)) return;   // klik baris biasa -> panel detail
  e.stopPropagation();
  if(!tombol) return;

  switch(tombol.dataset.eb){
    case 'edit':        ebMulai(id); break;
    case 'batal':       ebTutup(); break;
    case 'simpan':      ebSimpan(); break;
    case 'hapus':       ebTanyaHapus(true); break;
    case 'batal-hapus': ebTanyaHapus(false); break;
    case 'ya-hapus':    ebHapus(); break;
  }
}, true);

// Simpan ketikan ke draft
document.getElementById('tab-stok').addEventListener('input', (e)=>{
  const nama = e.target.dataset && e.target.dataset.isi;
  if(nama && ebState.draft) ebState.draft[nama] = e.target.value;
});

// Enter = simpan, Esc = batal (selama kursor ada di isian edit)
document.getElementById('tab-stok').addEventListener('keydown', (e)=>{
  if(!e.target.dataset || !e.target.dataset.isi) return;
  e.stopPropagation();   // jangan sampai Enter/Spasi membuka panel detail
  if(e.key === 'Enter'){ e.preventDefault(); ebSimpan(); }
  if(e.key === 'Escape'){ e.preventDefault(); ebTutup(); }
}, true);
