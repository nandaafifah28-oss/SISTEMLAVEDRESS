(function () {
  const supabase = window.lave.supabase;
  const state = { dresses: [], variants: [], categories: [], suppliers: [] };
  const $ = id => document.getElementById(id);
  const value = id => $(id).value;
  const setValue = (id, val) => {
    $(id).value = val ?? '';
  };
  const money = val => window.lave.currency(val);

  function open() {
    $('dressModal').classList.add('show');
  }

  function close() {
    $('dressModal').classList.remove('show');
  }

  function resetForm() {
    $('dressForm').reset();
    setValue('dressId', '');
    setValue('dressCode', '');
    setValue('dressStatus', 'Active');
    setValue('dressCondition', 'Good');
    photoPreview.hidden = true;
    photoPreview.src = '';
    $('dressModalTitle').textContent = 'Tambah Dress';
  }

  function render() {
    const query = value('dressSearch').trim().toLowerCase();
    const rows = state.dresses.filter(d =>
      `${d.dress_code} ${d.name}`.toLowerCase().includes(query)
    );

    $('dressRows').closest('table').querySelector('thead').innerHTML =
      '<tr><th>Kode Model</th><th>Nama Model</th><th>Kategori</th><th>Jumlah Varian</th><th>Warna Varian</th><th>Harga Beli Dasar</th><th>Harga Sewa</th><th>Supplier</th><th>Status</th><th>Kondisi</th><th>Aksi</th></tr>';

    $('dressRows').innerHTML = rows.length
      ? rows.map(d => {
          const variants = state.variants.filter(
            variant => Number(variant.dress_id) === Number(d.id)
          );

          const colors = [
            ...new Set(variants.map(variant => variant.color).filter(Boolean))
          ].join(', ') || '-';

          return `<tr><td>${window.lave.escape(d.dress_code)}</td><td><strong>${window.lave.escape(d.name)}</strong></td><td>${window.lave.escape(d.dress_categories?.category_name || '-')}</td><td>${variants.length}</td><td>${window.lave.escape(colors)}</td><td>${money(d.purchase_price)}</td><td>${money(d.rental_price)}</td><td>${window.lave.escape(d.suppliers?.name || '-')}</td><td>${d.is_active === false ? 'Inactive' : 'Active'}</td><td>${window.lave.escape(d.condition || '-')}</td><td><button class="btn btn-light" data-variants="${d.id}">Varian</button> <button class="btn btn-light" data-edit="${d.id}">Edit</button> <button class="btn btn-danger" data-disable="${d.id}" ${d.is_active === false ? 'disabled' : ''}>Nonaktifkan</button></td></tr>`;
        }).join('')
      : '<tr><td colspan="11" class="empty">Belum ada data dress.</td></tr>';

    document.querySelectorAll('[data-edit]').forEach(btn =>
      btn.addEventListener('click', () => edit(Number(btn.dataset.edit)))
    );

    document.querySelectorAll('[data-disable]').forEach(btn =>
      btn.addEventListener('click', () => disable(Number(btn.dataset.disable)))
    );

    document.querySelectorAll('[data-variants]').forEach(btn =>
      btn.addEventListener('click', () =>
        manageVariants(Number(btn.dataset.variants))
      )
    );
  }

  async function load() {
    const [dressResult, variantResult] = await Promise.all([
      supabase
        .from('dresses')
        .select('*,dress_categories(category_name),suppliers(name)')
        .order('dress_code'),
      supabase
        .from('dress_variants')
        .select('*')
        .order('normalized_size')
    ]);

    if (dressResult.error) throw dressResult.error;
    if (variantResult.error) throw variantResult.error;

    state.dresses = dressResult.data || [];
    state.variants = variantResult.data || [];
    render();
  }

  async function loadOptions() {
    const [categories, suppliers] = await Promise.all([
      supabase
        .from('dress_categories')
        .select('*')
        .order('category_name'),
      supabase
        .from('suppliers')
        .select('*')
        .order('name')
    ]);

    if (categories.error) throw categories.error;
    if (suppliers.error) throw suppliers.error;

    state.categories = categories.data || [];
    state.suppliers = suppliers.data || [];

    $('dressCategory').innerHTML =
      '<option value="">Pilih kategori</option>' +
      state.categories
        .map(c =>
          `<option value="${c.id}">${window.lave.escape(c.category_name)}</option>`
        )
        .join('');

    $('dressSupplier').innerHTML =
      '<option value="">Tanpa supplier</option>' +
      state.suppliers
        .map(s =>
          `<option value="${s.id}">${window.lave.escape(s.supplier_code)} - ${window.lave.escape(s.name)}</option>`
        )
        .join('');
  }

  async function edit(id) {
    const d = state.dresses.find(item => item.id === id);
    if (!d) return;

    setValue('dressId', d.id);
    setValue('dressCode', d.dress_code);
    setValue('dressName', d.name);
    setValue('dressCategory', d.category_id);
    setValue('dressSize', '');
    setValue('dressPurchasePrice', d.purchase_price);
    setValue('dressRentalPrice', d.rental_price);
    setValue('dressSupplier', d.supplier_id);
    setValue('dressCondition', d.condition || 'Good');
    setValue('dressStatus', d.is_active === false ? 'Inactive' : 'Active');
    setValue('dressDescription', d.description);
    photoPreview.src = d.photo_url || '';
    photoPreview.hidden = !d.photo_url;
    $('dressModalTitle').textContent = 'Edit Model Dress';
    open();
  }

  async function manageVariants(dressId) {
    const dress = state.dresses.find(item => Number(item.id) === dressId);
    if (!dress) return;

    let modal = $('variantManagerModal');

    if (!modal) {
      document.body.insertAdjacentHTML(
        'beforeend',
        '<div class="modal" id="variantManagerModal"><div class="modal-box"><div class="modal-head"><h3>Varian Dress</h3><button class="close" type="button" id="closeVariantManager">×</button></div><p id="variantManagerModel"></p><form id="variantForm"><div class="form-grid"><div class="field"><label>Ukuran</label><input id="variantSize" list="variantSizeOptions" required maxlength="20"><datalist id="variantSizeOptions"><option value="XS"><option value="S"><option value="M"><option value="L"><option value="XL"><option value="XXL"></datalist></div><div class="field"><label>Warna</label><input id="variantColor" required maxlength="50"></div></div><p class="muted">Stok masuk dicatat melalui Pembelian agar jurnal dan persediaan tetap seimbang.</p><div class="form-actions"><button type="submit" class="btn btn-primary">Tambah Varian</button></div></form><div class="table-wrap"><table><thead><tr><th>Ukuran</th><th>Warna</th><th>Stok</th><th>Tersedia</th><th>Disewa</th><th>Laundry</th><th>Repair</th><th>Status</th><th>Kondisi</th></tr></thead><tbody id="variantRows"></tbody></table></div></div></div>'
      );

      modal = $('variantManagerModal');

      $('closeVariantManager').addEventListener(
        'click',
        () => modal.classList.remove('show')
      );

      $('variantForm').addEventListener('submit', async event => {
        event.preventDefault();

        const size = $('variantSize').value.trim().toUpperCase();
        const color = $('variantColor').value.trim();

        if (!size || !color) {
          window.lave.toast('Ukuran dan warna wajib diisi.', 'error');
          return;
        }

        const { error } = await supabase.rpc('ensure_dress_variant', {
          p_dress_id: Number(modal.dataset.dressId),
          p_size: size,
          p_color: color
        });

        if (error) {
          window.lave.toast(error.message, 'error');
          return;
        }

        $('variantSize').value = '';
        $('variantColor').value = '';
        await load();
        renderVariantRows(Number(modal.dataset.dressId));
        window.lave.toast(
          'Varian ukuran dan warna tersimpan. Stok dapat ditambahkan melalui Pembelian.'
        );
      });
    }

    modal.dataset.dressId = String(dressId);
    $('variantManagerModel').textContent =
      `${dress.dress_code} - ${dress.name}`;
    renderVariantRows(dressId);
    modal.classList.add('show');
  }

  function renderVariantRows(dressId) {
    const variants = state.variants.filter(
      variant => Number(variant.dress_id) === dressId
    );

    $('variantRows').innerHTML = variants.length
      ? variants
          .map(
            variant =>
              `<tr><td>${window.lave.escape(variant.size)}</td><td>${window.lave.escape(variant.color)}</td><td>${variant.quantity}</td><td>${variant.available_quantity}</td><td>${variant.rented_quantity}</td><td>${variant.laundry_quantity || 0}</td><td>${variant.repair_quantity || 0}</td><td>${window.lave.escape(variant.status)}</td><td>${window.lave.escape(variant.condition)}</td></tr>`
          )
          .join('')
      : '<tr><td colspan="9" class="empty">Belum ada varian.</td></tr>';
  }

  async function disable(id) {
    if (!confirm('Nonaktifkan dress ini? Data transaksi tetap dipertahankan.')) {
      return;
    }

    const { error } = await supabase
      .from('dresses')
      .update({ is_active: false, status: 'Not Available' })
      .eq('id', id);

    if (error) {
      window.lave.toast(error.message, 'error');
      return;
    }

    window.lave.toast('Dress dinonaktifkan.');
    await load();
  }

  $('addDressButton').addEventListener('click', () => {
    resetForm();
    open();
  });

  $('dressSize').required = false;
  $('dressSize').disabled = true;
  $('dressSize').closest('.field').hidden = true;

  $('dressStatus')
    .closest('.field')
    .querySelector('label').textContent = 'Status Aktif';

  $('dressStatus').innerHTML =
    '<option value="Active">Active</option><option value="Inactive">Inactive</option>';

  $('dressStatus').value = 'Active';

  $('dressColor').closest('.field').hidden = true;
  $('dressColor').required = false;

  $('dressPhoto').type = 'file';
  $('dressPhoto').accept = 'image/*';

  $('dressPhoto')
    .closest('.field')
    .querySelector('label').textContent = 'Foto Dress (maks. 5 MB)';

  const photoPreview = document.createElement('img');
  photoPreview.alt = 'Pratinjau foto dress';
  photoPreview.hidden = true;
  photoPreview.style.maxWidth = '160px';
  photoPreview.style.maxHeight = '180px';
  photoPreview.style.objectFit = 'cover';

  $('dressPhoto').after(photoPreview);

  $('dressPhoto').addEventListener('change', () => {
    const file = $('dressPhoto').files?.[0];
    photoPreview.hidden = !file;
    if (file) photoPreview.src = URL.createObjectURL(file);
  });

  document
    .querySelectorAll('[data-close="dressModal"]')
    .forEach(btn => btn.addEventListener('click', close));

  $('dressSearch').addEventListener('input', render);

  $('dressForm').addEventListener('submit', async event => {
    event.preventDefault();

    const id = value('dressId');
    const isActive = value('dressStatus') === 'Active';

    const fields = {
      name: value('dressName'),
      category_id: value('dressCategory'),
      purchase_price: value('dressPurchasePrice'),
      rental_price: value('dressRentalPrice'),
      supplier_id: value('dressSupplier'),
      condition: value('dressCondition'),
      description: value('dressDescription')
    };

    const built = window.lave.buildDressMasterPayload(fields);

    if (built.error) {
      window.lave.toast(built.error, 'error');
      return;
    }

    if (isActive) {
      const duplicate = state.dresses.find(
        dress =>
          Number(dress.id) !== Number(id) &&
          dress.is_active !== false &&
          dress.name.trim().toLowerCase() ===
            built.payload.name.toLowerCase() &&
          Number(dress.category_id) === built.payload.category_id
      );

      if (duplicate) {
        window.lave.toast(
          `Model serupa sudah terdaftar dengan kode ${duplicate.dress_code}. Tambahkan varian pada model tersebut.`,
          'error'
        );
        return;
      }
    }

    const photoFile = $('dressPhoto').files?.[0];

    if (id) {
      const result = await window.lave.updateDress(
        id,
        fields,
        photoFile,
        { is_active: isActive }
      );

      if (result.error) {
        window.lave.toast(result.error.message, 'error');
        return;
      }

      window.lave.toast('Data dress berhasil diperbarui.');
    } else {
      const photo = await window.lave.uploadDressPhoto(photoFile, null);

      if (photo.error) {
        window.lave.toast(photo.error, 'error');
        return;
      }

      const payload = {
        ...built.payload,
        photo_url: photo.photo_url,
        is_active: isActive,
        status: isActive ? 'Available' : 'Not Available'
      };

      const result = await supabase.from('dresses').insert(payload);

      if (result.error) {
        if (photo.uploadedPath) {
          await supabase.storage
            .from('dress-photos')
            .remove([photo.uploadedPath]);
        }

        window.lave.toast(result.error.message, 'error');
        return;
      }

      window.lave.toast(
        'Model dress dibuat dengan kode sequence database.'
      );
    }

    $('dressForm').reset();
    photoPreview.hidden = true;
    close();
    await load();
  });

  Promise.all([loadOptions(), load()]).catch(error =>
    window.lave.toast(error.message, 'error')
  );
}());