(function () {
  const db = window.lave.supabase
  const $ = id => document.getElementById(id)
  const money = value => window.lave.currency(value)
  const esc = value => window.lave.escape(value)

  async function loadAccounts() {
    const result = await db
      .from('accounts')
      .select('id,account_code,account_name,account_type')
      .eq('account_type', 'Asset')
      .order('account_code')

    if (result.error) throw result.error

    const cashAccounts = (result.data || []).filter(account =>
      ['101', '1120'].includes(account.account_code)
    )

    $('capitalAccount').innerHTML =
      '<option value="">Pilih akun kas/bank</option>' +
      cashAccounts
        .map(account =>
          `<option value="${account.id}">${esc(account.account_code)} - ${esc(account.account_name)}</option>`
        )
        .join('')
  }

  async function render() {
    const result = await db
      .from('v_capital_contributions')
      .select('*')
      .order('id', { ascending: false })

    if (result.error) {
      window.lave.handleSupabaseError(result.error, { module: 'Capital', operation: 'SELECT' })
      window.lave.toast(result.error.message, 'error')
      return
    }

    const header = $('capitalRows').closest('table')?.querySelector('thead tr')

    if (header && !header.querySelector('.capital-action-heading')) {
      header.insertAdjacentHTML(
        'beforeend',
        '<th class="capital-action-heading">Aksi</th>'
      )
    }

    $('capitalRows').innerHTML = (result.data || []).length
      ? result.data
          .map(row =>
            `<tr><td>${esc(row.capital_code)}</td><td>${window.lave.formatDate(row.contribution_date)}</td><td>${esc(row.owner_name)}</td><td>${esc(row.contribution_type)}</td><td>${esc(row.account_code)} - ${esc(row.account_name)}</td><td>${money(row.amount)}</td><td>${esc(row.status)}</td><td>${row.status === 'Posted' ? `<button class="btn btn-danger capital-cancel" data-id="${row.id}">Batalkan</button>` : '-'}</td></tr>`
          )
          .join('')
      : '<tr><td colspan="8" class="empty">Belum ada setoran modal.</td></tr>'

    document.querySelectorAll('.capital-cancel').forEach(button =>
      button.addEventListener('click', async () => {
        const reason = window.prompt(
          'Alasan pembatalan setoran modal:',
          'Koreksi transaksi'
        )

        if (!reason) return

        const cancelResult = await db.rpc('cancel_capital_contribution', {
          p_capital_id: Number(button.dataset.id),
          p_reason: reason
        })

        if (cancelResult.error) {
          window.lave.handleSupabaseError(cancelResult.error, {
            module: 'Capital',
            operation: 'CANCEL'
          })
          window.lave.toast(cancelResult.error.message, 'error')
          return
        }

        window.lave.toast('Setoran modal dibatalkan dan jurnal reversal dibuat.')
        await render()
      })
    )
  }

  const assetOption = Array.from($('capitalType').options).find(
    option => option.value === 'Asset' || option.textContent === 'Asset'
  )

  if (assetOption) assetOption.remove()

  $('capitalDate').value = new Date().toISOString().slice(0, 10)

  $('capitalForm').addEventListener('submit', async event => {
    event.preventDefault()

    const payload = {
      p_contribution_date: $('capitalDate').value,
      p_owner_name: $('ownerName').value.trim(),
      p_contribution_type: $('capitalType').value,
      p_cash_account_id: Number($('capitalAccount').value),
      p_amount: Number($('capitalAmount').value),
      p_description: $('capitalDescription').value.trim() || null
    }

    if (
      !payload.p_owner_name ||
      !payload.p_cash_account_id ||
      payload.p_amount <= 0
    ) {
      window.lave.toast(
        'Pemilik, akun kas/bank, dan jumlah wajib diisi.',
        'error'
      )
      return
    }

    const result = await db.rpc('create_capital_contribution', payload)

    if (result.error) {
      window.lave.handleSupabaseError(result.error, {
        module: 'Capital',
        operation: 'INSERT'
      })
      window.lave.toast(result.error.message, 'error')
      return
    }

    const capitalRecord = Array.isArray(result.data)
      ? result.data[0]
      : result.data

    window.lave.toast(
      `Setoran modal ${capitalRecord.capital_code} berhasil diposting.`
    )

    $('capitalForm').reset()
    $('capitalDate').value = new Date().toISOString().slice(0, 10)
    await render()
  })

  Promise.all([loadAccounts(), render()]).catch(error => {
    window.lave.handleSupabaseError(error, {
      module: 'Capital',
      operation: 'INIT'
    })
    window.lave.toast(error.message, 'error')
  })
}())