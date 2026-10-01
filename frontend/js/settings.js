(function () {
  const db = window.lave.supabase;
  const $ = id => document.getElementById(id);
  const set = (id, value) => {
    if ($(id)) $(id).value = value ?? '';
  };
  const get = id => $(id)?.value;

  function notify(message, type) {
    window.lave.toast(message, type || 'success');
  }

  $('passwordForm')?.remove();
  $('logoutButton')?.remove();

  const accessCard = $('account_email')?.closest('.card');

  if (accessCard) {
    accessCard.querySelector('h3').textContent = 'Akses Publik';
    accessCard.querySelector('label').textContent = 'Mode';
    $('account_role').previousElementSibling.textContent = 'Hak Akses';
    $('account_status').previousElementSibling.textContent = 'Autentikasi';
  }

  async function load() {
    const [business, accounting, preferences, audit] = await Promise.all([
      db
        .from('business_settings')
        .select('*')
        .eq('id', true)
        .single(),
      db
        .from('accounting_settings')
        .select('*')
        .eq('id', true)
        .single(),
      db
        .from('system_preferences')
        .select('*')
        .eq('id', true)
        .single(),
      db
        .from('audit_logs')
        .select('*')
        .order('created_at', { ascending: false })
        .limit(100)
    ]);

    set('account_email', 'Akses publik');
    set('account_role', 'Administrator');
    set('account_status', 'Tanpa login');

    if (business.error) {
      notify(business.error.message, 'error');
    } else {
      const b = business.data || {};
      set('business_name', b.business_name);
      set('business_address', b.address);
      set('business_phone', b.phone);
      set('business_email', b.email);
      set('business_website', b.website);
      set('business_tax', b.tax_number);
      set('business_logo', b.logo_url);
      set('business_description', b.description);
    }

    if (accounting.data) {
      set('currency', accounting.data.currency || 'IDR');
      set('accounting_method', accounting.data.accounting_method);
      set('period_start', accounting.data.period_start);
      set('period_end', accounting.data.period_end);
    }

    if (preferences.data) {
      set('theme', preferences.data.theme);
      set('rows_per_page', preferences.data.rows_per_page);
      set('dashboard_period', preferences.data.dashboard_period);
      $('confirm_delete').checked = preferences.data.confirm_delete;
    }

    $('auditRows').innerHTML = audit.error
      ? `<tr><td colspan="4">${window.lave.escape(audit.error.message)}</td></tr>`
      : (audit.data || [])
          .map(
            row =>
              `<tr><td>${window.lave.formatDate(row.created_at)}</td><td>${window.lave.escape(row.action)}</td><td>${window.lave.escape(row.module)}</td><td>${window.lave.escape(row.record_id || '-')}</td></tr>`
          )
          .join('');
  }

  $('businessForm').addEventListener('submit', async event => {
    event.preventDefault();

    const result = await db.from('business_settings').upsert({
      id: true,
      business_name: get('business_name'),
      address: get('business_address'),
      phone: get('business_phone'),
      email: get('business_email'),
      website: get('business_website'),
      tax_number: get('business_tax'),
      logo_url: get('business_logo'),
      description: get('business_description'),
      updated_at: new Date().toISOString()
    });

    if (result.error) {
      notify(result.error.message, 'error');
    } else {
      notify('Profil bisnis tersimpan.');
    }
  });

  $('accountingForm').addEventListener('submit', async event => {
    event.preventDefault();

    const result = await db.from('accounting_settings').upsert({
      id: true,
      accounting_method: get('accounting_method'),
      period_start: get('period_start') || null,
      period_end: get('period_end') || null
    });

    if (result.error) {
      notify(result.error.message, 'error');
    } else {
      notify('Pengaturan accounting tersimpan.');
    }
  });

  $('preferenceForm').addEventListener('submit', async event => {
    event.preventDefault();

    const result = await db.from('system_preferences').upsert({
      id: true,
      theme: get('theme'),
      rows_per_page: Number(get('rows_per_page')),
      dashboard_period: get('dashboard_period'),
      confirm_delete: $('confirm_delete').checked
    });

    if (result.error) {
      notify(result.error.message, 'error');
    } else {
      notify('Preferensi tersimpan.');
    }
  });

  load().catch(error => notify(error.message, 'error'));
}());