(function () {
  const page = document.body && document.body.dataset ? document.body.dataset.page : '';
  const la = window.lave || {};
  const supabase = la.supabase;
  if (!supabase) return;

  function money(v) {
    return la.currency ? la.currency(v) : 'Rp' + Number(v || 0).toLocaleString('id-ID');
  }

  function statusBadge(v) {
    const label = String(v || '-');
    const key = label.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
    return '<span class="badge status-' + key + '">' + la.escape(label) + '</span>';
  }

  function getValue(id) {
    const el = document.getElementById(id);
    return el ? el.value : '';
  }

  function setValue(id, value) {
    const el = document.getElementById(id);
    if (el) el.value = value ?? '';
  }

  async function loadCustomers() {
    const { data, error } = await supabase
      .from('customers')
      .select('*')
      .order('id', { ascending: false });

    if (error) throw error;
    return data || [];
  }

  async function loadDresses() {
    const { data, error } = await supabase
      .from('dresses')
      .select('*, dress_categories(category_name)')
      .order('dress_code');

    if (error) throw error;
    return data || [];
  }

  async function loadRentalOptions() {
    const { data, error } = await supabase
      .from('rentals')
      .select('*, customers(name)')
      .order('id', { ascending: false });

    if (error) throw error;
    return data || [];
  }

  async function loadSuppliers() {
    const { data, error } = await supabase
      .from('suppliers')
      .select('*')
      .order('id', { ascending: false });

    if (error) throw error;
    return data || [];
  }

  async function loadCategories() {
    const { data, error } = await supabase
      .from('dress_categories')
      .select('*')
      .order('category_name');

    if (error) throw error;
    return data || [];
  }

  async function nextCode(type) {
    return la.nextCode(type);
  }

  async function ensureCustomerFromForm(customerName, phone = '', email = '', address = '') {
    const name = String(customerName || '').trim();
    if (!name) return null;

    const { data: existing } = await supabase
      .from('customers')
      .select('*')
      .ilike('name', name)
      .limit(1);

    if (existing && existing.length) return existing[0];

    const payload = {
      customer_code: await nextCode('customer'),
      name,
      phone: phone || null,
      email: email || null,
      address: address || null
    };

    const { data, error } = await supabase
      .from('customers')
      .insert(payload)
      .select()
      .single();

    if (error) throw error;
    return data;
  }

  async function ensureSupplierFromForm(supplierName, phone = '', email = '', address = '', notes = '') {
    const name = String(supplierName || '').trim();
    if (!name) return null;

    const { data: existing } = await supabase
      .from('suppliers')
      .select('*')
      .ilike('name', name)
      .limit(1);

    if (existing && existing.length) return existing[0];

    const payload = {
      supplier_code: await nextCode('supplier'),
      name,
      phone: phone || null,
      email: email || null,
      address: address || null,
      notes: notes || null
    };

    const { data, error } = await supabase
      .from('suppliers')
      .insert(payload)
      .select()
      .single();

    if (error) throw error;
    return data;
  }

  function computeStatus(total, paid) {
    const remaining = Number(total || 0) - Number(paid || 0);
    if (remaining <= 0) return 'Lunas';
    if (paid > 0) return 'Sebagian Dibayar';
    return 'Belum Dibayar';
  }

  async function initRentalPage() {
    const form = document.getElementById('form');
    if (!form) return;

    form.innerHTML = `
      <div class="form-grid">
        <div class="field">
          <label>Nomor Penyewaan</label>
          <input id="rental_code" required>
        </div>
        <div class="field">
          <label>Customer</label>
          <select id="customer_id"></select>
        </div>
        <div class="field">
          <label>Nama Customer Baru</label>
          <input id="customer_name" placeholder="Isi jika customer belum ada">
        </div>
        <div class="field">
          <label>No. HP</label>
          <input id="customer_phone">
        </div>
        <div class="field">
          <label>Email</label>
          <input id="customer_email" type="email">
        </div>
        <div class="field">
          <label>Alamat</label>
          <input id="customer_address">
        </div>
        <div class="field">
          <label>Model Dress</label>
          <select id="dress_code" required>
            <option value="">Pilih model dress</option>
          </select>
        </div>
        <div class="field">
          <label>Ukuran Tersedia</label>
          <select id="dress_variant_id" required>
            <option value="">Pilih model terlebih dahulu</option>
          </select>
        </div>
        <div class="field">
          <label>Unit Fisik Tersedia</label>
          <select id="dress_unit_id" required disabled>
            <option value="">Pilih ukuran dan warna terlebih dahulu</option>
          </select>
        </div>
        <div class="field">
          <label>Nama Dress</label>
          <input id="dress_name" readonly>
        </div>
        <div class="field">
          <label>Kategori</label>
          <input id="dress_category" readonly>
        </div>
        <div class="field">
          <label>Ukuran</label>
          <input id="dress_size" readonly>
        </div>
        <div class="field">
          <label>Warna</label>
          <input id="dress_color" readonly>
        </div>
        <div class="field">
          <label>Harga Sewa</label>
          <input id="rental_price" type="number" readonly>
        </div>
        <div class="field">
          <label>Tanggal Mulai Sewa</label>
          <input id="rental_date" type="date" required>
        </div>
        <div class="field">
          <label>Tanggal Kembali</label>
          <input id="return_due_date" type="date" required>
        </div>
        <div class="field">
          <label>Deposit/Jaminan Diterima</label>
          <input id="deposit_amount" type="number" value="0" min="0">
        </div>
        <div class="field">
          <label>Total Sewa</label>
          <input id="total_amount" type="number" readonly>
        </div>
        <div class="field">
          <label>Sisa Sewa</label>
          <input id="remaining_rent" type="number" readonly>
        </div>
        <div class="field">
          <label>Total Dibayar (DP + Deposit)</label>
          <input id="total_received_amount" type="number" readonly>
        </div>
        <div class="field">
          <label>Status Pembayaran Sewa</label>
          <input id="initial_payment_status" readonly>
        </div>
        <div class="field">
          <label>Status Penyewaan</label>
          <select id="rental_status">
            <option value="Booked">Booked</option>
            <option value="Ongoing">Ongoing</option>
            <option value="Cancelled">Cancelled</option>
          </select>
        </div>
        <div class="field">
          <label>DP / Pembayaran Awal Sewa</label>
          <input id="initial_payment" type="number" min="0" value="0">
        </div>
        <div class="field">
          <label>Metode Pembayaran</label>
          <select id="initial_payment_method">
            <option value="Cash">Cash</option>
            <option value="Transfer">Transfer</option>
            <option value="E-Wallet">E-Wallet</option>
          </select>
        </div>
        <div class="field">
          <label>Tipe Pembayaran</label>
          <select id="initial_payment_type">
            <option value="DP">DP</option>
            <option value="PELUNASAN">Pelunasan</option>
          </select>
        </div>
        <div class="field">
          <label>Tanggal Pembayaran</label>
          <input id="initial_payment_date" type="date">
        </div>
      </div>
      <div class="form-actions">
        <button type="button" class="btn btn-light" id="createCustomerBtn">+ Customer Baru</button>
        <button type="button" class="btn btn-light" onclick="closeModal('modal')">Batal</button>
        <button type="submit" class="btn btn-primary">Simpan</button>
      </div>
    `;

    const tableBody = document.getElementById('tbody');
    const search = document.getElementById('search');
    const modalTitle = document.querySelector('.modal-head h3');
    if (modalTitle) modalTitle.textContent = 'Rental Baru';

    const tableHeader = tableBody.closest('table')?.querySelector('thead tr');
    if (tableHeader) {
      tableHeader.innerHTML = '<th>Kode</th><th>Customer</th><th>Tanggal</th><th>Jatuh Tempo</th><th>Total</th><th>Terbayar</th><th>Sisa</th><th>Status Rental</th><th>Status Pembayaran</th><th>Aksi</th>';
    }

    const customersSelect = document.getElementById('customer_id');
    const rentalCodeInput = document.getElementById('rental_code');
    const dressCodeInput = document.getElementById('dress_code');
    const variantSelect = document.getElementById('dress_variant_id');
    const unitSelect = document.getElementById('dress_unit_id');
    let unitLoadRequest = 0;
    const rentalPriceInput = document.getElementById('rental_price');
    const totalAmountInput = document.getElementById('total_amount');
    const rentalDateInput = document.getElementById('rental_date');
    const returnDueInput = document.getElementById('return_due_date');
    const createCustomerBtn = document.getElementById('createCustomerBtn');

    const dressMap = new Map();
    const customers = await loadCustomers();

    customersSelect.innerHTML =
      '<option value="">Pilih Customer</option>' +
      customers
        .map(c => `<option value="${c.id}">${c.customer_code} - ${c.name}</option>`)
        .join('');

    customersSelect.addEventListener('change', () => {
      const customer = customers.find(
        item => Number(item.id) === Number(customersSelect.value)
      );

      setValue('customer_name', customer ? customer.name : '');
      setValue('customer_phone', customer ? customer.phone : '');
      setValue('customer_email', customer ? customer.email : '');
      setValue('customer_address', customer ? customer.address : '');
    });

    const [dressRows, variantResult] = await Promise.all([
      loadDresses(),
      supabase
        .from('dress_variants')
        .select('*')
        .order('normalized_size')
    ]);

    if (variantResult.error) throw variantResult.error;

    const dresses = dressRows.filter(dress => dress.is_active !== false);
    let variants = variantResult.data || [];

    dresses.forEach(dress => {
      dressMap.set(String(dress.id), dress);

      const option = document.createElement('option');
      option.value = String(dress.id);
      option.textContent = `${dress.dress_code} - ${dress.name}`;
      dressCodeInput.appendChild(option);
    });

    const now = new Date();
    const defaultDate = new Date(now.getTime() + 86400000)
      .toISOString()
      .slice(0, 10);

    setValue('rental_code', await nextCode('rental'));
    setValue('rental_date', new Date().toISOString().slice(0, 10));
    setValue('return_due_date', defaultDate);
    setValue('initial_payment_date', new Date().toISOString().slice(0, 10));
    updateRentalSummary();

    if (createCustomerBtn) {
      createCustomerBtn.addEventListener('click', async () => {
        const name = window.prompt('Nama customer baru:', '');
        if (!name) return;

        const phone = window.prompt('Nomor telepon customer:', '') || '';
        const email = window.prompt('Email customer:', '') || '';

        try {
          const customer = await ensureCustomerFromForm(name, phone, email);
          if (!customer) return;

          const options = customersSelect.querySelectorAll('option');
          const exists = Array.from(options).some(
            option => Number(option.value) === Number(customer.id)
          );

          if (!exists) {
            const option = document.createElement('option');
            option.value = customer.id;
            option.textContent = `${customer.customer_code} - ${customer.name}`;
            customersSelect.appendChild(option);
          }

          customersSelect.value = String(customer.id);
          la.toast('Customer baru berhasil dibuat dan siap digunakan.');
        } catch (error) {
          la.toast(error.message || 'Customer gagal dibuat.', 'error');
        }
      });
    }

    dressCodeInput.addEventListener('change', () => {
      unitLoadRequest += 1;
      const dress = dressMap.get(dressCodeInput.value);

      if (!dress) {
        variantSelect.innerHTML =
          '<option value="">Pilih model terlebih dahulu</option>';
        unitSelect.innerHTML =
          '<option value="">Pilih ukuran dan warna terlebih dahulu</option>';
        unitSelect.disabled = true;

        setValue('dress_name', '');
        setValue('dress_category', '');
        setValue('dress_size', '');
        setValue('dress_color', '');
        setValue('rental_price', '');
        setValue('total_amount', '');
        return;
      }

      const dressVariants = variants.filter(
        variant => Number(variant.dress_id) === Number(dress.id)
      );

      variantSelect.innerHTML =
        '<option value="">Pilih ukuran dan warna</option>' +
        dressVariants
          .map(variant => {
            const unverified =
              String(variant.color || '').toUpperCase() === 'UNVERIFIED';

            const available =
              Number(variant.available_quantity || 0) > 0 && !unverified;

            return `<option value="${variant.id}" ${available ? '' : 'disabled'}>${la.escape(variant.size)} / ${la.escape(variant.color)} — ${available ? `Tersedia ${variant.available_quantity}` : unverified ? 'Perlu stocktake' : 'Tidak tersedia'}</option>`;
          })
          .join('');

      setValue('dress_name', dress.name);
      setValue(
        'dress_category',
        dress.dress_categories ? dress.dress_categories.category_name : ''
      );
      setValue('dress_color', dress.color || '');

      unitSelect.innerHTML =
        '<option value="">Pilih ukuran dan warna terlebih dahulu</option>';
      unitSelect.disabled = true;

      setValue('dress_size', '');
      setValue('rental_price', '');
      setValue('total_amount', '');
      updateRentalSummary();
    });

        variantSelect.addEventListener('change', async () => {
      const requestId = ++unitLoadRequest;
      const variant = variants.find(
        item => Number(item.id) === Number(variantSelect.value)
      );
      const dress = dressMap.get(dressCodeInput.value);

      if (!variant || !dress) {
        unitSelect.innerHTML =
          '<option value="">Pilih ukuran dan warna terlebih dahulu</option>';
        unitSelect.disabled = true;
        setValue('dress_size', '');
        setValue('rental_price', '');
        setValue('total_amount', '');
        return;
      }

      setValue('dress_size', variant.size);
      setValue('dress_color', variant.color || '');
      setValue('rental_price', dress.rental_price || 0);
      setValue('total_amount', Number(dress.rental_price || 0));
      updateRentalSummary();

      unitSelect.disabled = true;
      unitSelect.innerHTML =
        '<option value="">Memuat unit tersedia...</option>';

      const unitResult = await supabase
        .from('dress_units')
        .select('id,unit_code,status')
        .eq('variant_id', variant.id)
        .eq('status', 'Available')
        .order('unit_code');

      if (requestId !== unitLoadRequest) return;

      if (unitResult.error) {
        unitSelect.innerHTML =
          '<option value="">Unit tidak dapat dimuat</option>';
        la.toast(unitResult.error.message, 'error');
        return;
      }

      unitSelect.innerHTML =
        '<option value="">Pilih unit fisik</option>' +
        (unitResult.data || [])
          .map(
            unit =>
              `<option value="${unit.id}">${la.escape(unit.unit_code)}</option>`
          )
          .join('');

      unitSelect.disabled = !(unitResult.data || []).length;

      if (!(unitResult.data || []).length) {
        unitSelect.innerHTML =
          '<option value="">Tidak ada unit Available</option>';
      }
    });

    function updateRentalSummary() {
      const total = Number(getValue('rental_price') || 0);
      const downPayment = Number(getValue('initial_payment') || 0);
      const deposit = Number(getValue('deposit_amount') || 0);
      setValue('remaining_rent', Math.max(total - downPayment, 0));
      setValue('total_received_amount', downPayment + deposit);
      setValue('initial_payment_status', computeStatus(total, downPayment));
    }

    ['initial_payment', 'deposit_amount'].forEach(id =>
      document
        .getElementById(id)
        .addEventListener('input', updateRentalSummary)
    );

    async function renderList() {
      const { data, error } = await supabase
        .from('rentals')
        .select('*, customers(name), payments(amount,payment_type)')
        .order('id', { ascending: false });

      if (error) {
        la.toast(error.message, 'error');
        return;
      }

      const q = (search ? search.value : '').toLowerCase();

      const items = (data || []).filter(
        r =>
          (r.rental_code || '').toLowerCase().includes(q) ||
          (r.customers && r.customers.name || '').toLowerCase().includes(q)
      );

      tableBody.innerHTML = items.length
        ? items
            .map(r => {
              const paid = (r.payments || []).reduce(
                (sum, payment) =>
                  sum +
                  (payment.payment_type === 'REFUND'
                    ? -Number(payment.amount || 0)
                    : ['DP', 'PELUNASAN'].includes(payment.payment_type)
                      ? Number(payment.amount || 0)
                      : 0),
                0
              );

              const total = Number(r.total_rental ?? r.total_amount ?? 0);
              const remaining = Math.max(total - paid, 0);
              const rentalStatus =
                r.rental_status ||
                (r.status === 'Cancelled' ? 'Cancelled' : 'Booked');
              const paymentStatus =
                r.payment_status || computeStatus(total, paid);

              return `<tr>
          <td>${la.escape(r.rental_code)}</td>
          <td>${la.escape(r.customers ? r.customers.name : '-')}</td>
          <td>${la.formatDate(r.rental_date)}</td>
          <td>${la.formatDate(r.return_due_date)}</td>
          <td>${money(total)}</td>
          <td>${money(paid)}</td>
          <td>${money(remaining)}</td>
          <td>${statusBadge(rentalStatus)}</td>
          <td>${statusBadge(paymentStatus)}</td>
          <td><button type="button" class="btn btn-light rental-detail" data-id="${r.id}">Detail</button>${remaining > 0 && rentalStatus !== 'Cancelled' ? ` <button type="button" class="btn btn-light rental-pay" data-id="${r.id}" data-balance="${remaining}">Bayar Sisa</button>` : ''}${!['Cancelled', 'Completed'].includes(rentalStatus) ? ` <button type="button" class="btn btn-light rental-cancel" data-id="${r.id}">Batalkan</button>` : ''} <button type="button" class="btn btn-light rental-print" data-id="${r.id}">Cetak</button></td>
        </tr>`;
            })
            .join('')
        : '<tr><td colspan="10" class="empty">Belum ada data rental.</td></tr>';

      tableBody
        .querySelectorAll('.rental-detail')
        .forEach(button =>
          button.addEventListener('click', () =>
            showRentalDetail(Number(button.dataset.id))
          )
        );

      tableBody
        .querySelectorAll('.rental-pay')
        .forEach(button =>
          button.addEventListener('click', () =>
            payRentalBalance(
              Number(button.dataset.id),
              Number(button.dataset.balance)
            )
          )
        );

      tableBody
        .querySelectorAll('.rental-cancel')
        .forEach(button =>
          button.addEventListener('click', () =>
            cancelRental(Number(button.dataset.id))
          )
        );

      tableBody
        .querySelectorAll('.rental-print')
        .forEach(button =>
          button.addEventListener('click', () =>
            printRentalInvoice(Number(button.dataset.id))
          )
        );
    }

    async function getRentalRecord(rentalId) {
      const result = await supabase
        .from('rentals')
        .select(
          '*, customers(*), payments(*), rental_details(*, dresses(*, dress_categories(category_name)), dress_variants(size,color), dress_units(unit_code,status,condition))'
        )
        .eq('id', rentalId)
        .single();

      if (result.error) throw result.error;
      return result.data;
    }

    function paymentTotals(rental) {
      const paid = (rental.payments || []).reduce(
        (sum, payment) =>
          sum +
          (payment.payment_type === 'REFUND'
            ? -Number(payment.amount || 0)
            : ['DP', 'PELUNASAN'].includes(payment.payment_type)
              ? Number(payment.amount || 0)
              : 0),
        0
      );

      const total = Number(rental.total_rental ?? rental.total_amount ?? 0);

      return {
        total,
        paid,
        remaining: Math.max(total - paid, 0)
      };
    }

    async function showRentalDetail(rentalId) {
      try {
        const rental = await getRentalRecord(rentalId);
        const totals = paymentTotals(rental);
        const detail = (rental.rental_details || [])[0] || {};
        const dress = detail.dresses || {};
        let modal = document.getElementById('rentalDetailModal');

        if (!modal) {
          document.body.insertAdjacentHTML(
            'beforeend',
            '<div class="modal" id="rentalDetailModal"><div class="modal-box"><div class="modal-head"><h3>Detail Rental</h3><button class="close" onclick="closeModal(\'rentalDetailModal\')">×</button></div><div id="rentalDetailContent"></div></div></div>'
          );
          modal = document.getElementById('rentalDetailModal');
        }

        document.getElementById('rentalDetailContent').innerHTML = `
          <div class="form-grid">
            <div class="field"><label>Kode Rental</label><input readonly value="${la.escape(rental.rental_code)}"></div>
            <div class="field"><label>Customer</label><input readonly value="${la.escape(rental.customers ? rental.customers.name : '-')}\"></div>
            <div class="field"><label>Dress</label><input readonly value="${la.escape(dress.dress_code || '-')} - ${la.escape(dress.name || '')}"></div>
            <div class="field"><label>Ukuran</label><input readonly value="${la.escape(detail.dress_variants?.size || '-')}"></div>
            <div class="field"><label>Unit Fisik</label><input readonly value="${la.escape(detail.dress_units?.unit_code || '-')} / ${la.escape(detail.dress_units?.status || '-')}"></div>
            <div class="field"><label>Warna</label><input readonly value="${la.escape(detail.dress_variants?.color || '-')}"></div>
            <div class="field"><label>Tanggal Rental</label><input readonly value="${la.escape(rental.rental_date)}"></div>
            <div class="field"><label>Tanggal Pengembalian</label><input readonly value="${la.escape(rental.return_due_date)}"></div>
            <div class="field"><label>Total Rental</label><input readonly value="${money(totals.total)}"></div>
            <div class="field"><label>Deposit Diterima</label><input readonly value="${money(rental.deposit_received_amount)}"></div>
            <div class="field"><label>Status Rental</label><input readonly value="${la.escape(rental.rental_status || 'Booked')}"></div>
            <div class="field"><label>Status Pembayaran</label><input readonly value="${la.escape(rental.payment_status || computeStatus(totals.total, totals.paid))}"></div>
            <div class="field"><label>Total Dibayar</label><input readonly value="${money(totals.paid)}"></div>
            <div class="field"><label>Sisa Pembayaran</label><input readonly value="${money(totals.remaining)}"></div>
          </div>
          <h4>Riwayat Pembayaran</h4>
          <div class="table-wrap"><table><thead><tr><th>Tanggal</th><th>Tipe</th><th>Jumlah</th><th>Metode</th></tr></thead><tbody>${(rental.payments || []).length ? rental.payments.map(payment => `<tr><td>${la.formatDate(payment.payment_date)}</td><td>${la.escape(payment.payment_type || '-')}</td><td>${money(payment.amount)}</td><td>${la.escape(payment.payment_method || '-')}</td></tr>`).join('') : '<tr><td colspan="4">Belum ada pembayaran.</td></tr>'}</tbody></table></div>
          <div class="form-actions"><button type="button" class="btn btn-light" id="detailPayButton" ${totals.remaining <= 0 || rental.rental_status === 'Cancelled' ? 'disabled' : ''}>+ Bayar Sisa</button><button type="button" class="btn btn-light" id="detailCancelButton" ${['Cancelled', 'Completed'].includes(rental.rental_status || '') ? 'disabled' : ''}>Batalkan Rental</button><button type="button" class="btn btn-light" id="detailEditButton" ${['Cancelled', 'Completed'].includes(rental.rental_status || '') ? 'disabled' : ''}>Edit Rental</button><button type="button" class="btn btn-light" id="detailPrintButton">Cetak Invoice</button></div>
        `;

        document
          .getElementById('detailPayButton')
          .addEventListener('click', () =>
            payRentalBalance(rental.id, totals.remaining)
          );

        document
          .getElementById('detailCancelButton')
          .addEventListener('click', () => cancelRental(rental.id));

        document
          .getElementById('detailEditButton')
          .addEventListener('click', () => editRental(rental));

        document
          .getElementById('detailPrintButton')
          .addEventListener('click', () => printRentalInvoice(rental.id));

        openModal('rentalDetailModal');
      } catch (error) {
        la.toast(
          error.message || 'Detail rental gagal dimuat.',
          'error'
        );
      }
    }

    async function payRentalBalance(rentalId, balance) {
      const rental = await getRentalRecord(rentalId);
      const totals = paymentTotals(rental);
      let modal = document.getElementById('rentalPaymentModal');

      if (!modal) {
        document.body.insertAdjacentHTML(
          'beforeend',
          '<div class="modal" id="rentalPaymentModal"><div class="modal-box"><div class="modal-head"><h3>Pembayaran Rental</h3><button class="close" onclick="closeModal(\'rentalPaymentModal\')">×</button></div><form id="rentalPaymentForm"><div id="rentalPaymentSummary"></div><div class="form-grid"><div class="field"><label>Nominal Pembayaran</label><input id="rental_payment_amount" type="number" min="1" required></div><div class="field"><label>Metode</label><select id="rental_payment_method"><option>Cash</option><option>Transfer Bank</option><option>E-Wallet</option><option>QRIS</option><option>Lainnya</option></select></div><div class="field"><label>Tanggal</label><input id="rental_payment_date" type="date" required></div><div class="field"><label>Nomor Referensi</label><input id="rental_payment_reference"></div><div class="field"><label>Catatan</label><input id="rental_payment_notes"></div></div><div id="rentalPaymentPreview" class="card" style="padding:12px;margin-top:12px"></div><div class="form-actions"><button type="button" class="btn btn-light" onclick="closeModal(\'rentalPaymentModal\')">Batal</button><button type="submit" class="btn btn-primary">Konfirmasi Pembayaran</button></div></form></div></div>'
        );
        modal = document.getElementById('rentalPaymentModal');
      }

      const paymentForm = document.getElementById('rentalPaymentForm');

      setValue(
        'rental_payment_amount',
        String(Math.min(balance, totals.remaining))
      );
      setValue(
        'rental_payment_date',
        new Date().toISOString().slice(0, 10)
      );

      document.getElementById('rentalPaymentSummary').innerHTML =
        `<p><strong>${la.escape(rental.rental_code)}</strong><br>Customer: ${la.escape(rental.customers ? rental.customers.name : '-')}<br>Total tagihan: ${money(totals.total)}<br>Telah dibayar: ${money(totals.paid)}<br>Sisa tagihan: ${money(totals.remaining)}</p>`;

      const updatePreview = () => {
        const amount = Number(getValue('rental_payment_amount') || 0);
        const after = Math.max(totals.remaining - amount, 0);
        const status =
          amount > totals.remaining
            ? 'Nominal tidak valid'
            : after <= 0
              ? 'LUNAS'
              : 'SEBAGIAN DIBAYAR';

        document.getElementById('rentalPaymentPreview').innerHTML =
          `<strong>Sebelum Disimpan</strong><br>Nominal: ${money(amount)}<br>Sisa sebelum pembayaran: ${money(totals.remaining)}<br>Sisa setelah pembayaran: ${money(after)}<br>Status setelah pembayaran: ${status}`;
      };

      document.getElementById('rental_payment_amount').oninput = updatePreview;
      updatePreview();
      openModal('rentalPaymentModal');

      paymentForm.onsubmit = async event => {
        event.preventDefault();

        const amount = Number(getValue('rental_payment_amount') || 0);

        if (!amount || amount <= 0 || amount > totals.remaining) {
          la.toast(
            'Jumlah pembayaran tidak boleh melebihi sisa tagihan.',
            'error'
          );
          return;
        }

        const result = await supabase.rpc('record_rental_payment', {
          p_rental_id: rentalId,
          p_payment_date: getValue('rental_payment_date'),
          p_amount: amount,
          p_payment_method:
            document.getElementById('rental_payment_method').value,
          p_payment_type: 'PELUNASAN',
          p_payment_reference:
            getValue('rental_payment_reference') || null,
          p_notes: getValue('rental_payment_notes') || null
        });

        if (result.error) {
          la.toast(result.error.message, 'error');
          return;
        }

        const paymentRecord = Array.isArray(result.data)
          ? result.data[0]
          : result.data;

        closeModal('rentalPaymentModal');

        const newTotalPaid = totals.paid + amount;
        const receipt = document.createElement('div');
        receipt.className = 'modal show';
        receipt.id = 'paymentSuccessModal';
        receipt.innerHTML =
          `<div class="modal-box"><div class="modal-head"><h3>Pembayaran Berhasil</h3><button class="close" onclick="closeModal(\'paymentSuccessModal\')">×</button></div><p><strong>${la.escape(paymentRecord.payment_code || '-')}</strong><br>Rental: ${la.escape(rental.rental_code)}<br>Customer: ${la.escape(rental.customers ? rental.customers.name : '-')}<br>Nominal: ${money(amount)}<br>Metode: ${la.escape(paymentRecord.payment_method || '-')}<br>Total dibayar: ${money(newTotalPaid)}<br>Sisa: ${money(Math.max(totals.total - newTotalPaid, 0))}<br>Status: ${newTotalPaid >= totals.total ? 'LUNAS' : 'SEBAGIAN DIBAYAR'}</p><div class="form-actions"><button type="button" class="btn btn-primary" id="printPaymentReceiptButton">Cetak Bukti Pembayaran</button><button type="button" class="btn btn-light" onclick="closeModal(\'paymentSuccessModal\')">Tutup</button></div></div>`;

        document.body.appendChild(receipt);
        document
          .getElementById('printPaymentReceiptButton')
          .addEventListener('click', () =>
            printRentalPaymentReceipt({
              rental,
              payment: paymentRecord,
              amount,
              totalPaid: newTotalPaid,
              remaining: Math.max(totals.total - newTotalPaid, 0),
              rentalTotal: totals.total
            })
          );
        renderList();
      };
    }

    async function editRental(rental) {
      const newDueDate = window.prompt(
        'Tanggal jatuh tempo baru (YYYY-MM-DD):',
        rental.return_due_date
      );

      if (
        !newDueDate ||
        new Date(newDueDate) < new Date(rental.rental_date)
      ) {
        la.toast('Tanggal jatuh tempo tidak valid.', 'error');
        return;
      }

      const newStatus = window.prompt(
        'Status rental (Booked/Ongoing):',
        rental.rental_status || 'Booked'
      );

      if (!['Booked', 'Ongoing'].includes(newStatus)) {
        la.toast('Status rental tidak valid.', 'error');
        return;
      }

      const result = await supabase.rpc('update_rental_schedule', {
        p_rental_id: rental.id,
        p_return_due_date: newDueDate,
        p_rental_status: newStatus
      });

      if (result.error) {
        la.toast(result.error.message, 'error');
        return;
      }

      la.toast('Rental berhasil diperbarui.');
      closeModal('rentalDetailModal');
      renderList();
    }

    async function cancelRental(rentalId) {
      const rental = await getRentalRecord(rentalId);
      const totals = paymentTotals(rental);
      let modal = document.getElementById('rentalCancelModal');

      if (!modal) {
        document.body.insertAdjacentHTML(
          'beforeend',
          '<div class="modal" id="rentalCancelModal"><div class="modal-box"><div class="modal-head"><h3>Pembatalan Rental</h3><button class="close" onclick="closeModal(\'rentalCancelModal\')">×</button></div><form id="rentalCancelForm"><div id="rentalCancelSummary"></div><div class="field"><label>Alasan Pembatalan</label><textarea id="cancel_reason" required></textarea></div><div class="field"><label>Penanganan DP</label><label><input type="radio" name="cancel_action" value="REFUND" checked> Kembalikan DP</label><label><input type="radio" name="cancel_action" value="FORFEIT"> DP menjadi biaya pembatalan</label></div><div class="form-actions"><button type="button" class="btn btn-light" onclick="closeModal(\'rentalCancelModal\')">Batal</button><button type="submit" class="btn btn-primary">Konfirmasi Pembatalan</button></div></form></div></div>'
        );
        modal = document.getElementById('rentalCancelModal');
      }

      document.getElementById('rentalCancelSummary').innerHTML =
        `<p><strong>${la.escape(rental.rental_code)}</strong><br>Customer: ${la.escape(rental.customers ? rental.customers.name : '-')}<br>Total rental: ${money(totals.total)}<br>Total dibayar: ${money(totals.paid)}<br>Sisa: ${money(totals.remaining)}</p>`;

      document.querySelector(
        '#rentalCancelForm input[value="REFUND"]'
      ).disabled = totals.paid <= 0;

      if (totals.paid <= 0) {
        document.querySelector(
          '#rentalCancelForm input[value="FORFEIT"]'
        ).checked = true;
      }

      openModal('rentalCancelModal');

      document.getElementById('rentalCancelForm').onsubmit = async event => {
        event.preventDefault();

        const reason = getValue('cancel_reason').trim();

        if (!reason) {
          la.toast('Alasan pembatalan wajib diisi.', 'error');
          return;
        }

        const action = document.querySelector(
          'input[name="cancel_action"]:checked'
        ).value;

        const result = await supabase.rpc('cancel_rental', {
          p_rental_id: rentalId,
          p_reason: reason,
          p_deposit_action: action
        });

        if (result.error) {
          la.toast(result.error.message, 'error');
          return;
        }

        closeModal('rentalCancelModal');
        la.toast('Rental berhasil dibatalkan.');
        renderList();
      };
    }

    async function printRentalPaymentReceipt({
      rental,
      payment,
      amount,
      totalPaid,
      remaining,
      rentalTotal,
      documentType = 'payment',
      popupWindow = null
    }) {
      const popup = popupWindow || window.open('', '_blank');

      if (!popup) {
        la.toast('Popup bukti pembayaran diblokir browser.', 'error');
        return;
      }

      try {
        const settingsResult = await supabase
          .from('business_settings')
          .select('business_name, logo_url, address, phone, email, website')
          .eq('id', true)
          .maybeSingle();
        const company = settingsResult.data || {};
        const customer = rental.customers || {};
        const escape = value => la.escape(String(value ?? ''));
        const dateLabel = value => {
          if (!value) return '-';
          const date = new Date(`${value}T00:00:00`);
          return Number.isNaN(date.getTime())
            ? escape(value)
            : escape(date.toLocaleDateString('id-ID', { dateStyle: 'long' }));
        };
        const logoUrl = /^https?:\/\//i.test(company.logo_url || '')
          ? escape(company.logo_url)
          : '';
        const details = (rental.rental_details || []).map(item => {
          const dress = item.dresses || {};
          const variant = item.dress_variants || {};
          const unit = item.dress_units || {};
          const quantity = Number(item.quantity || 1);
          const subtotal = Number(
            item.subtotal ?? Number(item.rental_price || 0) * quantity
          );
          const variation = [variant.size, variant.color].filter(Boolean).join(' / ') || '-';

          return `<tr><td><strong>${escape(dress.name || 'Dress rental')}</strong><small>${escape(dress.dress_code || '-')} ${unit.unit_code ? `· Unit ${escape(unit.unit_code)}` : ''}</small></td><td>${escape(variation)}</td><td class="number">${quantity}</td><td class="number">${money(subtotal)}</td></tr>`;
        }).join('');
        const companyDetails = [
          company.address,
          [company.phone, company.email].filter(Boolean).join(' · '),
          company.website
        ].filter(Boolean).map(escape).join('<br>');
        const paymentStatus = remaining <= 0 ? 'LUNAS' : 'SEBAGIAN DIBAYAR';
        const isRentalInvoice = documentType === 'rental';
        const documentTitle = isRentalInvoice ? 'Invoice Penyewaan' : 'Bukti Pembayaran';
        const documentCode = isRentalInvoice
          ? rental.rental_code
          : payment.payment_code || rental.rental_code;
        const headlineLabel = isRentalInvoice ? 'Total nilai rental' : 'Jumlah diterima';
        const headlineAmount = isRentalInvoice ? rentalTotal : amount;
        const paymentDate = payment.payment_date
          ? dateLabel(payment.payment_date)
          : 'Belum ada pembayaran';

        popup.document.write(`<!doctype html>
          <html lang="id">
            <head>
              <meta charset="utf-8">
              <meta name="viewport" content="width=device-width, initial-scale=1">
              <title>${escape(documentTitle)} ${escape(documentCode)}</title>
              <style>
                *{box-sizing:border-box}
                body{margin:0;padding:32px;background:#eef3f1;color:#203331;font:14px/1.55 Arial,sans-serif}
                .receipt{max-width:780px;margin:0 auto;padding:42px;background:#fff;border:1px solid #dce7e3;box-shadow:0 12px 36px rgba(24,52,47,.08)}
                .masthead{display:flex;justify-content:space-between;align-items:flex-start;gap:24px;padding-bottom:24px;border-bottom:2px solid #187d72}
                .brand{display:flex;align-items:center;gap:14px;min-width:0}
                .mark{width:54px;height:54px;flex:0 0 54px;display:grid;place-items:center;overflow:hidden;border-radius:11px;background:#e6f3ef;color:#187d72;font:30px Georgia,serif}
                .mark img{width:100%;height:100%;object-fit:contain}
                .brand h1{margin:0 0 5px;font-size:18px;letter-spacing:0}
                .company-details{color:#71817e;font-size:11px}
                .document{text-align:right}
                .eyebrow{color:#187d72;font-size:10px;font-weight:700;letter-spacing:1.2px}
                .document h2{margin:3px 0 7px;font-size:24px;letter-spacing:0}
                .code{display:inline-block;padding:6px 9px;border-radius:6px;background:#edf5f2;color:#176e64;font-weight:700}
                .issued{margin:7px 0 0;color:#71817e;font-size:11px}
                .amount-panel{margin:24px 0;padding:20px;border-radius:9px;background:#18302f;color:#fff}
                .amount-panel small{display:block;color:#c1d5cf;font-size:10px;font-weight:700;letter-spacing:1px;text-transform:uppercase}
                .amount-panel strong{display:block;margin-top:5px;font-size:30px;line-height:1.2}
                .status{float:right;padding:6px 10px;border-radius:99px;background:#d7eee4;color:#176e50;font-size:10px;font-weight:700}
                .grid{display:grid;grid-template-columns:1fr 1fr;gap:14px;margin-bottom:23px}
                .info{padding:14px;border:1px solid #e1e9e6;border-radius:8px}
                .label{display:block;color:#71817e;font-size:9px;font-weight:700;letter-spacing:1px;text-transform:uppercase}
                .info strong{display:block;margin-top:5px;font-size:14px}
                .muted{display:block;margin-top:3px;color:#71817e;font-size:11px;overflow-wrap:anywhere}
                table{width:100%;border-collapse:collapse}
                th{padding:9px 7px;border-bottom:1px solid #cfdcd7;color:#71817e;font-size:9px;text-align:left;text-transform:uppercase}
                td{padding:11px 7px;border-bottom:1px solid #e7eeeb;vertical-align:top}
                td small{display:block;margin-top:3px;color:#71817e;font-size:10px}
                .number{text-align:right;white-space:nowrap}
                .total{width:min(100%,340px);margin:16px 0 0 auto}
                .total-row{display:flex;justify-content:space-between;gap:18px;padding:6px 0;color:#5f716d}
                .total-row strong{color:#203331}
                .total-row.emphasis{margin-top:5px;padding-top:11px;border-top:1px solid #cfdcd7;font-weight:700}
                .total-row.emphasis strong{color:#187d72;font-size:17px}
                .reference{margin-top:20px;padding:12px 14px;border-left:3px solid #e47d65;background:#fff8f5;color:#5f716d;font-size:11px;overflow-wrap:anywhere}
                .footer{display:flex;justify-content:space-between;gap:20px;margin-top:30px;padding-top:16px;border-top:1px solid #e1e9e6;color:#71817e;font-size:10px}
                .actions{display:flex;justify-content:center;margin-top:22px}
                .print-button{padding:11px 18px;border:0;border-radius:7px;background:#187d72;color:#fff;font-weight:700;cursor:pointer}
                @media(max-width:600px){body{padding:0}.receipt{padding:24px 16px;border:0;box-shadow:none}.masthead{gap:14px}.mark{width:42px;height:42px;flex-basis:42px}.brand h1{font-size:15px}.company-details{font-size:9px}.document h2{font-size:18px}.amount-panel strong{font-size:25px}.grid{grid-template-columns:1fr}.footer{flex-direction:column}}
                @page{size:A4;margin:16mm}
                @media print{body{padding:0;background:#fff}.receipt{max-width:none;padding:0;border:0;box-shadow:none}.actions{display:none}.amount-panel,.status,.mark{-webkit-print-color-adjust:exact;print-color-adjust:exact}tr{break-inside:avoid}}
              </style>
            </head>
            <body>
              <article class="receipt">
                <header class="masthead">
                  <div class="brand">
                    <div class="mark">${logoUrl ? `<img src="${logoUrl}" alt="">` : 'L'}</div>
                    <div><h1>${escape(company.business_name || 'LAVÉ DRESS RENTAL')}</h1><div class="company-details">${companyDetails || 'Bukti pembayaran transaksi penyewaan'}</div></div>
                  </div>
                  <div class="document"><span class="eyebrow">${isRentalInvoice ? 'RINGKASAN TRANSAKSI' : 'TANDA TERIMA RESMI'}</span><h2>${isRentalInvoice ? 'INVOICE PENYEWAAN' : 'BUKTI PEMBAYARAN'}</h2><span class="code">${escape(documentCode)}</span><p class="issued">Diterbitkan ${escape(new Date().toLocaleDateString('id-ID', { dateStyle: 'long' }))}</p></div>
                </header>

                <section class="amount-panel"><span class="status">${paymentStatus}</span><small>${headlineLabel}</small><strong>${money(headlineAmount)}</strong></section>

                <section class="grid">
                  <div class="info"><span class="label">${isRentalInvoice ? 'Customer' : 'Diterima dari'}</span><strong>${escape(customer.name || '-')}</strong><span class="muted">${[customer.phone, customer.email, customer.address].filter(Boolean).map(escape).join('<br>') || 'Informasi kontak tidak tersedia'}</span></div>
                  <div class="info"><span class="label">${isRentalInvoice ? 'Pembayaran terakhir' : 'Detail pembayaran'}</span><strong>${paymentDate}</strong><span class="muted">Metode: ${escape(payment.payment_method || '-')}<br>Jenis: ${escape(payment.payment_type || 'PELUNASAN')}${payment.payment_code ? `<br>Kode pembayaran: ${escape(payment.payment_code)}` : ''}</span></div>
                  <div class="info"><span class="label">Transaksi rental</span><strong>${escape(rental.rental_code)}</strong><span class="muted">Periode: ${dateLabel(rental.rental_date)} – ${dateLabel(rental.return_due_date)}</span></div>
                  <div class="info"><span class="label">Ringkasan tagihan</span><strong>Total rental ${money(rentalTotal)}</strong><span class="muted">Total telah dibayar: ${money(totalPaid)}<br>Sisa tagihan: ${money(remaining)}</span></div>
                </section>

                <table><thead><tr><th>Item rental</th><th>Varian</th><th class="number">Qty</th><th class="number">Jumlah</th></tr></thead><tbody>${details || '<tr><td colspan="4">Pembayaran untuk transaksi penyewaan.</td></tr>'}</tbody></table>

                <section class="total"><div class="total-row"><span>Total rental</span><strong>${money(rentalTotal)}</strong></div><div class="total-row"><span>${isRentalInvoice ? 'Pembayaran sebelum transaksi terakhir' : 'Pembayaran sebelumnya'}</span><strong>${money(Math.max(totalPaid - amount, 0))}</strong></div><div class="total-row emphasis"><span>${isRentalInvoice ? 'Pembayaran terakhir' : 'Pembayaran ini'}</span><strong>${money(amount)}</strong></div><div class="total-row"><span>${isRentalInvoice ? 'Sisa tagihan saat ini' : 'Sisa setelah pembayaran'}</span><strong>${money(remaining)}</strong></div></section>

                ${(payment.payment_reference || payment.notes) ? `<div class="reference">${payment.payment_reference ? `Referensi: ${escape(payment.payment_reference)}` : ''}${payment.payment_reference && payment.notes ? '<br>' : ''}${payment.notes ? `Catatan: ${escape(payment.notes)}` : ''}</div>` : ''}
                <footer class="footer"><span>${isRentalInvoice ? 'Ringkasan transaksi penyewaan LAVÉ.' : 'Terima kasih atas pembayaran Anda.'}</span><span>Dokumen ini diterbitkan secara digital.</span></footer>
                <div class="actions"><button class="print-button" onclick="window.print()">Cetak / Simpan PDF</button></div>
              </article>
            </body>
          </html>`);
        popup.document.close();
        popup.setTimeout(() => {
          popup.focus();
          popup.print();
        }, 400);
      } catch (error) {
        popup.close();
        la.toast(error.message || 'Bukti pembayaran gagal dibuat.', 'error');
      }
    }

    async function printRentalInvoice(rentalId) {
      const popup = window.open('', '_blank');

      if (!popup) {
        la.toast('Popup invoice diblokir browser.', 'error');
        return;
      }

      try {
        const rental = await getRentalRecord(rentalId);
        const totals = paymentTotals(rental);
        const payment = (rental.payments || [])
          .slice()
          .sort((first, second) =>
            String(second.payment_date || '').localeCompare(String(first.payment_date || '')) ||
            String(second.created_at || '').localeCompare(String(first.created_at || ''))
          )[0];
        const paymentAmount = !payment
          ? 0
          : payment.payment_type === 'REFUND'
            ? -Number(payment.amount || 0)
            : Number(payment.amount || 0);

        await printRentalPaymentReceipt({
          rental,
          payment: payment || {
            payment_code: rental.rental_code,
            payment_method: '-',
            payment_type: 'Belum ada pembayaran'
          },
          amount: paymentAmount,
          totalPaid: totals.paid,
          remaining: totals.remaining,
          rentalTotal: totals.total,
          documentType: 'rental',
          popupWindow: popup
        });
      } catch (error) {
        popup.close();
        la.toast(
          error.message || 'Invoice gagal dibuat.',
          'error'
        );
      }
    }

    search && search.addEventListener('input', renderList);

    form.addEventListener('submit', async (e) => {
      e.preventDefault();

      let customerId = Number(getValue('customer_id'));
      const dressId = Number(getValue('dress_code') || 0);
      const dressVariantId = Number(getValue('dress_variant_id') || 0);
      const dressUnitId = Number(getValue('dress_unit_id') || 0);
      const rentalDate = getValue('rental_date');
      const returnDueDate = getValue('return_due_date');
      const depositAmount = Number(getValue('deposit_amount') || 0);
      const rentalPrice = Number(getValue('rental_price') || 0);
      const initialPayment = Number(getValue('initial_payment') || 0);

      if (
        !dressId ||
        !dressVariantId ||
        !dressUnitId ||
        !rentalDate ||
        !returnDueDate
      ) {
        la.toast(
          'Customer, model, ukuran, warna, unit fisik, dan tanggal wajib diisi.',
          'error'
        );
        return;
      }

      if (!customerId) {
        try {
          const customer = await ensureCustomerFromForm(
            getValue('customer_name'),
            getValue('customer_phone'),
            getValue('customer_email'),
            getValue('customer_address')
          );

          if (!customer) {
            la.toast(
              'Pilih customer atau isi nama customer baru.',
              'error'
            );
            return;
          }

          customerId = Number(customer.id);
        } catch (error) {
          la.toast(
            error.message || 'Customer gagal dibuat.',
            'error'
          );
          return;
        }
      }

      const dress = dressMap.get(String(dressId));

      const variant = variants.find(
        item =>
          Number(item.id) === dressVariantId &&
          Number(item.dress_id) === dressId
      );

      if (!dress || !variant) {
        la.toast('Model atau ukuran dress tidak valid.', 'error');
        return;
      }

      if (variant.available_quantity <= 0) {
        la.toast(
          'Ukuran tersebut tidak memiliki stok tersedia.',
          'error'
        );
        return;
      }

      if (new Date(returnDueDate) < new Date(rentalDate)) {
        la.toast(
          'Tanggal kembali tidak boleh lebih awal dari tanggal sewa.',
          'error'
        );
        return;
      }

      if (
        depositAmount < 0 ||
        initialPayment < 0 ||
        initialPayment > rentalPrice
      ) {
        la.toast(
          'Pembayaran awal tidak boleh melebihi total tagihan.',
          'error'
        );
        return;
      }

      const { error: transactionError } = await supabase.rpc(
        'create_rental_unit_transaction',
        {
          p_customer_id: customerId,
          p_dress_id: dress.id,
          p_dress_variant_id: variant.id,
          p_dress_unit_id: dressUnitId,
          p_rental_date: rentalDate,
          p_return_due_date: returnDueDate,
          p_total_rental: rentalPrice,
          p_rental_code: getValue('rental_code'),
          p_deposit_amount: depositAmount,
          p_rental_status:
            document.getElementById('rental_status').value,
          p_payment_amount: initialPayment,
          p_payment_date:
            getValue('initial_payment_date') || rentalDate,
          p_payment_method:
            document.getElementById('initial_payment_method').value,
          p_payment_type:
            document.getElementById('initial_payment_type').value
        }
      );

      if (transactionError) {
        la.toast(transactionError.message, 'error');
        return;
      }

      la.toast('Transaksi penyewaan berhasil disimpan.');
      closeModal('modal');
      form.reset();

      setValue('rental_code', await nextCode('rental'));
      setValue('rental_date', new Date().toISOString().slice(0, 10));
      setValue('return_due_date', defaultDate);
      setValue('deposit_amount', '0');
      setValue('total_amount', '0');
      setValue('initial_payment', '0');
      setValue(
        'initial_payment_date',
        new Date().toISOString().slice(0, 10)
      );

      updateRentalSummary();

      const refreshedVariants = await supabase
        .from('dress_variants')
        .select('*')
        .order('normalized_size');

      if (!refreshedVariants.error) {
        variants = refreshedVariants.data || [];
      }

      dressCodeInput.dispatchEvent(new Event('change'));
      renderList();
    });

    renderList();
  }

    async function initPurchasePage() {
    const root = document.querySelector('.main') || document.body;
    const legacyPage = document.querySelector('.page');
    if (legacyPage) legacyPage.style.display = 'none';

    const pageHtml = `
      <div class="card" style="padding:18px; margin-bottom:18px;">
        <h3>Pembelian Dress</h3>
        <form id="purchaseForm">
          <div class="form-grid">
            <div class="field">
              <label>Kode Pembelian</label>
              <input id="purchase_code" value="Otomatis dari sequence database" readonly>
            </div>
            <div class="field">
              <label>Supplier</label>
              <div style="display:flex;gap:8px;align-items:center;">
                <select id="supplier_id" required></select>
                <button type="button" class="btn btn-light" id="createSupplierBtn">+ Baru</button>
              </div>
              <div id="supplierPreview" class="muted" style="font-size:12px;margin-top:6px">Pilih supplier untuk melihat detail.</div>
            </div>
            <div class="field">
              <label>Tanggal Pembelian</label>
              <input id="purchase_date" type="date" required>
            </div>
            <div class="field">
              <label>Pilih Model Dress</label>
              <div style="display:flex;gap:8px;align-items:center;">
                <select id="dress_id"><option value="">Pilih model</option></select>
                <button type="button" class="btn btn-light" id="createDressBtn">+ Dress Baru</button>
              </div>
            </div>
            <div class="field">
              <label>Kode Model</label>
              <input id="new_dress_code" placeholder="Terbentuk saat pembelian disimpan" readonly>
            </div>
            <div class="field">
              <label>Nama Model</label>
              <input id="dress_name" placeholder="Nama dress">
            </div>
            <div class="field">
              <label>Kategori</label>
              <select id="category_id"></select>
            </div>
            <div class="field">
              <label>Ukuran</label>
              <select id="dress_size" required><option value="">Pilih ukuran</option></select>
              <input id="new_dress_size" placeholder="Ukuran baru" maxlength="20" hidden>
            </div>
            <div class="field">
              <label>Warna</label>
              <input id="dress_color" maxlength="50" required>
            </div>
            <div class="field">
              <label>Harga Beli</label>
              <input id="purchase_price" type="number" min="0" required>
            </div>
            <div class="field">
              <label>Harga Sewa</label>
              <input id="rental_price" type="number" min="0" value="0">
            </div>
            <div class="field">
              <label>Qty</label>
              <input id="quantity" type="number" min="1" value="1" required>
            </div>
            <div class="field">
              <label>Status Pembayaran</label>
              <select id="purchase_payment_status"><option value="Unpaid">Kredit / Belum Dibayar</option><option value="Paid">Tunai / Sudah Dibayar</option></select>
            </div>
            <div class="field">
              <label>Metode Pembayaran</label>
              <select id="purchase_payment_method"><option>Cash</option><option>Transfer</option><option>E-Wallet</option></select>
            </div>
            <div class="field">
              <label>Subtotal</label>
              <input id="subtotal" type="number" min="0" readonly>
            </div>
          </div>
          <div class="form-actions">
            <button type="submit" class="btn btn-primary">Simpan Pembelian</button>
          </div>
        </form>
      </div>
      <div class="card table-card">
        <div class="table-head"><strong>Riwayat Pembelian</strong></div>
        <div class="table-wrap">
          <table>
            <thead><tr><th>Kode</th><th>Supplier</th><th>Tanggal</th><th>Nominal</th><th>Status</th></tr></thead>
            <tbody id="purchaseRows"></tbody>
          </table>
        </div>
      </div>
    `;

    root.insertAdjacentHTML('beforeend', pageHtml);

    const purchaseForm = document.getElementById('purchaseForm');
    const supplierSelect = document.getElementById('supplier_id');
    const dressSelect = document.getElementById('dress_id');
    const categorySelect = document.getElementById('category_id');
    const purchaseRows = document.getElementById('purchaseRows');
    const purchasePriceInput = document.getElementById('purchase_price');
    const rentalPriceInput = document.getElementById('rental_price');
    const quantityInput = document.getElementById('quantity');
    const subtotalInput = document.getElementById('subtotal');
    const sizeSelect = document.getElementById('dress_size');
    const newSizeInput = document.getElementById('new_dress_size');
    let isNewModel = false;

    const [suppliers, categories, dressRows, variantResult] = await Promise.all([
      loadSuppliers(),
      loadCategories(),
      loadDresses(),
      supabase.from('dress_variants').select('*').order('normalized_size')
    ]);

    if (variantResult.error) {
      if (
        variantResult.error.code === 'PGRST205' &&
        variantResult.error.message.includes('dress_variants')
      ) {
        throw new Error('Database belum memiliki tabel varian dress. Jalankan migration 23-31 secara berurutan; tinjau pemetaan duplikat dan rekonsiliasi stocktake sebelum menyewakan stok UNVERIFIED. Jika tabel sudah ada, jalankan NOTIFY pgrst, \'reload schema\';');
      }
      throw variantResult.error;
    }

    const dresses = dressRows.filter(dress => dress.is_active !== false);
    let variants = variantResult.data || [];

    supplierSelect.innerHTML =
      '<option value="">Pilih Supplier</option>' +
      suppliers
        .map(s => `<option value="${s.id}">${s.supplier_code} - ${s.name}</option>`)
        .join('');

    categorySelect.innerHTML =
      '<option value="">Pilih Kategori</option>' +
      categories
        .map(c => `<option value="${c.id}">${c.category_name}</option>`)
        .join('');

    dressSelect.innerHTML =
      '<option value="">Pilih model</option>' +
      dresses
        .map(d => `<option value="${d.id}">${la.escape(d.dress_code)} - ${la.escape(d.name)}</option>`)
        .join('');

    document.getElementById('purchase_date').value =
      new Date().toISOString().slice(0, 10);

    function updateSizeOptions(dressId) {
      const sizes = [
        ...new Set(
          variants
            .filter(variant => Number(variant.dress_id) === Number(dressId))
            .map(variant => variant.size)
        )
      ];

      sizeSelect.innerHTML =
        '<option value="">Pilih ukuran</option>' +
        sizes
          .map(size => `<option value="${la.escape(size)}">${la.escape(size)}</option>`)
          .join('') +
        '<option value="__new__">+ Ukuran baru</option>';

      sizeSelect.value = '';
      newSizeInput.value = '';
      newSizeInput.hidden = false;
      newSizeInput.hidden = true;
    }

    function selectedSize() {
      return sizeSelect.value === '__new__'
        ? newSizeInput.value.trim().toUpperCase()
        : sizeSelect.value;
    }

    function updateSubtotal() {
      const subtotal =
        Number(purchasePriceInput.value || 0) *
        Number(quantityInput.value || 1);
      subtotalInput.value = String(subtotal);
    }

    purchasePriceInput.addEventListener('input', updateSubtotal);
    quantityInput.addEventListener('input', updateSubtotal);

    sizeSelect.addEventListener('change', () => {
      newSizeInput.hidden = sizeSelect.value !== '__new__';
      if (sizeSelect.value === '__new__') newSizeInput.focus();
    });

    dressSelect.addEventListener('change', () => {
      const selected = dresses.find(
        d => Number(d.id) === Number(dressSelect.value)
      );

      if (!selected) return;

      isNewModel = false;
      document.getElementById('new_dress_code').value =
        selected.dress_code || '';
      document.getElementById('dress_name').value =
        selected.name || '';
      document.getElementById('dress_name').readOnly = true;
      categorySelect.value =
        selected.category_id ? String(selected.category_id) : '';
      categorySelect.disabled = true;
      document.getElementById('dress_color').value =
        selected.color || '';
      document.getElementById('dress_color').readOnly = false;
      purchasePriceInput.value = Number(selected.purchase_price || 0);
      rentalPriceInput.value = Number(selected.rental_price || 0);
      updateSizeOptions(selected.id);
      updateSubtotal();
    });

    async function renderPurchaseRows() {
      const { data, error } = await supabase
        .from('purchases')
        .select('*, suppliers(name)')
        .order('id', { ascending: false });

      if (error) {
        la.toast(error.message, 'error');
        return;
      }

      purchaseRows.innerHTML = (data || []).length
        ? (data || [])
            .map(p => `
        <tr>
          <td>${la.escape(p.purchase_code)}</td>
          <td>${la.escape(p.suppliers ? p.suppliers.name : '-')}</td>
          <td>${la.formatDate(p.purchase_date)}</td>
          <td>${money(p.total_amount)}</td>
          <td>${la.escape(p.payment_status || 'Unpaid')}</td>
        </tr>
      `)
            .join('')
        : '<tr><td colspan="5" class="empty">Belum ada pembelian.</td></tr>';
    }

    const supplierPreview = document.getElementById('supplierPreview');

    supplierSelect.addEventListener('change', () => {
      const supplier = suppliers.find(
        item => Number(item.id) === Number(supplierSelect.value)
      );

      supplierPreview.textContent = supplier
        ? `${supplier.supplier_code} - ${supplier.name} | ${supplier.phone || 'Telepon belum diisi'} | ${supplier.email || 'Email belum diisi'}`
        : 'Pilih supplier untuk melihat detail.';
    });

    document.getElementById('createSupplierBtn').addEventListener('click', () => {
      let modal = document.getElementById('newSupplierModal');

      if (!modal) {
        document.body.insertAdjacentHTML(
          'beforeend',
          '<div class="modal" id="newSupplierModal"><div class="modal-box"><div class="modal-head"><h3>Tambah Supplier Baru</h3><button class="close" type="button" id="closeSupplierModal">x</button></div><form id="newSupplierForm"><div class="form-grid"><div class="field"><label>Kode Supplier</label><input value="Otomatis dari sequence database" readonly></div><div class="field"><label>Nama Supplier *</label><input id="newSupplierName" required maxlength="100"></div><div class="field"><label>No. Telepon</label><input id="newSupplierPhone"></div><div class="field"><label>Email</label><input id="newSupplierEmail" type="email"></div><div class="field"><label>Alamat</label><input id="newSupplierAddress"></div><div class="field"><label>Catatan</label><textarea id="newSupplierNotes" rows="3"></textarea></div></div><div class="form-actions"><button type="button" class="btn btn-light" id="closeSupplierModalSecondary">Batal</button><button class="btn btn-primary">Simpan Supplier</button></div></form></div></div>'
        );

        modal = document.getElementById('newSupplierModal');

        const closeSupplierModal = () =>
          modal.classList.remove('show');

        document
          .getElementById('closeSupplierModal')
          .addEventListener('click', closeSupplierModal);

        document
          .getElementById('closeSupplierModalSecondary')
          .addEventListener('click', closeSupplierModal);

        document
          .getElementById('newSupplierForm')
          .addEventListener('submit', async event => {
            event.preventDefault();

            try {
              const supplier = await ensureSupplierFromForm(
                document.getElementById('newSupplierName').value,
                document.getElementById('newSupplierPhone').value,
                document.getElementById('newSupplierEmail').value,
                document.getElementById('newSupplierAddress').value,
                document.getElementById('newSupplierNotes').value
              );

              if (!supplier) return;

              suppliers.push(supplier);

              const option = document.createElement('option');
              option.value = supplier.id;
              option.textContent =
                `${supplier.supplier_code} - ${supplier.name}`;
              supplierSelect.appendChild(option);
              supplierSelect.value = String(supplier.id);
              supplierSelect.dispatchEvent(new Event('change'));

              closeSupplierModal();
              event.target.reset();
              la.toast('Supplier tersimpan dan otomatis terpilih.');
            } catch (error) {
              la.handleSupabaseError(error, {
                module: 'Supplier',
                operation: 'INSERT'
              });
              la.toast(
                error.message || 'Supplier gagal dibuat.',
                'error'
              );
            }
          });
      }

      modal.classList.add('show');
    });

    document.getElementById('createDressBtn').addEventListener('click', () => {
      isNewModel = true;
      dressSelect.value = '';
      document.getElementById('new_dress_code').value =
        'Dibuat otomatis saat pembelian disimpan';
      document.getElementById('dress_name').value = '';
      document.getElementById('dress_name').readOnly = false;
      categorySelect.value = '';
      categorySelect.disabled = false;
      document.getElementById('dress_color').value = '';
      document.getElementById('dress_color').readOnly = false;
      sizeSelect.innerHTML =
        '<option value="__new__">Masukkan ukuran pertama</option>';
      sizeSelect.value = '__new__';
      newSizeInput.value = '';
      newSizeInput.hidden = false;
      purchasePriceInput.value = '';
      rentalPriceInput.value = '0';
      updateSubtotal();
    });

    purchaseForm.addEventListener('submit', async (event) => {
      event.preventDefault();

      const supplierId = Number(supplierSelect.value || 0);
      const purchaseDate =
        document.getElementById('purchase_date').value;
      const purchasePrice = Number(purchasePriceInput.value || 0);
      const rentalPrice = Number(rentalPriceInput.value || 0);
      const quantity = Number(quantityInput.value || 1);
      const subtotal = Number(subtotalInput.value || 0);
      const selectedDressId =
        !isNewModel && dressSelect.value
          ? Number(dressSelect.value)
          : null;
      const selectedSizeValue = selectedSize();
      const selectedColorValue =
        document.getElementById('dress_color').value.trim();

      if (
        !supplierId ||
        !purchaseDate ||
        purchasePrice <= 0 ||
        !Number.isInteger(quantity) ||
        quantity <= 0 ||
        !selectedSizeValue ||
        !selectedColorValue
      ) {
        la.toast(
          'Supplier, tanggal, model, ukuran, warna, harga beli, dan quantity valid wajib diisi.',
          'error'
        );
        return;
      }

      if (!isNewModel && !selectedDressId) {
        la.toast(
          'Pilih model dress atau gunakan tombol Dress Baru.',
          'error'
        );
        return;
      }

      if (
        isNewModel &&
        (
          !document.getElementById('dress_name').value.trim() ||
          !categorySelect.value
        )
      ) {
        la.toast(
          'Nama dan kategori wajib diisi untuk model dress baru.',
          'error'
        );
        return;
      }

      if (isNewModel) {
        const newName =
          document.getElementById('dress_name').value.trim().toLowerCase();
        const newCategory = Number(categorySelect.value);

        const duplicateModel = dresses.find(
          dress =>
            dress.name.trim().toLowerCase() === newName &&
            Number(dress.category_id) === newCategory
        );

        if (duplicateModel) {
          la.toast(
            `Model ${duplicateModel.dress_code} sudah ada. Pilih model tersebut lalu tambahkan ukuran dan warna.`,
            'error'
          );
          return;
        }
      }

      try {
        const { data: purchaseResult, error: purchaseError } =
          await supabase.rpc('create_purchase_transaction', {
            p_supplier_id: supplierId,
            p_purchase_date: purchaseDate,
            p_payment_status:
              document.getElementById('purchase_payment_status').value,
            p_payment_method:
              document.getElementById('purchase_payment_method').value,
            p_dress_id: selectedDressId,
            p_dress_name:
              document.getElementById('dress_name').value.trim() || null,
            p_category_id:
              categorySelect.value ? Number(categorySelect.value) : null,
            p_size: selectedSizeValue,
            p_color:
              document.getElementById('dress_color').value.trim() || null,
            p_purchase_price: purchasePrice,
            p_rental_price: rentalPrice,
            p_quantity: quantity
          });

        if (purchaseError) throw purchaseError;

        la.toast('Pembelian dress berhasil disimpan.');
        purchaseForm.reset();
        isNewModel = false;
        categorySelect.disabled = false;
        document.getElementById('dress_name').readOnly = false;
        document.getElementById('dress_color').readOnly = false;
        sizeSelect.innerHTML =
          '<option value="">Pilih ukuran</option>';
        newSizeInput.hidden = true;
        document.getElementById('purchase_code').value =
          'Otomatis dari sequence database';
        document.getElementById('purchase_date').value =
          new Date().toISOString().slice(0, 10);
        purchasePriceInput.value = '';
        rentalPriceInput.value = '0';
        quantityInput.value = '1';
        subtotalInput.value = '0';

        try {
          const [refreshedDresses, refreshedVariants] =
            await Promise.all([
              loadDresses(),
              supabase
                .from('dress_variants')
                .select('*')
                .order('normalized_size')
            ]);

          if (refreshedVariants.error) {
            throw refreshedVariants.error;
          }

          dresses.splice(
            0,
            dresses.length,
            ...refreshedDresses.filter(
              dress => dress.is_active !== false
            )
          );

          variants = refreshedVariants.data || [];

          dressSelect.innerHTML =
            '<option value="">Pilih model</option>' +
            dresses
              .map(
                dress =>
                  `<option value="${dress.id}">${la.escape(dress.dress_code)} - ${la.escape(dress.name)}</option>`
              )
              .join('');
        } catch (refreshError) {
          la.toast(
            `Pembelian tersimpan, tetapi pilihan model perlu dimuat ulang: ${refreshError.message}`,
            'error'
          );
        }

        renderPurchaseRows();
      } catch (error) {
        la.toast(
          error.message || 'Pembelian gagal disimpan.',
          'error'
        );
      }
    });

    renderPurchaseRows();
    updateSubtotal();
  }

    async function initPayablePage() {
    const root = document.querySelector('.main') || document.body;
    const legacyPage = document.querySelector('.page');
    if (legacyPage) legacyPage.style.display = 'none';

    const pageHtml = `
      <div class="card" style="padding:18px; margin-bottom:18px;">
        <h3>Pembayaran Utang Supplier</h3>
        <form id="payableForm">
          <div class="form-grid">
            <div class="field"><label>Pembelian</label><select id="payable_purchase_id" required></select></div>
            <div class="field"><label>Supplier</label><input id="payable_supplier" readonly></div>
            <div class="field"><label>Total Pembelian</label><input id="payable_total" readonly></div>
            <div class="field"><label>Total Terbayar</label><input id="payable_paid" readonly></div>
            <div class="field"><label>Sisa Utang</label><input id="payable_balance" readonly></div>
            <div class="field"><label>Tanggal Pembayaran</label><input id="payable_date" type="date" required></div>
            <div class="field"><label>Jumlah Pembayaran</label><input id="payable_amount" type="number" min="1" required></div>
            <div class="field"><label>Metode Pembayaran</label><select id="payable_method"><option>Cash</option><option>Transfer</option><option>E-Wallet</option></select></div>
            <div class="field"><label>Keterangan</label><input id="payable_description"></div>
          </div>
          <div class="form-actions"><button type="submit" class="btn btn-primary">Simpan Pembayaran Utang</button></div>
        </form>
      </div>
      <div class="card table-card"><div class="table-head"><strong>Daftar Utang Supplier</strong></div><div class="table-wrap"><table><thead><tr><th>Pembelian</th><th>Supplier</th><th>Total</th><th>Terbayar</th><th>Sisa</th><th>Status</th></tr></thead><tbody id="payableRows"></tbody></table></div></div>
    `;

    root.insertAdjacentHTML('beforeend', pageHtml);

    const purchaseSelect = document.getElementById('payable_purchase_id');
    const form = document.getElementById('payableForm');
    const rows = document.getElementById('payableRows');
    let purchaseList = [];

    setValue('payable_date', new Date().toISOString().slice(0, 10));

    async function refreshPayables() {
      const result = await supabase
        .from('v_purchase_payables')
        .select('*')
        .order('purchase_date', { ascending: false });

      if (result.error) throw result.error;

      purchaseList = result.data || [];

      purchaseSelect.innerHTML =
        '<option value="">Pilih Pembelian</option>' +
        purchaseList
          .map(
            p =>
              `<option value="${p.purchase_id}">${la.escape(p.purchase_code)} - sisa ${money(p.remaining_amount)}</option>`
          )
          .join('');

      await renderPayables();
    }

    async function updateSelectedPurchase() {
      const purchase = purchaseList.find(
        item => Number(item.purchase_id) === Number(purchaseSelect.value)
      );

      if (!purchase) {
        [
          'payable_supplier',
          'payable_total',
          'payable_paid',
          'payable_balance',
          'payable_amount'
        ].forEach(id => setValue(id, ''));
        return;
      }

      const total = Number(purchase.total_amount || 0);
      const paid = Number(purchase.paid_amount || 0);

      setValue('payable_total', String(total));
      setValue('payable_paid', String(paid));
      setValue('payable_supplier', purchase.supplier_name || '-');
      setValue('payable_balance', String(purchase.remaining_amount));
      setValue('payable_amount', String(purchase.remaining_amount));
    }

    async function renderPayables() {
      rows.innerHTML = purchaseList.length
        ? purchaseList
            .map(p => {
              const paid = Number(p.paid_amount || 0);
              const status = paid > 0 ? 'Sebagian' : 'Belum Dibayar';

              return `<tr><td>${la.escape(p.purchase_code)}</td><td>${la.escape(p.supplier_name || '-')}</td><td>${money(p.total_amount)}</td><td>${money(paid)}</td><td>${money(p.remaining_amount)}</td><td>${statusBadge(status)}</td></tr>`;
            })
            .join('')
        : '<tr><td colspan="6" class="empty">Tidak ada utang outstanding.</td></tr>';
    }

    purchaseSelect.addEventListener('change', () =>
      updateSelectedPurchase().catch(error =>
        la.toast(error.message, 'error')
      )
    );

    form.addEventListener('submit', async event => {
      event.preventDefault();

      const purchaseId = Number(purchaseSelect.value || 0);
      const amount = Number(getValue('payable_amount') || 0);
      const balance = Number(getValue('payable_balance') || 0);

      if (!purchaseId || !getValue('payable_date') || amount <= 0) {
        la.toast(
          'Pembelian, tanggal, dan jumlah pembayaran wajib diisi.',
          'error'
        );
        return;
      }

      if (amount > balance) {
        la.toast(
          'Pembayaran tidak boleh melebihi sisa utang.',
          'error'
        );
        return;
      }

      const result = await supabase.rpc('record_purchase_payment', {
        p_purchase_id: purchaseId,
        p_payment_date: getValue('payable_date'),
        p_amount: amount,
        p_payment_method: document.getElementById('payable_method').value,
        p_description: getValue('payable_description') || null
      });

      if (result.error) {
        la.toast(result.error.message, 'error');
        return;
      }

      la.toast('Pembayaran utang berhasil dicatat.');
      form.reset();
      setValue('payable_date', new Date().toISOString().slice(0, 10));
      await refreshPayables();
      await updateSelectedPurchase();
    });

    await refreshPayables();
  }

  async function initExpensePage() {
    const root = document.querySelector('.main') || document.body;
    const legacyPage = document.querySelector('.page');
    if (legacyPage) legacyPage.style.display = 'none';

    const pageHtml = `
      <div class="card" style="padding:18px; margin-bottom:18px;">
        <h3>Biaya Operasional</h3>
        <form id="expenseForm">
          <div class="form-grid">
            <div class="field"><label>Nomor Biaya</label><input id="expense_code" required></div>
            <div class="field"><label>Tanggal</label><input id="expense_date" type="date" required></div>
            <div class="field"><label>Kategori</label><select id="expense_category_id" required></select></div>
            <div class="field"><label>Jumlah</label><input id="expense_amount" type="number" min="1" required></div>
            <div class="field"><label>Metode Pembayaran</label><select id="expense_method"><option>Cash</option><option>Transfer</option><option>E-Wallet</option></select></div>
            <div class="field"><label>Status Pembayaran</label><select id="expense_status"><option value="Paid">Sudah Dibayar</option><option value="Unpaid">Belum Dibayar</option></select></div>
            <div class="field"><label>Penerima/Supplier</label><input id="expense_recipient"></div>
            <div class="field"><label>Keterangan</label><input id="expense_description"></div>
          </div>
          <div class="form-actions"><button type="submit" class="btn btn-primary">Simpan Biaya</button></div>
        </form>
      </div>
      <div class="card table-card"><div class="table-head"><strong>Riwayat Biaya Operasional</strong></div><div class="table-wrap"><table><thead><tr><th>Kode</th><th>Kategori</th><th>Tanggal</th><th>Jumlah</th><th>Status</th><th>Aksi</th></tr></thead><tbody id="expenseRows"></tbody></table></div></div>
    `;

    root.insertAdjacentHTML('beforeend', pageHtml);

    const form = document.getElementById('expenseForm');
    const categorySelect = document.getElementById('expense_category_id');
    const rows = document.getElementById('expenseRows');

    const categoriesResult = await supabase
      .from('expense_categories')
      .select('*')
      .order('category_name');

    if (categoriesResult.error) throw categoriesResult.error;

    categorySelect.innerHTML =
      '<option value="">Pilih Kategori</option>' +
      (categoriesResult.data || [])
        .map(
          category =>
            `<option value="${category.id}">${la.escape(category.category_name)}</option>`
        )
        .join('');

    setValue('expense_code', await nextCode('expense'));
    setValue('expense_date', new Date().toISOString().slice(0, 10));

    async function renderExpenses() {
      const result = await supabase
        .from('expenses')
        .select('*, expense_categories(category_name)')
        .order('id', { ascending: false });

      if (result.error) {
        la.toast(result.error.message, 'error');
        return;
      }

      rows.innerHTML = (result.data || []).length
        ? result.data
            .map(expense => `
        <tr>
          <td>${la.escape(expense.expense_code)}</td>
          <td>${la.escape(expense.expense_categories ? expense.expense_categories.category_name : '-')}</td>
          <td>${la.formatDate(expense.expense_date)}</td>
          <td>${money(expense.amount)}</td>
          <td>${statusBadge(expense.payment_status || 'Paid')}</td>
          <td>${expense.payment_status === 'Unpaid' ? `<button type="button" class="btn btn-light expense-pay" data-id="${expense.id}">Bayar</button>` : '-'}</td>
        </tr>
      `)
            .join('')
        : '<tr><td colspan="6" class="empty">Belum ada biaya operasional.</td></tr>';

      rows
        .querySelectorAll('.expense-pay')
        .forEach(button =>
          button.addEventListener('click', async () => {
            const expenseId = Number(button.dataset.id);
            const amount = Number(
              window.prompt('Jumlah pembayaran biaya:', '') || 0
            );

            if (!amount || amount <= 0) return;

            const expenseResult = await supabase
              .from('expenses')
              .select('amount')
              .eq('id', expenseId)
              .single();

            if (expenseResult.error) {
              la.toast(expenseResult.error.message, 'error');
              return;
            }

            const paymentsResult = await supabase
              .from('expense_payments')
              .select('amount')
              .eq('expense_id', expenseId);

            if (paymentsResult.error) {
              la.toast(paymentsResult.error.message, 'error');
              return;
            }

            const paid = (paymentsResult.data || []).reduce(
              (sum, payment) =>
                sum + Number(payment.amount || 0),
              0
            );

            const balance = Math.max(
              Number(expenseResult.data.amount || 0) - paid,
              0
            );

            if (amount > balance) {
              la.toast(
                'Pembayaran biaya tidak boleh melebihi sisa kewajiban.',
                'error'
              );
              return;
            }

            const result = await supabase.rpc(
              'record_expense_payment',
              {
                p_expense_id: expenseId,
                p_payment_date:
                  new Date().toISOString().slice(0, 10),
                p_amount: amount,
                p_payment_method: 'Cash',
                p_description: 'Pelunasan biaya operasional'
              }
            );

            if (result.error) {
              la.toast(result.error.message, 'error');
              return;
            }

            la.toast('Biaya operasional berhasil dibayar.');
            renderExpenses();
          })
        );
    }

    form.addEventListener('submit', async event => {
      event.preventDefault();

      const amount = Number(getValue('expense_amount') || 0);

      if (
        !getValue('expense_date') ||
        !categorySelect.value ||
        amount <= 0
      ) {
        la.toast(
          'Tanggal, kategori, dan jumlah biaya wajib diisi.',
          'error'
        );
        return;
      }

      const result = await supabase.from('expenses').insert({
        expense_code:
          getValue('expense_code') || await nextCode('expense'),
        category_id: Number(categorySelect.value),
        expense_date: getValue('expense_date'),
        amount,
        payment_method:
          document.getElementById('expense_method').value,
        payment_status:
          document.getElementById('expense_status').value,
        recipient: getValue('expense_recipient') || null,
        description: getValue('expense_description') || null
      });

      if (result.error) {
        la.toast(result.error.message, 'error');
        return;
      }

      la.toast('Biaya operasional berhasil disimpan.');
      form.reset();
      setValue('expense_code', await nextCode('expense'));
      setValue('expense_date', new Date().toISOString().slice(0, 10));
      renderExpenses();
    });

    renderExpenses();
  }

  async function initPaymentPage() {
    const root = document.querySelector('.main') || document.body;

    const pageHtml = `
      <div class="card" style="padding:18px; margin-bottom:18px;">
        <h3>Pembayaran Penyewaan</h3>
        <form id="paymentForm">
          <div class="form-grid">
            <div class="field"><label>Nomor Penyewaan</label><select id="rental_id" required></select></div>
            <div class="field"><label>Customer</label><input id="customer_name" readonly></div>
            <div class="field"><label>Kode Dress</label><input id="dress_code" readonly></div>
            <div class="field"><label>Nama Dress</label><input id="dress_name" readonly></div>
            <div class="field"><label>Ukuran</label><input id="dress_size" readonly></div>
            <div class="field"><label>Warna</label><input id="dress_color" readonly></div>
            <div class="field"><label>Warna</label><input id="dress_color" readonly></div>
            <div class="field"><label>Tanggal Sewa</label><input id="rental_date" readonly></div>
            <div class="field"><label>Tanggal Kembali</label><input id="return_due_date" readonly></div>
            <div class="field"><label>Total Tagihan</label><input id="total_amount" readonly></div>
            <div class="field"><label>Deposit</label><input id="deposit_amount" readonly></div>
            <div class="field"><label>Total Dibayar</label><input id="paid_amount" readonly></div>
            <div class="field"><label>Sisa Tagihan</label><input id="balance_amount" readonly></div>
            <div class="field"><label>Status</label><input id="payment_status" readonly></div>
            <div class="field"><label>Tanggal Pembayaran</label><input id="payment_date" type="date" required></div>
            <div class="field"><label>Jumlah Pembayaran</label><input id="amount" type="number" min="0" required></div>
            <div class="field"><label>Metode Pembayaran</label><select id="payment_method"><option value="Cash">Cash</option><option value="Transfer">Transfer</option><option value="E-Wallet">E-Wallet</option></select></div>
            <div class="field"><label>Tipe Pembayaran</label><select id="payment_type"><option value="PELUNASAN">Pelunasan</option><option value="DP">DP</option></select></div>
            <div class="field"><label>Keterangan</label><input id="description"></div>
          </div>
          <div class="form-actions"><button type="submit" class="btn btn-primary">Simpan Pembayaran</button></div>
        </form>
      </div>
      <div class="card table-card"><div class="table-head"><strong>Riwayat Pembayaran</strong></div><div class="table-wrap"><table><thead><tr><th>Kode</th><th>Rental</th><th>Tanggal</th><th>Jumlah</th><th>Metode</th></tr></thead><tbody id="paymentRows"></tbody></table></div></div>
    `;

    root.insertAdjacentHTML('beforeend', pageHtml);

    const rentalSelect = document.getElementById('rental_id');
    const form = document.getElementById('paymentForm');
    const paymentRows = document.getElementById('paymentRows');

    async function renderPaymentRows() {
      const { data, error } = await supabase
        .from('payments')
        .select('*')
        .order('id', { ascending: false });

      if (error) {
        la.toast(error.message, 'error');
        return;
      }

      paymentRows.innerHTML = (data || []).length
        ? (data || [])
            .map(p => `
        <tr><td>${la.escape(p.payment_code)}</td><td>${la.escape(p.rental_id)}</td><td>${la.formatDate(p.payment_date)}</td><td>${money(p.amount)}</td><td>${la.escape(p.payment_method || '-')}</td></tr>
      `)
            .join('')
        : '<tr><td colspan="5" class="empty">Belum ada data pembayaran.</td></tr>';
    }

    const rentals = await loadRentalOptions();

    rentalSelect.innerHTML =
      '<option value="">Pilih nomor penyewaan</option>' +
      rentals
        .map(r => `<option value="${r.id}">${r.rental_code}</option>`)
        .join('');

    rentalSelect.addEventListener('change', async () => {
      const rentalId = Number(rentalSelect.value);
      if (!rentalId) return;

      const { data, error } = await supabase
        .from('rentals')
        .select(
          '*, customers(name), rental_details(*, dresses(dress_code,name,color,rental_price), dress_variants(size,color))'
        )
        .eq('id', rentalId)
        .single();

      if (error) {
        la.toast(error.message, 'error');
        return;
      }

      const detail = (data.rental_details || [])[0] || {};
      const dress = detail.dresses || {};

      const paymentResult = await supabase
        .from('payments')
        .select('amount,payment_type')
        .eq('rental_id', rentalId);

      if (paymentResult.error) {
        la.toast(paymentResult.error.message, 'error');
        return;
      }

      const totalPaid = (paymentResult.data || []).reduce(
        (sum, payment) =>
          sum +
          (payment.payment_type === 'REFUND'
            ? -Number(payment.amount || 0)
            : ['DP', 'PELUNASAN'].includes(payment.payment_type)
              ? Number(payment.amount || 0)
              : 0),
        0
      );

      const total = Number(
        data.total_rental ?? data.total_amount ?? 0
      );
      const balance = total - totalPaid;

      setValue(
        'customer_name',
        data.customers ? data.customers.name : ''
      );
      setValue('dress_code', dress.dress_code || '');
      setValue('dress_name', dress.name || '');
      setValue('dress_size', detail.dress_variants?.size || '');
      setValue('dress_color', detail.dress_variants?.color || '');
      setValue('rental_date', data.rental_date || '');
      setValue('return_due_date', data.return_due_date || '');
      setValue('total_amount', String(total));
      setValue('deposit_amount', String(data.deposit_amount || 0));
      setValue('paid_amount', String(totalPaid));
      setValue('balance_amount', String(balance));
      setValue('payment_status', computeStatus(total, totalPaid));
      setValue('amount', String(Math.max(balance, 0)));
      setValue(
        'payment_date',
        new Date().toISOString().slice(0, 10)
      );
    });

    form.addEventListener('submit', async (e) => {
      e.preventDefault();

      const rentalId = Number(rentalSelect.value);
      const total = Number(getValue('total_amount') || 0);
      const totalPaid = Number(getValue('paid_amount') || 0);
      const paymentAmount = Number(getValue('amount') || 0);
      const paymentDate = getValue('payment_date');

      if (!rentalId || !paymentDate || paymentAmount <= 0) {
        la.toast(
          'Tanggal dan jumlah pembayaran wajib diisi.',
          'error'
        );
        return;
      }

      const rentalStatusResult = await supabase
        .from('rentals')
        .select('rental_status, status')
        .eq('id', rentalId)
        .single();

      if (rentalStatusResult.error) {
        la.toast(rentalStatusResult.error.message, 'error');
        return;
      }

      if (
        (
          rentalStatusResult.data.rental_status ||
          rentalStatusResult.data.status
        ) === 'Cancelled'
      ) {
        la.toast(
          'Rental yang dibatalkan tidak dapat menerima pembayaran baru.',
          'error'
        );
        return;
      }

      const remaining = total - totalPaid;

      if (paymentAmount > remaining) {
        la.toast(
          'Jumlah pembayaran tidak boleh melebihi sisa tagihan.',
          'error'
        );
        return;
      }

      const { error } = await supabase.rpc(
        'record_rental_payment',
        {
          p_rental_id: rentalId,
          p_payment_date: paymentDate,
          p_amount: paymentAmount,
          p_payment_method:
            document.getElementById('payment_method').value,
          p_payment_type:
            document.getElementById('payment_type').value,
          p_notes: getValue('description')
        }
      );

      if (error) {
        la.toast(error.message, 'error');
        return;
      }

      la.toast('Pembayaran berhasil dicatat.');
      rentalSelect.value = '';
      setValue('customer_name', '');
      setValue('dress_code', '');
      setValue('dress_name', '');
      setValue('dress_size', '');
      setValue('dress_color', '');
      setValue('rental_date', '');
      setValue('return_due_date', '');
      setValue('total_amount', '');
      setValue('deposit_amount', '');
      setValue('paid_amount', '');
      setValue('balance_amount', '');
      setValue('payment_status', '');
      setValue('amount', '');
      form.reset();
      renderPaymentRows();
    });

    renderPaymentRows();
  }

    async function initReturnPage() {
    const root = document.querySelector('.main') || document.body;

    const pageHtml = `
      <div class="card" style="padding:18px; margin-bottom:18px;">
        <h3>Pengembalian Dress</h3>
        <form id="returnForm">
          <div class="form-grid">
            <div class="field"><label>Nomor Penyewaan</label><select id="rental_id" required></select></div>
            <div class="field"><label>Customer</label><input id="customer_name" readonly></div>
            <div class="field"><label>Kode Dress</label><input id="dress_code" readonly></div>
            <div class="field"><label>Nama Dress</label><input id="dress_name" readonly></div>
            <div class="field"><label>Ukuran</label><input id="return_dress_size" readonly></div>
            <div class="field"><label>Warna</label><input id="return_dress_color" readonly></div>
            <div class="field"><label>Unit Fisik</label><input id="return_dress_unit" readonly></div>
            <div class="field"><label>Tanggal Sewa</label><input id="rental_date" readonly></div>
            <div class="field"><label>Jatuh Tempo</label><input id="return_due_date" readonly></div>
            <div class="field"><label>Total Sewa</label><input id="return_total_amount" readonly></div>
            <div class="field"><label>Deposit Awal</label><input id="return_deposit_amount" readonly></div>
            <div class="field"><label>Status Pembayaran</label><input id="return_payment_status" readonly></div>
            <div class="field"><label>Tanggal Aktual Pengembalian</label><input id="return_date" type="date" required></div>
            <div class="field"><label>Kondisi Dress</label><select id="condition"><option value="Baik">Baik</option><option value="Kotor">Kotor</option><option value="Rusak Ringan">Rusak Ringan</option><option value="Rusak Berat">Rusak Berat</option><option value="Hilang">Hilang</option></select></div>
            <div class="field"><label>Tarif Denda per Hari</label><input id="late_rate" type="number" min="0" value="50000"></div>
            <div class="field"><label>Hari Keterlambatan</label><input id="late_days" type="number" readonly value="0"></div>
            <div class="field"><label>Denda Keterlambatan</label><input id="late_penalty" type="number" readonly value="0"></div>
            <div class="field"><label>Biaya Kerusakan</label><input id="damage_amount" type="number" min="0" value="0"></div>
            <div class="field"><label>Total Denda</label><input id="total_penalty" type="number" readonly value="0"></div>
            <div class="field"><label>Dibayar Saat Pengembalian</label><input id="penalty_payment_amount" type="number" min="0" value="0"></div>
            <div class="field"><label>Metode Pembayaran Denda</label><select id="penalty_payment_method"><option>Cash</option><option>Transfer</option><option>E-Wallet</option></select></div>
            <div class="field"><label>Catatan</label><input id="notes"></div>
          </div>
          <div class="deposit-summary" id="returnDepositSummary" hidden></div>
          <div class="form-actions"><button type="submit" class="btn btn-primary">Simpan Pengembalian</button></div>
        </form>
      </div>
    `;

    root.insertAdjacentHTML('beforeend', pageHtml);

    const rentalSelect = document.getElementById('rental_id');
    const form = document.getElementById('returnForm');
    let currentDeposit = 0;

    const rentalResult = await supabase
      .from('rentals')
      .select('*, customers(name), returns(id)')
      .order('id', { ascending: false });

    if (rentalResult.error) throw rentalResult.error;

    const rentals = (rentalResult.data || []).filter(
      r =>
        !(r.returns || []).length &&
        !['Cancelled', 'Completed', 'Returned'].includes(
          r.rental_status || r.status
        )
    );

    rentalSelect.innerHTML =
      '<option value="">Pilih nomor penyewaan</option>' +
      rentals
        .map(r => `<option value="${r.id}">${r.rental_code}</option>`)
        .join('');

    rentalSelect.addEventListener('change', async () => {
      const rentalId = Number(rentalSelect.value);
      if (!rentalId) return;

      const { data, error } = await supabase
        .from('rentals')
        .select(
          '*, customers(name), rental_details(*, dresses(dress_code,name), dress_variants(size,color), dress_units(unit_code,status))'
        )
        .eq('id', rentalId)
        .single();

      if (error) {
        la.toast(error.message, 'error');
        return;
      }

      const detail = (data.rental_details || [])[0] || {};
      const dress = detail.dresses || {};

      setValue(
        'customer_name',
        data.customers ? data.customers.name : ''
      );
      setValue('dress_code', dress.dress_code || '');
      setValue('dress_name', dress.name || '');
      setValue('return_dress_size', detail.dress_variants?.size || '');
      setValue('return_dress_color', detail.dress_variants?.color || '');
      setValue(
        'return_dress_unit',
        `${detail.dress_units?.unit_code || ''} / ${detail.dress_units?.status || ''}`
      );
      setValue('rental_date', data.rental_date || '');
      setValue('return_due_date', data.return_due_date || '');
      setValue(
        'return_total_amount',
        data.total_rental ?? data.total_amount ?? 0
      );

      currentDeposit = Number(data.deposit_received_amount || 0);

      setValue('return_deposit_amount', currentDeposit);
      setValue(
        'return_payment_status',
        data.payment_status || data.status || ''
      );
      setValue(
        'return_date',
        new Date().toISOString().slice(0, 10)
      );

      document.getElementById('returnDepositSummary').hidden = false;
      updateReturnTotals();
    });

    function updateReturnTotals() {
      const actual = getValue('return_date');
      const due = getValue('return_due_date');

      const lateDays =
        actual && due
          ? Math.max(
              0,
              Math.ceil(
                (new Date(actual) - new Date(due)) / 86400000
              )
            )
          : 0;

      const lateAmount =
        lateDays * Number(getValue('late_rate') || 0);

      const total =
        lateAmount + Number(getValue('damage_amount') || 0);

      setValue('late_days', lateDays);
      setValue('late_penalty', lateAmount);
      setValue('total_penalty', total);

      const depositUsed = Math.min(currentDeposit, total);
      const depositRefunded = Math.max(currentDeposit - total, 0);
      const customerDue = Math.max(total - depositUsed, 0);
      const paymentInput =
        document.getElementById('penalty_payment_amount');

      paymentInput.max = String(customerDue);

      if (Number(paymentInput.value || 0) > customerDue) {
        paymentInput.value = String(customerDue);
      }

      const receivable = Math.max(
        customerDue - Number(paymentInput.value || 0),
        0
      );

      document.getElementById('returnDepositSummary').innerHTML = `
        <h4>Ringkasan Deposit</h4>
        <div>Deposit Awal<strong>${money(currentDeposit)}</strong></div>
        <div>Denda Keterlambatan<strong>${money(lateAmount)}</strong></div>
        <div>Biaya Kerusakan<strong>${money(Number(getValue('damage_amount') || 0))}</strong></div>
        <div>Total Denda/Kerusakan<strong>${money(total)}</strong></div>
        <div>Deposit Digunakan<strong>${money(depositUsed)}</strong></div>
        <div>Deposit Dikembalikan<strong>${money(depositRefunded)}</strong></div>
        <div>Dibayar Saat Pengembalian<strong>${money(Number(paymentInput.value || 0))}</strong></div>
        <div>Sisa Tagihan<strong>${money(receivable)}</strong></div>`;
    }

    [
      'return_date',
      'late_rate',
      'damage_amount',
      'penalty_payment_amount'
    ].forEach(id =>
      document
        .getElementById(id)
        .addEventListener('input', updateReturnTotals)
    );

    form.addEventListener('submit', async (e) => {
      e.preventDefault();

      const rentalId = Number(rentalSelect.value);
      const actualDate = getValue('return_date');
      const dueDate = getValue('return_due_date');
      const condition = document.getElementById('condition').value;
      const lateRate = Number(getValue('late_rate') || 0);
      const damageAmount = Number(getValue('damage_amount') || 0);
      const paymentAmount = Number(
        getValue('penalty_payment_amount') || 0
      );

      if (!rentalId || !actualDate || !dueDate) {
        la.toast(
          'Nomor penyewaan dan tanggal pengembalian wajib diisi.',
          'error'
        );
        return;
      }

      const { data: processed, error: returnError } =
        await supabase.rpc('process_return_transaction', {
          p_rental_id: rentalId,
          p_return_date: actualDate,
          p_condition: condition,
          p_notes: getValue('notes') || null,
          p_late_rate: lateRate,
          p_damage_amount: damageAmount,
          p_payment_amount: paymentAmount,
          p_payment_method: getValue('penalty_payment_method')
        });

      if (returnError) {
        la.handleSupabaseError(returnError, {
          module: 'Return',
          operation: 'PROCESS'
        });
        la.toast(returnError.message, 'error');
        return;
      }

      la.toast('Pengembalian dress berhasil dicatat.');
      form.reset();
      rentalSelect.value = '';
      currentDeposit = 0;
      document.getElementById('returnDepositSummary').hidden = true;
      setValue('late_rate', 50000);
      setValue('late_days', 0);
      setValue('late_penalty', 0);
      setValue('total_penalty', 0);
      setValue('penalty_payment_amount', 0);
    });
  }

  async function initPenaltyPage() {
    const rows = document.getElementById('tbody');
    if (!rows) return;

    const header = rows.closest('table')?.querySelector('thead tr');

    if (header) {
      header.innerHTML =
        '<th>Rental</th><th>Jenis</th><th>Total</th><th>Terbayar</th><th>Sisa</th><th>Keterangan</th><th>Aksi</th>';
    }

    const { data, error } = await supabase
      .from('penalties')
      .select('*, returns(rental_id,deposit_used,customer_receivable)')
      .order('id', { ascending: false });

    if (error) {
      la.toast(error.message, 'error');
      return;
    }

    const paymentResult = await supabase
      .from('penalty_payments')
      .select('penalty_id, amount');

    if (paymentResult.error) {
      la.toast(paymentResult.error.message, 'error');
      return;
    }

    const paidByPenalty = {};

    (paymentResult.data || []).forEach(payment => {
      paidByPenalty[payment.penalty_id] =
        (paidByPenalty[payment.penalty_id] || 0) +
        Number(payment.amount || 0);
    });

    rows.innerHTML = (data || []).length
      ? (data || [])
          .map(p => {
            const paid = paidByPenalty[p.id] || 0;
            const depositUsed = Number(p.returns?.deposit_used || 0);
            const balance = Math.max(
              Number(p.amount || 0) - depositUsed - paid,
              0
            );

            return `<tr><td>${la.escape(p.returns ? p.returns.rental_id : '-')}</td><td>${la.escape(p.penalty_type || '-')}</td><td>${money(p.amount)}</td><td>${money(depositUsed + paid)}</td><td>${money(balance)}</td><td>${la.escape(p.description || '-')}</td><td>${balance > 0 ? `<button type="button" class="btn btn-light penalty-pay" data-id="${p.id}" data-balance="${balance}">Bayar</button>` : statusBadge('Lunas')}</td></tr>`;
          })
          .join('')
      : '<tr><td colspan="7" class="empty">Belum ada denda.</td></tr>';

    rows
      .querySelectorAll('.penalty-pay')
      .forEach(button =>
        button.addEventListener('click', async () => {
          const amount = Number(
            window.prompt(
              `Jumlah pembayaran (maksimal ${button.dataset.balance}):`,
              button.dataset.balance
            ) || 0
          );

          if (
            !amount ||
            amount <= 0 ||
            amount > Number(button.dataset.balance)
          ) {
            la.toast(
              'Jumlah pembayaran denda tidak valid.',
              'error'
            );
            return;
          }

          const result = await supabase.rpc(
            'record_penalty_payment',
            {
              p_penalty_id: Number(button.dataset.id),
              p_payment_date:
                new Date().toISOString().slice(0, 10),
              p_amount: amount,
              p_payment_method: 'Cash',
              p_description: 'Pembayaran denda/kerusakan'
            }
          );

          if (result.error) {
            la.toast(result.error.message, 'error');
            return;
          }

          la.toast('Pembayaran denda berhasil dicatat.');
          initPenaltyPage();
        })
      );
  }

  async function initDashboardPage() {
    const revenueEl = document.getElementById('rev');
    const expenseEl = document.getElementById('exp');
    const netEl = document.getElementById('profit');
    const payEl = document.getElementById('ar');
    const availEl = document.getElementById('avail');
    const rentedEl = document.getElementById('rented');
    const statusEl = document.getElementById('status');

    if (!revenueEl && !expenseEl && !netEl) return;

    const [
      rentalsRes,
      expensesRes,
      dressesRes,
      paymentsRes
    ] = await Promise.all([
      supabase
        .from('rentals')
        .select('id, total_amount, total_rental'),
      supabase
        .from('expenses')
        .select('amount'),
      supabase
        .from('v_dress_inventory')
        .select(
          'status,quantity,available_quantity,rented_quantity,laundry_quantity,repair_quantity,not_available_quantity,unclassified_quantity'
        ),
      supabase
        .from('payments')
        .select('rental_id, amount, payment_type')
    ]);

    const revenue = (rentalsRes.data || []).reduce(
      (sum, r) => sum + Number(r.total_amount || 0),
      0
    );

    const expense = (expensesRes.data || []).reduce(
      (sum, e) => sum + Number(e.amount || 0),
      0
    );

    const paidByRental = {};

    (paymentsRes.data || []).forEach(payment => {
      const paid =
        payment.payment_type === 'REFUND'
          ? -Number(payment.amount || 0)
          : ['DP', 'PELUNASAN'].includes(payment.payment_type)
            ? Number(payment.amount || 0)
            : 0;

      paidByRental[payment.rental_id] =
        (paidByRental[payment.rental_id] || 0) + paid;
    });

    const receivable = (rentalsRes.data || []).reduce(
      (sum, rental) =>
        sum +
        Math.max(
          Number(
            rental.total_rental ?? rental.total_amount ?? 0
          ) - (paidByRental[rental.id] || 0),
          0
        ),
      0
    );

    const dresses = dressesRes.data || [];

    const dressCounts = dresses.reduce(
      (counts, variant) => {
        counts.Available += Number(
          variant.available_quantity || 0
        );
        counts.Rented += Number(variant.rented_quantity || 0);
        counts.Laundry += Number(variant.laundry_quantity || 0);
        counts.Repair += Number(variant.repair_quantity || 0);
        counts['Not Available'] += Number(
          variant.not_available_quantity || 0
        );
        counts.Unclassified += Number(
          variant.unclassified_quantity || 0
        );
        return counts;
      },
      {
        Available: 0,
        Rented: 0,
        Laundry: 0,
        Repair: 0,
        'Not Available': 0,
        Unclassified: 0
      }
    );

    if (revenueEl) revenueEl.textContent = money(revenue);
    if (expenseEl) expenseEl.textContent = money(expense);
    if (netEl) netEl.textContent = money(revenue - expense);
    if (payEl) payEl.textContent = money(receivable);
    if (availEl) {
      availEl.textContent = String(dressCounts.Available || 0);
    }
    if (rentedEl) {
      rentedEl.textContent = String(dressCounts.Rented || 0);
    }

    if (statusEl) {
      statusEl.innerHTML = Object.entries(dressCounts)
        .map(
          ([key, val]) =>
            `<div style="display:flex;justify-content:space-between;padding:6px 0;border-bottom:1px solid #eee"><span>${key}</span><strong>${val}</strong></div>`
        )
        .join('');
    }
  }

    async function initLaporanPage() {
    const legacyPage = document.querySelector('.page');
    if (legacyPage) legacyPage.style.display = 'none';
    const root = document.querySelector('.main') || document.body;

    root.insertAdjacentHTML('beforeend', `
      <section class="page" id="accountingReportPage">
        <div class="page-title"><div><h2>Laporan Keuangan</h2><p>Seluruh angka berasal dari jurnal umum dan journal details.</p></div><div class="form-actions"><button class="btn btn-light" id="pdfIncome">PDF Laba Rugi</button><button class="btn btn-light" id="pdfPackage">PDF Paket Lengkap</button></div></div>
        <div class="card" style="padding:18px;margin-bottom:18px"><div class="form-grid"><div class="field"><label>Dari Tanggal</label><input id="reportFrom" type="date"></div><div class="field"><label>Sampai Tanggal</label><input id="reportTo" type="date"></div><div class="field"><label>Preset</label><select id="reportPreset"><option value="custom">Custom</option><option value="today">Hari Ini</option><option value="month">Bulan Ini</option><option value="lastMonth">Bulan Lalu</option><option value="year">Tahun Ini</option><option value="lastYear">Tahun Lalu</option></select></div><div class="field"><label>&nbsp;</label><button class="btn btn-primary" id="refreshReports">Tampilkan Laporan</button></div></div></div>
        <div id="reportWarning"></div>
        <div class="grid grid-3"><div class="card"><div class="muted">Total Pendapatan</div><h2 id="reportRevenue">Rp0</h2></div><div class="card"><div class="muted">Total Beban</div><h2 id="reportExpense">Rp0</h2></div><div class="card"><div class="muted">Laba / (Rugi)</div><h2 id="reportProfit">Rp0</h2></div><div class="card"><div class="muted">Setoran Modal</div><h2 id="reportCapital">Rp0</h2></div><div class="card"><div class="muted">Kas dari Pendanaan</div><h2 id="reportFinancingCash">Rp0</h2></div></div>
        <div class="grid grid-2" style="margin-top:18px"><div class="card"><h3>Laporan Laba Rugi</h3><div class="table-wrap"><table><tbody id="incomeRows"></tbody></table></div></div><div class="card"><h3>Laporan Posisi Keuangan</h3><div class="table-wrap"><table><tbody id="balanceRows"></tbody></table></div></div></div>
        <div class="card" style="margin-top:18px"><h3>Laporan Perubahan Ekuitas</h3><div class="table-wrap"><table><tbody id="equityRows"></tbody></table></div></div>
        <div class="card" style="margin-top:18px"><h3>Laporan Arus Kas Langsung</h3><div class="table-wrap"><table><tbody id="cashRows"></tbody></table></div></div>
        <div class="card" style="margin-top:18px"><h3>Rekonsiliasi Accounting</h3><div id="reconciliationRows"></div></div>
      </section>
    `);

    const fromInput = document.getElementById('reportFrom');
    const toInput = document.getElementById('reportTo');
    const today = new Date();
    const iso = date => {
      const year = date.getFullYear();
      const month = String(date.getMonth() + 1).padStart(2, '0');
      const day = String(date.getDate()).padStart(2, '0');
      return `${year}-${month}-${day}`;
    };
    const firstYear = new Date(today.getFullYear(), 0, 1);
    fromInput.value = iso(firstYear);
    toInput.value = iso(today);
    let currentReport = null;

    function setPreset(value) {
      const now = new Date();
      let from = new Date(now);
      let to = new Date(now);

      if (value === 'month') {
        from = new Date(now.getFullYear(), now.getMonth(), 1);
      }

      if (value === 'lastMonth') {
        from = new Date(now.getFullYear(), now.getMonth() - 1, 1);
        to = new Date(now.getFullYear(), now.getMonth(), 0);
      }

      if (value === 'year') {
        from = new Date(now.getFullYear(), 0, 1);
      }

      if (value === 'lastYear') {
        from = new Date(now.getFullYear() - 1, 0, 1);
        to = new Date(now.getFullYear() - 1, 11, 31);
      }

      if (value === 'today') {
        from = new Date(
          now.getFullYear(),
          now.getMonth(),
          now.getDate()
        );
      }

      fromInput.value = iso(from);
      toInput.value = iso(to);
    }

    document
      .getElementById('reportPreset')
      .addEventListener('change', event =>
        setPreset(event.target.value)
      );

    async function loadReport() {
      const from = fromInput.value;
      const to = toInput.value;

      if (!from || !to || from > to) {
        la.toast('Periode laporan tidak valid.', 'error');
        return;
      }

      const result = await supabase
        .from('v_general_ledger')
        .select('*')
        .lte('journal_date', to)
        .order('journal_date')
        .order('journal_number');

      if (result.error) {
        la.toast(result.error.message, 'error');
        return;
      }

      const allLines = result.data || [];

      const periodLines = allLines.filter(
        line =>
          line.journal_date >= from &&
          line.journal_date <= to
      );

      const periodTotals = {};
      const closingTotals = {};
      const accountMeta = {};

      allLines.forEach(line => {
        accountMeta[line.account_code] = line;

        const target =
          line.journal_date >= from &&
          line.journal_date <= to
            ? periodTotals
            : null;

        const signed = Number(line.signed_amount || 0);

        closingTotals[line.account_code] =
          (closingTotals[line.account_code] || 0) + signed;

        if (target) {
          target[line.account_code] =
            (target[line.account_code] || 0) + signed;
        }
      });

      const sumType = (source, type) =>
        Object.keys(source).reduce(
          (sum, code) =>
            sum +
            (
              accountMeta[code] &&
              accountMeta[code].account_type === type
                ? source[code]
                : 0
            ),
          0
        );

      const revenue = sumType(periodTotals, 'Revenue');
      const expense = sumType(periodTotals, 'Expense');
      const profit = revenue - expense;
      const assets = sumType(closingTotals, 'Asset');
      const liabilities = sumType(closingTotals, 'Liability');
      const equity = sumType(closingTotals, 'Equity');
      const closingRevenue = sumType(closingTotals, 'Revenue');
      const closingExpense = sumType(closingTotals, 'Expense');

      const liabilitiesEquity =
        liabilities +
        equity +
        closingRevenue -
        closingExpense;

      const debit = periodLines.reduce(
        (sum, line) => sum + Number(line.debit || 0),
        0
      );

      const credit = periodLines.reduce(
        (sum, line) => sum + Number(line.credit || 0),
        0
      );

      const cashAccountCodes = ['101', '1120'];
      const cashLines = periodLines.filter(line =>
        cashAccountCodes.includes(line.account_code)
      );
      const financingLines = cashLines.filter(
        line => line.reference_type === 'capital'
      );
      const cashIn = cashLines.reduce(
        (sum, line) => sum + Number(line.debit || 0),
        0
      );
      const cashOut = cashLines.reduce(
        (sum, line) => sum + Number(line.credit || 0),
        0
      );
      const financingCashIn = financingLines.reduce(
        (sum, line) => sum + Number(line.debit || 0),
        0
      );
      const financingCashOut = financingLines.reduce(
        (sum, line) => sum + Number(line.credit || 0),
        0
      );
      const operatingCashIn = cashIn - financingCashIn;
      const operatingCashOut = cashOut - financingCashOut;
      const operatingCashNet = operatingCashIn - operatingCashOut;
      const financingCash = financingCashIn - financingCashOut;

      const capitalContribution = periodLines
        .filter(
          line =>
            line.reference_type === 'capital' &&
            ['101', '1120'].includes(line.account_code) &&
            Number(line.debit || 0) > 0
        )
        .reduce(
          (sum, line) => sum + Number(line.debit || 0),
          0
        );

      const openingCapital = allLines
        .filter(
          line =>
            line.account_code === '301' &&
            line.journal_date < from
        )
        .reduce(
          (sum, line) =>
            sum + Number(line.signed_amount || 0),
          0
        );

      const endingCapital = closingTotals['301'] || 0;
      const openingEquityAccounts = allLines
        .filter(line =>
          line.journal_date < from &&
          accountMeta[line.account_code]?.account_type === 'Equity'
        )
        .reduce((sum, line) => sum + Number(line.signed_amount || 0), 0);
      const openingRetainedEarnings = allLines
        .filter(line =>
          line.journal_date < from &&
          ['Revenue', 'Expense'].includes(accountMeta[line.account_code]?.account_type)
        )
        .reduce((sum, line) => sum + Number(line.signed_amount || 0), 0);
      const openingEquity = openingEquityAccounts + openingRetainedEarnings;
      const endingEquity = equity + closingRevenue - closingExpense;
      const otherEquityMovements =
        endingEquity - openingEquity - financingCash - profit;

      const openingCash = allLines
        .filter(line =>
          cashAccountCodes.includes(line.account_code) &&
          line.journal_date < from
        )
        .reduce(
          (sum, line) =>
            sum + Number(line.signed_amount || 0),
          0
        );

      const cashBalance = cashAccountCodes.reduce(
        (sum, code) => sum + Number(closingTotals[code] || 0),
        0
      );
      const cashFlowBalance =
        openingCash + operatingCashNet + financingCash;

      const reconciliation = {
        debit,
        credit,
        assets,
        liabilitiesEquity,
        difference: assets - liabilitiesEquity,
        cashBalance,
        openingCash,
        cashFlowBalance
      };

      currentReport = {
        from,
        to,
        periodLines,
        periodTotals,
        closingTotals,
        revenue,
        expense,
        profit,
        assets,
        liabilities,
        equity,
        liabilitiesEquity,
        cashIn,
        cashOut,
        operatingCashIn,
        operatingCashOut,
        operatingCashNet,
        financingCashIn,
        financingCashOut,
        capitalContribution,
        financingCash,
        cashBalance,
        openingCapital,
        endingCapital,
        openingEquity,
        endingEquity,
        otherEquityMovements,
        reconciliation,
        accountMeta
      };

      document.getElementById('reportRevenue').textContent =
        money(revenue);

      document.getElementById('reportExpense').textContent =
        money(expense);

      document.getElementById('reportProfit').textContent =
        money(profit);

      document.getElementById('reportCapital').textContent =
        money(capitalContribution);

      document.getElementById('reportFinancingCash').textContent =
        money(financingCash);

      const incomeRows = document.getElementById('incomeRows');

      incomeRows.innerHTML =
        `<tr><th colspan="2">PENDAPATAN</th></tr>${Object.keys(periodTotals).filter(code => accountMeta[code]?.account_type === 'Revenue').map(code => `<tr><td>${la.escape(accountMeta[code].account_name)}</td><td class="text-right">${money(periodTotals[code])}</td></tr>`).join('')}<tr><th>Total Pendapatan</th><th class="text-right">${money(revenue)}</th></tr><tr><th colspan="2">BEBAN</th></tr>${Object.keys(periodTotals).filter(code => accountMeta[code]?.account_type === 'Expense').map(code => `<tr><td>${la.escape(accountMeta[code].account_name)}</td><td class="text-right">${money(periodTotals[code])}</td></tr>`).join('')}<tr><th>Total Beban</th><th class="text-right">${money(expense)}</th></tr><tr><th>Laba / (Rugi) Bersih</th><th class="text-right">${money(profit)}</th></tr>`;

      document.getElementById('balanceRows').innerHTML =
        `<tr><th colspan="2">ASET</th></tr>${Object.keys(closingTotals).filter(code => accountMeta[code]?.account_type === 'Asset').map(code => `<tr><td>${la.escape(accountMeta[code].account_name)}</td><td class="text-right">${money(closingTotals[code])}</td></tr>`).join('')}<tr><th>Total Aset</th><th class="text-right">${money(assets)}</th></tr><tr><th colspan="2">LIABILITAS & EKUITAS</th></tr>${Object.keys(closingTotals).filter(code => ['Liability','Equity'].includes(accountMeta[code]?.account_type)).map(code => `<tr><td>${la.escape(accountMeta[code].account_name)}</td><td class="text-right">${money(closingTotals[code])}</td></tr>`).join('')}<tr><td>Laba / (Rugi) Berjalan</td><td class="text-right">${money(closingRevenue - closingExpense)}</td></tr><tr><th>Total Liabilitas + Ekuitas</th><th class="text-right">${money(liabilitiesEquity)}</th></tr>`;

      document.getElementById('equityRows').innerHTML =
        `<tr><td>Saldo ekuitas awal periode</td><td class="text-right">${money(openingEquity)}</td></tr><tr><td>Setoran modal bersih</td><td class="text-right">${money(financingCash)}</td></tr><tr><td>Laba / (Rugi) periode berjalan</td><td class="text-right">${money(profit)}</td></tr><tr><td>Penyesuaian / penarikan modal lainnya</td><td class="text-right">${money(otherEquityMovements)}</td></tr><tr><th>Saldo ekuitas akhir periode</th><th class="text-right">${money(endingEquity)}</th></tr>`;

      document.getElementById('cashRows').innerHTML =
        `<tr><td>Saldo kas dan bank awal periode</td><td class="text-right">${money(openingCash)}</td></tr><tr><td>Penerimaan aktivitas operasi</td><td class="text-right">${money(operatingCashIn)}</td></tr><tr><td>Pengeluaran aktivitas operasi</td><td class="text-right">(${money(operatingCashOut)})</td></tr><tr><td>Arus kas bersih aktivitas operasi</td><td class="text-right">${money(operatingCashNet)}</td></tr><tr><td>Arus kas bersih aktivitas pendanaan</td><td class="text-right">${money(financingCash)}</td></tr><tr><th>Kenaikan / (Penurunan) Kas dan Bank</th><th class="text-right">${money(operatingCashNet + financingCash)}</th></tr><tr><th>Saldo kas dan bank akhir periode</th><th class="text-right">${money(cashFlowBalance)}</th></tr><tr><td>Saldo akun Kas dan Bank sampai ${la.formatDate(to)}</td><td class="text-right">${money(cashBalance)}</td></tr>`;

      const balanced =
        Math.abs(debit - credit) < 0.01 &&
        Math.abs(assets - liabilitiesEquity) < 0.01 &&
        Math.abs(cashFlowBalance - cashBalance) < 0.01;

      document.getElementById('reportWarning').innerHTML =
        balanced
          ? '<div class="badge success" style="padding:12px">✓ DATA AKUNTANSI SEIMBANG</div>'
          : `<div class="badge danger" style="padding:12px">⚠ TERDAPAT SELISIH. Debit: ${money(debit)} | Kredit: ${money(credit)} | Selisih Neraca: ${money(assets - liabilitiesEquity)}</div>`;

      document.getElementById('reconciliationRows').innerHTML =
        `<p>Total Debit Jurnal: <strong>${money(debit)}</strong></p><p>Total Kredit Jurnal: <strong>${money(credit)}</strong></p><p>Total Aset: <strong>${money(assets)}</strong></p><p>Liabilitas + Ekuitas: <strong>${money(liabilitiesEquity)}</strong></p><p>Saldo kas akhir arus kas: <strong>${money(cashFlowBalance)}</strong></p><p>Saldo Kas dan Bank: <strong>${money(cashBalance)}</strong></p>`;
    }

    async function ensurePdf() {
      if (window.jspdf?.jsPDF) return window.jspdf.jsPDF;

      await new Promise((resolve, reject) => {
        const script = document.createElement('script');
        script.src =
          'https://cdnjs.cloudflare.com/ajax/libs/jspdf/2.5.1/jspdf.umd.min.js';
        script.onload = resolve;
        script.onerror = reject;
        document.head.appendChild(script);
      });

      return window.jspdf.jsPDF;
    }

    async function exportPdf(kind) {
      if (!currentReport) await loadReport();
      if (!currentReport) return;

      if (
        Math.abs(
          currentReport.reconciliation.debit -
          currentReport.reconciliation.credit
        ) >= 0.01 ||
        Math.abs(currentReport.reconciliation.difference) >= 0.01 ||
        Math.abs(
          currentReport.reconciliation.cashFlowBalance -
          currentReport.reconciliation.cashBalance
        ) >= 0.01
      ) {
        la.toast(
          'Laporan belum dapat dicetak karena accounting tidak balance atau kas tidak tere konsiliasi.',
          'error'
        );
        return;
      }

      const [JsPDF, businessResult] = await Promise.all([
        ensurePdf(),
        supabase
          .from('business_settings')
          .select('business_name, address, phone, email, website')
          .eq('id', true)
          .maybeSingle()
      ]);
      const company = businessResult.data || {};
      const report = currentReport;
      const doc = new JsPDF({ orientation: 'portrait', unit: 'mm', format: 'a4' });
      const pageWidth = doc.internal.pageSize.getWidth();
      const pageHeight = doc.internal.pageSize.getHeight();
      const left = 16;
      const right = pageWidth - 16;
      const companyName = company.business_name || 'LAVE DRESS RENTAL';
      const companyDetails = [
        company.address,
        [company.phone, company.email].filter(Boolean).join(' | '),
        company.website
      ].filter(Boolean).join(' | ');
      const formatAmount = value =>
        Number(value || 0) < 0
          ? `(${money(Math.abs(Number(value)))})`
          : money(value);

      doc.setProperties({
        title: kind === 'income' ? 'Laporan Laba Rugi' : 'Paket Laporan Keuangan',
        subject: `Laporan keuangan ${report.from} sampai ${report.to}`,
        author: companyName,
        creator: 'LAVE Dress Rental & Accounting'
      });

      const drawHeader = title => {
        doc.setFillColor(24, 125, 114);
        doc.rect(0, 0, pageWidth, 3, 'F');
        doc.setFont('helvetica', 'bold');
        doc.setFontSize(12);
        doc.setTextColor(28, 48, 47);
        doc.text(companyName, left, 15);

        if (companyDetails) {
          doc.setFont('helvetica', 'normal');
          doc.setFontSize(7.5);
          doc.setTextColor(101, 119, 114);
          doc.text(doc.splitTextToSize(companyDetails, 105).slice(0, 2), left, 21);
        }

        doc.setFont('helvetica', 'bold');
        doc.setFontSize(8);
        doc.setTextColor(24, 125, 114);
        doc.text('LAPORAN KEUANGAN', right, 15, { align: 'right' });
        doc.setFont('helvetica', 'normal');
        doc.setFontSize(8);
        doc.setTextColor(72, 91, 86);
        doc.text(`${la.formatDate(report.from)} - ${la.formatDate(report.to)}`, right, 21, { align: 'right' });
        doc.text(`Dicetak ${la.formatDate(new Date().toISOString().slice(0, 10))}`, right, 26, { align: 'right' });
        doc.setDrawColor(210, 224, 219);
        doc.line(left, 33, right, 33);
        doc.setFont('helvetica', 'bold');
        doc.setFontSize(16);
        doc.setTextColor(28, 48, 47);
        doc.text(title, left, 44);
        doc.setFont('helvetica', 'normal');
        doc.setFontSize(8);
        doc.setTextColor(101, 119, 114);
        doc.text('Disusun berdasarkan jurnal umum yang telah tercatat.', left, 50);
        return 59;
      };

      const rowsForType = (totals, type) =>
        Object.keys(totals)
          .filter(code => report.accountMeta[code]?.account_type === type)
          .sort((first, second) => first.localeCompare(second, undefined, { numeric: true }))
          .map(code => ({
            label: `${code} - ${report.accountMeta[code].account_name}`,
            value: totals[code]
          }));

      let hasPage = false;
      const drawStatement = (title, rows) => {
        if (hasPage) doc.addPage();
        hasPage = true;
        let y = drawHeader(title);

        const drawColumnHead = () => {
          doc.setFillColor(239, 246, 243);
          doc.rect(left, y, right - left, 9, 'F');
          doc.setFont('helvetica', 'bold');
          doc.setFontSize(7.5);
          doc.setTextColor(72, 91, 86);
          doc.text('KETERANGAN', left + 3, y + 6);
          doc.text('JUMLAH', right - 3, y + 6, { align: 'right' });
          y += 9;
        };

        drawColumnHead();

        rows.forEach(row => {
          if (row.kind === 'spacer') {
            y += 4;
            return;
          }

          const labelWidth = right - left - 52;
          const labelLines = doc.splitTextToSize(row.label, labelWidth);
          const rowHeight = row.kind === 'section'
            ? 9
            : Math.max(8, labelLines.length * 4.5 + 3);

          if (y + rowHeight > pageHeight - 19) {
            doc.addPage();
            y = drawHeader(`${title} - lanjutan`);
            drawColumnHead();
          }

          if (row.kind === 'section') {
            doc.setFillColor(247, 250, 249);
            doc.rect(left, y, right - left, rowHeight, 'F');
            doc.setFont('helvetica', 'bold');
            doc.setFontSize(8);
            doc.setTextColor(24, 125, 114);
            doc.text(row.label.toUpperCase(), left + 3, y + 6);
          } else {
            const isTotal = row.kind === 'total';
            doc.setFont('helvetica', isTotal ? 'bold' : 'normal');
            doc.setFontSize(8.5);
            doc.setTextColor(28, 48, 47);
            if (isTotal) {
              doc.setDrawColor(210, 224, 219);
              doc.line(left, y, right, y);
            }
            doc.text(labelLines, left + 3, y + 5);
            doc.text(row.displayValue || formatAmount(row.value), right - 3, y + 5, { align: 'right' });
          }

          y += rowHeight;
          doc.setDrawColor(231, 238, 235);
          doc.line(left, y, right, y);
        });
      };

      const incomeRows = [
        { kind: 'section', label: 'Pendapatan' },
        ...rowsForType(report.periodTotals, 'Revenue'),
        { kind: 'total', label: 'Total Pendapatan', value: report.revenue },
        { kind: 'spacer' },
        { kind: 'section', label: 'Beban' },
        ...rowsForType(report.periodTotals, 'Expense'),
        { kind: 'total', label: 'Total Beban', value: report.expense },
        { kind: 'spacer' },
        { kind: 'total', label: 'Laba / (Rugi) Bersih', value: report.profit }
      ];

      drawStatement('Laporan Laba Rugi', incomeRows);

      if (kind === 'package') {
        drawStatement('Laporan Posisi Keuangan', [
          { kind: 'section', label: 'Aset' },
          ...rowsForType(report.closingTotals, 'Asset'),
          { kind: 'total', label: 'Total Aset', value: report.assets },
          { kind: 'spacer' },
          { kind: 'section', label: 'Liabilitas' },
          ...rowsForType(report.closingTotals, 'Liability'),
          { kind: 'total', label: 'Total Liabilitas', value: report.liabilities },
          { kind: 'spacer' },
          { kind: 'section', label: 'Ekuitas' },
          ...rowsForType(report.closingTotals, 'Equity'),
          { kind: 'row', label: 'Laba / (Rugi) Berjalan', value: report.reconciliation.liabilitiesEquity - report.liabilities - report.equity },
          { kind: 'total', label: 'Total Liabilitas + Ekuitas', value: report.liabilitiesEquity }
        ]);

        drawStatement('Laporan Perubahan Ekuitas', [
          { kind: 'row', label: 'Saldo ekuitas awal periode', value: report.openingEquity },
          { kind: 'row', label: 'Setoran modal bersih', value: report.financingCash },
          { kind: 'row', label: 'Laba / (Rugi) periode berjalan', value: report.profit },
          { kind: 'row', label: 'Penyesuaian / penarikan modal lainnya', value: report.otherEquityMovements },
          { kind: 'total', label: 'Saldo ekuitas akhir periode', value: report.endingEquity }
        ]);

        drawStatement('Laporan Arus Kas', [
          { kind: 'row', label: 'Saldo kas awal periode', value: report.reconciliation.openingCash },
          { kind: 'row', label: 'Penerimaan aktivitas operasi', value: report.operatingCashIn },
          { kind: 'row', label: 'Pengeluaran aktivitas operasi', value: -report.operatingCashOut },
          { kind: 'row', label: 'Arus kas bersih aktivitas operasi', value: report.operatingCashNet },
          { kind: 'row', label: 'Arus kas bersih aktivitas pendanaan', value: report.financingCash },
          { kind: 'total', label: 'Kenaikan / (Penurunan) Kas dan Bank', value: report.operatingCashNet + report.financingCash },
          { kind: 'total', label: 'Saldo kas akhir arus kas', value: report.reconciliation.cashFlowBalance },
          { kind: 'row', label: 'Saldo akun Kas dan Bank', value: report.cashBalance }
        ]);

        drawStatement('Rekonsiliasi dan Kontrol', [
          { kind: 'row', label: 'Total Debit Jurnal', value: report.reconciliation.debit },
          { kind: 'row', label: 'Total Kredit Jurnal', value: report.reconciliation.credit },
          { kind: 'row', label: 'Total Aset', value: report.assets },
          { kind: 'row', label: 'Liabilitas + Ekuitas', value: report.liabilitiesEquity },
          { kind: 'row', label: 'Saldo kas akhir arus kas', value: report.reconciliation.cashFlowBalance },
          { kind: 'row', label: 'Saldo Kas dan Bank', value: report.cashBalance },
          { kind: 'total', label: 'Status rekonsiliasi', value: 0, displayValue: 'TEREKONSILIASI' }
        ]);
      }

      const pageCount = doc.getNumberOfPages();
      for (let pageNumber = 1; pageNumber <= pageCount; pageNumber++) {
        doc.setPage(pageNumber);
        doc.setDrawColor(210, 224, 219);
        doc.line(left, pageHeight - 13, right, pageHeight - 13);
        doc.setFont('helvetica', 'normal');
        doc.setFontSize(7);
        doc.setTextColor(101, 119, 114);
        doc.text('LAVE Dress Rental & Accounting', left, pageHeight - 8);
        doc.text(`Halaman ${pageNumber} dari ${pageCount}`, right, pageHeight - 8, { align: 'right' });
      }

      doc.save(
        `LAVE_Laporan_${kind === 'income' ? 'Laba_Rugi' : 'Keuangan_Lengkap'}_${report.to}.pdf`
      );
    }

    document
      .getElementById('refreshReports')
      .addEventListener('click', loadReport);

    document
      .getElementById('pdfIncome')
      .addEventListener('click', () => exportPdf('income'));

    document
      .getElementById('pdfPackage')
      .addEventListener('click', () => exportPdf('package'));

    await loadReport();
  }

    async function initAccountingPage() {
    const legacyPage = document.querySelector('.page');
    if (legacyPage) legacyPage.style.display = 'none';
    const root = document.querySelector('.main') || document.body;
    const titles = {
      'buku-besar': 'Buku Besar',
      'neraca-saldo': 'Neraca Saldo'
    };
    const title = titles[page];

    root.insertAdjacentHTML(
      'beforeend',
      `<section class="page" id="accountingPage"><div class="page-title"><div><h2>${title}</h2><p>Sumber data: journal entries dan journal details.</p></div></div><div class="card" style="padding:18px;margin-bottom:18px"><div class="form-grid"><div class="field"><label>Dari Tanggal</label><input id="accountingFrom" type="date"></div><div class="field"><label>Sampai Tanggal</label><input id="accountingTo" type="date"></div><div class="field"><label>Akun</label><select id="accountingAccount"><option value="">Semua Akun</option></select></div><div class="field"><label>&nbsp;</label><button class="btn btn-primary" id="accountingRefresh">Tampilkan</button></div></div></div><div id="accountingAlert"></div><div class="card table-card"><div class="table-wrap"><table><thead id="accountingHead"></thead><tbody id="accountingRows"></tbody><tfoot id="accountingFoot"></tfoot></table></div></div></section>`
    );

    const today = new Date();
    const from = new Date(today.getFullYear(), 0, 1);

    document.getElementById('accountingFrom').value =
      from.toISOString().slice(0, 10);

    document.getElementById('accountingTo').value =
      today.toISOString().slice(0, 10);

    const accountsResult = await supabase
      .from('accounts')
      .select('*')
      .order('account_code');

    if (accountsResult.error) {
      la.toast(accountsResult.error.message, 'error');
      return;
    }

    document.getElementById('accountingAccount').innerHTML +=
      (accountsResult.data || [])
        .map(
          account =>
            `<option value="${account.id}">${la.escape(account.account_code)} - ${la.escape(account.account_name)}</option>`
        )
        .join('');

    async function render() {
      const start =
        document.getElementById('accountingFrom').value;

      const end =
        document.getElementById('accountingTo').value;

      const accountId =
        document.getElementById('accountingAccount').value;

      const result = await supabase
        .from('v_general_ledger')
        .select('*')
        .gte('journal_date', start)
        .lte('journal_date', end)
        .order('journal_date')
        .order('journal_number');

      if (result.error) {
        la.toast(result.error.message, 'error');
        return;
      }

      let rows = result.data || [];

      if (accountId) {
        rows = rows.filter(
          row => String(row.account_id) === String(accountId)
        );
      }

      const head = document.getElementById('accountingHead');
      const body = document.getElementById('accountingRows');
      const foot = document.getElementById('accountingFoot');

      if (page === 'buku-besar') {
        head.innerHTML =
          '<tr><th>Tanggal</th><th>Nomor Jurnal</th><th>Akun</th><th>Referensi</th><th>Keterangan</th><th>Debit</th><th>Kredit</th><th>Saldo</th></tr>';

        const running = {};

        body.innerHTML =
          rows
            .map(row => {
              running[row.account_id] =
                (running[row.account_id] || 0) +
                Number(row.signed_amount || 0);

              return `<tr><td>${la.formatDate(row.journal_date)}</td><td>${la.escape(row.journal_number)}</td><td>${la.escape(row.account_code)} - ${la.escape(row.account_name)}</td><td>${la.escape(row.reference_type || '-')}</td><td>${la.escape(row.journal_description || '-')}</td><td>${money(row.debit)}</td><td>${money(row.credit)}</td><td>${money(running[row.account_id])}</td></tr>`;
            })
            .join('') ||
          '<tr><td colspan="8" class="empty">Belum ada ledger.</td></tr>';

        foot.innerHTML = '';
      } else {
        head.innerHTML =
          '<tr><th>Kode Akun</th><th>Nama Akun</th><th>Debit</th><th>Kredit</th><th>Saldo</th></tr>';

        const balances = {};

        rows.forEach(row => {
          balances[row.account_id] ||= {
            code: row.account_code,
            name: row.account_name,
            type: row.account_type,
            debit: 0,
            credit: 0
          };

          balances[row.account_id].debit +=
            Number(row.debit || 0);

          balances[row.account_id].credit +=
            Number(row.credit || 0);
        });

        let totalDebit = 0;
        let totalCredit = 0;

        body.innerHTML =
          Object.values(balances)
            .map(account => {
              totalDebit += account.debit;
              totalCredit += account.credit;

              const balance =
                ['Asset', 'Expense'].includes(account.type)
                  ? account.debit - account.credit
                  : account.credit - account.debit;

              return `<tr><td>${la.escape(account.code)}</td><td>${la.escape(account.name)}</td><td>${money(account.debit)}</td><td>${money(account.credit)}</td><td>${money(balance)}</td></tr>`;
            })
            .join('') ||
          '<tr><td colspan="5" class="empty">Belum ada saldo.</td></tr>';

        foot.innerHTML =
          `<tr><th colspan="2">TOTAL</th><th>${money(totalDebit)}</th><th>${money(totalCredit)}</th><th>${Math.abs(totalDebit - totalCredit) < 0.01 ? 'Seimbang' : 'Tidak Seimbang'}</th></tr>`;

        document.getElementById('accountingAlert').innerHTML =
          Math.abs(totalDebit - totalCredit) < 0.01
            ? '<div class="badge success" style="padding:12px">✓ TOTAL DEBIT = TOTAL KREDIT</div>'
            : '<div class="badge danger" style="padding:12px">⚠ Neraca saldo tidak seimbang.</div>';
      }
    }

    document
      .getElementById('accountingRefresh')
      .addEventListener('click', render);

    await render();
  }

  async function boot() {
    try {
      if (page === 'penyewaan') await initRentalPage();
      if (page === 'pembelian') await initPurchasePage();
      if (page === 'utang') await initPayablePage();
      if (page === 'biaya-operasional') await initExpensePage();
      if (page === 'pembayaran') await initPaymentPage();
      if (page === 'pengembalian') await initReturnPage();
      if (page === 'denda') await initPenaltyPage();
      if (page === 'dashboard') await initDashboardPage();
      if (page === 'laporan') await initLaporanPage();

      if (['buku-besar', 'neraca-saldo'].includes(page)) {
        await initAccountingPage();
      }
    } catch (error) {
      console.error(error);

      if (window.lave && window.lave.toast) {
        window.lave.toast(
          error.message || 'Terjadi kesalahan.',
          'error'
        );
      }
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener(
      'DOMContentLoaded',
      boot,
      { once: true }
    );
  } else {
    boot();
  }
})();