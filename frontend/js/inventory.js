(function () {
  const supabase = window.lave.supabase;
  const esc = window.lave.escape;
  let dresses = [];
  let units = [];
  const money = value => window.lave.currency(value);

  const statusBadge = status => {
    const label = String(status || '-');
    const key = label
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, '-')
      .replace(/^-|-$/g, '');

    return `<span class="badge status-${key}">${esc(label)}</span>`;
  };

  function render() {
    const query = document
      .getElementById('inventorySearch')
      .value
      .trim()
      .toLowerCase();

    const status = document.getElementById('inventoryStatus').value;

    const rows = dresses.filter(
      d =>
        (!status || d.status === status) &&
        `${d.dress_code} ${d.name} ${d.size} ${d.color}`
          .toLowerCase()
          .includes(query)
    );

    const inventoryBody = document.getElementById('inventoryRows');

    inventoryBody.closest('table').querySelector('thead').innerHTML =
      '<tr><th>Kode</th><th>Nama Model</th><th>Ukuran</th><th>Warna</th><th>Total</th><th>Tersedia</th><th>Disewa</th><th>Laundry</th><th>Repair</th><th>Tidak tersedia</th><th>Status</th><th>Kondisi</th><th>Aksi</th></tr>';

    inventoryBody.innerHTML = rows.length
      ? rows
          .map(
            d =>
              `<tr><td>${esc(d.dress_code)}</td><td>${esc(d.name)}</td><td>${esc(d.size)}</td><td class="${d.color === 'UNVERIFIED' ? 'variant-color-unverified' : ''}">${esc(d.color)}</td><td>${d.quantity}</td><td>${d.available_quantity}</td><td>${d.rented_quantity}</td><td>${d.laundry_quantity || 0}</td><td>${d.repair_quantity || 0}</td><td>${Number(d.not_available_quantity || 0) + Number(d.unclassified_quantity || 0)}</td><td>${statusBadge(d.status)}</td><td>${esc(d.condition || '-')}</td><td><div class="variant-actions"><button type="button" class="btn btn-light" data-detail-variant="${d.dress_variant_id}">Detail Unit</button><button type="button" class="btn btn-light" data-edit-status="${d.dress_variant_id}">Pilih Unit</button>${d.color === 'UNVERIFIED' ? `<button type="button" class="btn btn-light" data-reconcile-color="${d.dress_variant_id}">Stocktake Warna</button>` : ''}</div></td></tr>`
          )
          .join('')
      : '<tr><td colspan="13" class="empty">Tidak ada dress sesuai filter.</td></tr>';

    inventoryBody
      .querySelectorAll('[data-detail-variant]')
      .forEach(button =>
        button.addEventListener('click', () =>
          openDetail(Number(button.dataset.detailVariant))
        )
      );

    inventoryBody
      .querySelectorAll('[data-edit-status]')
      .forEach(button =>
        button.addEventListener('click', () =>
          openDetail(Number(button.dataset.editStatus))
        )
      );

    inventoryBody
      .querySelectorAll('[data-reconcile-color]')
      .forEach(button =>
        button.addEventListener('click', () =>
          openColorReconciliation(Number(button.dataset.reconcileColor))
        )
      );
  }

  async function openDetail(variantId) {
    const variant = dresses.find(
      item => Number(item.dress_variant_id) === variantId
    );

    if (!variant) return;

    const unitResult = await supabase
      .from('dress_units')
      .select('id,variant_id,unit_code,status,condition,notes')
      .eq('variant_id', variantId)
      .order('unit_code');

    if (unitResult.error) {
      window.lave.toast(unitResult.error.message, 'error');
      return;
    }

    units = unitResult.data || [];

    let modal = document.getElementById('inventoryDetailModal');

    if (!modal) {
      document.body.insertAdjacentHTML(
        'beforeend',
        '<div class="modal" id="inventoryDetailModal"><div class="modal-box"><div class="modal-head"><h3>Detail Varian dan Unit</h3><button type="button" class="close" id="closeInventoryDetail">×</button></div><div id="inventoryDetailContent" class="form-grid"></div><div class="table-wrap"><table><thead><tr><th>Unit</th><th>Status</th><th>Kondisi</th><th>Catatan</th><th>Aksi</th></tr></thead><tbody id="inventoryUnitRows"></tbody></table></div></div></div>'
      );

      modal = document.getElementById('inventoryDetailModal');

      document
        .getElementById('closeInventoryDetail')
        .addEventListener('click', () => modal.classList.remove('show'));
    }

    document.getElementById('inventoryDetailContent').innerHTML = `
      <div class="field"><label>Model</label><input readonly value="${esc(`${variant.dress_code} - ${variant.name}`)}"></div>
      <div class="field"><label>Ukuran / Warna</label><input readonly value="${esc(`${variant.size} / ${variant.color}`)}"></div>
      <div class="field"><label>Status</label><input readonly value="${esc(variant.status)}"></div>
      <div class="field"><label>Kondisi</label><input readonly value="${esc(variant.condition)}"></div>
      <div class="field"><label>Total</label><input readonly value="${variant.quantity}"></div>
      <div class="field"><label>Tersedia / Disewa</label><input readonly value="${variant.available_quantity} / ${variant.rented_quantity}"></div>
      <div class="field"><label>Laundry / Repair</label><input readonly value="${variant.laundry_quantity || 0} / ${variant.repair_quantity || 0}"></div>
      <div class="field"><label>Tidak tersedia / Belum terklasifikasi</label><input readonly value="${variant.not_available_quantity || 0} / ${variant.unclassified_quantity || 0}"></div>`;

    document.getElementById('inventoryUnitRows').innerHTML = units.length
      ? units
          .map(
            unit =>
              `<tr><td>${esc(unit.unit_code)}</td><td>${statusBadge(unit.status)}</td><td>${esc(unit.condition || '-')}</td><td>${esc(unit.notes || '-')}</td><td><button type="button" class="btn btn-light" data-edit-unit="${unit.id}" ${unit.status === 'Rented' ? 'disabled' : ''}>Edit Status</button></td></tr>`
          )
          .join('')
      : '<tr><td colspan="5" class="empty">Belum ada unit fisik.</td></tr>';

    document
      .getElementById('inventoryUnitRows')
      .querySelectorAll('[data-edit-unit]')
      .forEach(button =>
        button.addEventListener('click', () =>
          openStatusEditor(Number(button.dataset.editUnit))
        )
      );

    modal.dataset.variantId = String(variantId);
    modal.classList.add('show');
  }
 
  function openStatusEditor(unitId) {
    const unit = units.find(item => Number(item.id) === unitId);
    if (!unit) return;

    const parentVariant = dresses.find(
      item =>
        item.dress_variant_id ===
        Number(document.getElementById('inventoryDetailModal')?.dataset.variantId)
    );

    let modal = document.getElementById('inventoryStatusModal');

    if (!modal) {
      document.body.insertAdjacentHTML(
        'beforeend',
        '<div class="modal" id="inventoryStatusModal"><div class="modal-box"><div class="modal-head"><h3>Edit Status Unit</h3><button type="button" class="close" id="closeInventoryStatus">×</button></div><form id="inventoryStatusForm"><p id="inventoryStatusVariant"></p><div class="form-grid"><div class="field"><label>Status</label><select id="inventoryNewStatus" required><option value="">Pilih status</option><option>Available</option><option>Laundry</option><option>Repair</option><option>Not Available</option></select></div><div class="field"><label>Kondisi</label><select id="inventoryNewCondition"><option>Good</option><option>Fair</option><option>Damaged</option><option>Unusable</option></select></div><div class="field"><label>Catatan</label><input id="inventoryStatusNotes" required maxlength="500"></div></div><div class="form-actions"><button type="submit" class="btn btn-primary">Simpan</button></div></form></div></div>'
      );

      modal = document.getElementById('inventoryStatusModal');

      document
        .getElementById('closeInventoryStatus')
        .addEventListener('click', () => modal.classList.remove('show'));

      document
        .getElementById('inventoryStatusForm')
        .addEventListener('submit', async event => {
          event.preventDefault();

          const { error } = await supabase.rpc('update_dress_unit_status', {
            p_unit_id: Number(modal.dataset.unitId),
            p_status: document.getElementById('inventoryNewStatus').value,
            p_condition: document.getElementById('inventoryNewCondition').value,
            p_notes: document.getElementById('inventoryStatusNotes').value.trim()
          });

          if (error) {
            window.lave.toast(error.message, 'error');
            return;
          }

          modal.classList.remove('show');
          window.lave.toast('Status unit dan movement berhasil diperbarui.');
          await load();

          const variantId = Number(
            document.getElementById('inventoryDetailModal')?.dataset.variantId
          );

          if (variantId) await openDetail(variantId);
        });
    }

    modal.dataset.unitId = String(unitId);

    document.getElementById('inventoryStatusVariant').textContent =
      `${parentVariant?.dress_code || ''} - ${parentVariant?.name || ''} / ${parentVariant?.size || ''} / ${parentVariant?.color || ''} / ${unit.unit_code}`;

    document.getElementById('inventoryNewStatus').value =
      ['Available', 'Laundry', 'Repair', 'Not Available'].includes(unit.status)
        ? unit.status
        : '';

    document.getElementById('inventoryNewCondition').value =
      ['Good', 'Fair', 'Damaged', 'Unusable'].includes(unit.condition)
        ? unit.condition
        : 'Fair';

    document.getElementById('inventoryStatusNotes').value = '';
    modal.classList.add('show');
  }

  function openColorReconciliation(variantId) {
    const source = dresses.find(
      item => Number(item.dress_variant_id) === variantId
    );

    if (!source) return;

    const targets = dresses.filter(
      item =>
        Number(item.dress_id) === Number(source.dress_id) &&
        item.size.toUpperCase() === source.size.toUpperCase() &&
        item.color !== 'UNVERIFIED'
    );

    if (!targets.length) {
      window.lave.toast(
        'Tambahkan varian warna terverifikasi sebelum stocktake.',
        'error'
      );
      return;
    }

    let modal = document.getElementById('inventoryColorModal');

    if (!modal) {
      document.body.insertAdjacentHTML(
        'beforeend',
        '<div class="modal" id="inventoryColorModal"><div class="modal-box"><div class="modal-head"><h3>Rekonsiliasi Warna</h3><button type="button" class="close" id="closeInventoryColor">×</button></div><form id="inventoryColorForm"><p id="inventoryColorSource"></p><div class="form-grid"><div class="field"><label>Warna hasil stocktake</label><select id="inventoryTargetVariant" required></select></div><div class="field"><label>Jumlah unit hasil stocktake</label><input id="inventoryColorQuantity" type="number" min="1" required></div><div class="field"><label>Catatan stocktake</label><input id="inventoryColorNotes" required maxlength="500"></div></div><div class="form-actions"><button type="submit" class="btn btn-primary">Rekonsiliasi</button></div></form></div></div>'
      );

      modal = document.getElementById('inventoryColorModal');

      document
        .getElementById('closeInventoryColor')
        .addEventListener('click', () => modal.classList.remove('show'));

      document
        .getElementById('inventoryColorForm')
        .addEventListener('submit', async event => {
          event.preventDefault();

          const { error } = await supabase.rpc('reconcile_legacy_variant_color', {
            p_unverified_variant_id: Number(modal.dataset.sourceId),
            p_target_variant_id: Number(
              document.getElementById('inventoryTargetVariant').value
            ),
            p_quantity: Number(
              document.getElementById('inventoryColorQuantity').value
            ),
            p_notes: document
              .getElementById('inventoryColorNotes')
              .value
              .trim()
          });

          if (error) {
            window.lave.toast(error.message, 'error');
            return;
          }

          modal.classList.remove('show');
          window.lave.toast(
            'Jumlah stok dipindahkan dan movement stocktake dicatat.'
          );
          await load();
        });
    }

    modal.dataset.sourceId = String(variantId);

    document.getElementById('inventoryColorSource').textContent =
      `${source.dress_code} - ${source.name} / ${source.size} / belum terpetakan (${source.quantity - source.rented_quantity} unit tidak disewa)`;

    const targetSelect = document.getElementById('inventoryTargetVariant');

    targetSelect.innerHTML = targets
      .map(
        target =>
          `<option value="${target.dress_variant_id}">${esc(target.color)}</option>`
      )
      .join('');

    const quantityInput = document.getElementById('inventoryColorQuantity');
    const movableUnits =
      Number(source.quantity || 0) - Number(source.rented_quantity || 0);

    quantityInput.max = String(movableUnits);
    quantityInput.value = movableUnits > 0 ? String(movableUnits) : '';
    quantityInput.disabled = movableUnits <= 0;

    modal.classList.add('show');
  }

  async function load() {
    const pageSubtitle = document.querySelector('.topbar .muted');

    if (pageSubtitle) {
      pageSubtitle.textContent =
        'Stok, status, warna, dan riwayat movement per varian';
    }

    document.getElementById('inventoryStatus').innerHTML =
      '<option value="">Semua status</option><option>Available</option><option>Rented</option><option>Laundry</option><option>Repair</option><option>Not Available</option><option>Mixed</option><option>Unclassified</option>';

    const [dressResult, movementResult] = await Promise.all([
      supabase
        .from('v_dress_inventory')
        .select('*')
        .order('dress_code')
        .order('size')
        .order('color'),
      supabase
        .from('dress_movements')
        .select(
          '*,dresses(dress_code,name),dress_variants(size,color),dress_units(unit_code)'
        )
        .order('movement_date', { ascending: false })
        .limit(200)
    ]);

    if (dressResult.error) {
      document.getElementById('inventoryRows').innerHTML =
        `<tr><td colspan="13" class="empty">Persediaan gagal dimuat dari database: ${esc(dressResult.error.message)}</td></tr>`;

      document.getElementById('movementRows').innerHTML =
        '<tr><td colspan="14" class="empty">Riwayat movement tidak dapat ditampilkan sebelum persediaan berhasil dimuat.</td></tr>';

      throw dressResult.error;
    }

    dresses = dressResult.data || [];
    render();

    if (movementResult.error) {
      document.getElementById('movementRows').innerHTML =
        `<tr><td colspan="14" class="empty">Riwayat movement belum tersedia: ${esc(movementResult.error.message)}</td></tr>`;
      return;
    }

    const movements = movementResult.data || [];
    const movementBody = document.getElementById('movementRows');

    movementBody.closest('table').querySelector('thead').innerHTML =
      '<tr><th>Tanggal</th><th>Kode Model</th><th>Nama Model</th><th>Ukuran</th><th>Warna</th><th>Unit</th><th>Jenis</th><th>Status</th><th>Δ Total</th><th>Δ Tersedia</th><th>Δ Disewa</th><th>Δ Tidak Tersedia</th><th>Referensi</th><th>Catatan</th></tr>';

    movementBody.innerHTML = movements.length
      ? movements
          .map(
            m =>
              `<tr><td>${window.lave.formatDate(m.movement_date)}</td><td>${esc(m.dresses?.dress_code || '-')}</td><td>${esc(m.dresses?.name || '-')}</td><td>${esc(m.dress_variants?.size || '-')}</td><td>${esc(m.dress_variants?.color || '-')}</td><td>${esc(m.dress_units?.unit_code || '-')}</td><td>${esc(m.movement_type)}</td><td>${esc(m.status_before || '-')} → ${esc(m.status_after || '-')}</td><td>${m.quantity_delta > 0 ? '+' : ''}${m.quantity_delta}</td><td>${m.available_delta > 0 ? '+' : ''}${m.available_delta}</td><td>${m.rented_delta > 0 ? '+' : ''}${m.rented_delta}</td><td>${m.unavailable_delta > 0 ? '+' : ''}${m.unavailable_delta}</td><td>${esc(`${m.reference_type || ''} ${m.reference_code || m.reference_id || '-'}`)}</td><td>${esc(m.notes || m.description || '-')}</td></tr>`
          )
          .join('')
      : '<tr><td colspan="14" class="empty">Belum ada movement dress.</td></tr>';
  }

  document
    .getElementById('inventorySearch')
    .addEventListener('input', render);

  document
    .getElementById('inventoryStatus')
    .addEventListener('change', render);

  document
    .getElementById('printInventory')
    .addEventListener('click', () => window.print());

  load().catch(error => window.lave.toast(error.message, 'error'));
}());