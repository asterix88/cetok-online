// =====================================================================
// stok-filter.js -- Tombol status Semua / RFU / NOT RFU di tab Stok
//
// Tombol hanya tampilan; nilai tetap disimpan di <select id="stok_status_filter">
// supaya getFilteredStokRows() dan export Excel tidak perlu diubah.
// Tombol Lokasi / Unit / Urutan memakai daftar pilihan di script.js
// (openFilterSheet). File ini dimuat SETELAH script.js.
// =====================================================================

function tandaiStatusStok(){
  const nilai = document.getElementById('stok_status_filter').value;
  document.querySelectorAll('#stokStatus button').forEach(b => b.classList.toggle('on', b.dataset.status === nilai));
}

document.querySelectorAll('#stokStatus button').forEach(b => {
  b.addEventListener('click', () => {
    const pilih = document.getElementById('stok_status_filter');
    pilih.value = b.dataset.status;
    pilih.dispatchEvent(new Event('change'));
  });
});
