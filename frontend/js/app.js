function openModal(id) {
  document.getElementById(id)?.classList.add('show')
}

function closeModal(id) {
  document.getElementById(id)?.classList.remove('show')
}

function confirmDelete(m = 'Hapus data ini?') {
  return confirm(m)
}

function formatDate(v) {
  return v ? new Date(v).toLocaleDateString('id-ID') : '-'
}

function setupMobileNavigation() {
  const sidebar = document.querySelector('.sidebar')
  const topbar = document.querySelector('.topbar')
  if (!sidebar || !topbar) return

  sidebar.id = 'appSidebar'

  const toggle = document.createElement('button')
  toggle.type = 'button'
  toggle.className = 'menu-toggle'
  toggle.setAttribute('aria-label', 'Buka menu navigasi')
  toggle.setAttribute('aria-controls', sidebar.id)
  toggle.setAttribute('aria-expanded', 'false')
  toggle.innerHTML = '<span></span><span></span><span></span>'
  topbar.prepend(toggle)

  const backdrop = document.createElement('button')
  backdrop.type = 'button'
  backdrop.className = 'sidebar-backdrop'
  backdrop.setAttribute('aria-label', 'Tutup menu navigasi')
  document.querySelector('.app')?.append(backdrop)

  const closeMenu = () => {
    document.body.classList.remove('mobile-nav-open')
    toggle.setAttribute('aria-expanded', 'false')
    toggle.setAttribute('aria-label', 'Buka menu navigasi')
  }

  toggle.addEventListener('click', () => {
    const isOpen = document.body.classList.toggle('mobile-nav-open')
    toggle.setAttribute('aria-expanded', String(isOpen))
    toggle.setAttribute('aria-label', isOpen ? 'Tutup menu navigasi' : 'Buka menu navigasi')
  })

  backdrop.addEventListener('click', closeMenu)
  sidebar.querySelectorAll('a').forEach(link => link.addEventListener('click', closeMenu))
  document.addEventListener('keydown', event => {
    if (event.key === 'Escape') closeMenu()
  })
  window.matchMedia('(min-width: 721px)').addEventListener('change', closeMenu)
}

async function bootPage() {
  const p = document.body.dataset.page
  const flowStyles = document.createElement('link')
  flowStyles.rel = 'stylesheet'
  flowStyles.href = '../css/variant-flow.css'
  document.head.append(flowStyles)

  document.querySelectorAll('.nav a').forEach(a => {
    if (a.dataset.page === p) a.classList.add('active')
  })

  document.querySelectorAll('.nav a[data-page="pembayaran"], .nav a[data-page="kas-masuk"], .nav a[data-page="kas-keluar"]').forEach(el => el.remove())

  const nav = document.querySelector('.nav')

  if (nav && !nav.querySelector('[data-page="modal-pemilik"]')) {
    const link = document.createElement('a')
    link.href = 'modal-pemilik.html'
    link.dataset.page = 'modal-pemilik'
    link.textContent = 'Modal Pemilik'

    const existingFinanceTitle = Array.from(nav.querySelectorAll('.nav-title')).find(item =>
      ['persediaan & keuangan', 'keuangan'].includes(item.textContent.trim().toLowerCase())
    )
    const firstFinanceLink = nav.querySelector('a[href="pembelian.html"], a[data-page="pembelian"]')

    if (existingFinanceTitle && firstFinanceLink) {
      nav.insertBefore(link, firstFinanceLink)
    } else if (firstFinanceLink) {
      const title = document.createElement('div')
      title.className = 'nav-title'
      title.textContent = 'Keuangan'
      nav.insertBefore(title, firstFinanceLink)
      nav.insertBefore(link, firstFinanceLink)
    } else {
      nav.append(link)
    }

    if (p === 'modal-pemilik') link.classList.add('active')
  }

  if (nav) {
    const navTitles = Array.from(nav.querySelectorAll('.nav-title'))
    const financeTitle = navTitles.find(item =>
      ['persediaan & keuangan', 'keuangan'].includes(item.textContent.trim().toLowerCase())
    ) || (() => {
      const item = document.createElement('div')
      item.className = 'nav-title'
      nav.appendChild(item)
      return item
    })()

    financeTitle.textContent = 'Keuangan'

    const labels = {
      penyewaan: '◇ Penyewaan',
      pengembalian: '↩ Pengembalian',
      denda: '! Denda',
      'modal-pemilik': 'Modal Pemilik',
      pembelian: '＋ Pembelian',
      persediaan: '▥ Persediaan',
      utang: '≡ Utang',
      'biaya-operasional': '◌ Biaya Operasional'
    }

    const findNavLink = pageName =>
      nav.querySelector(`a[data-page="${pageName}"], a[href="${pageName}.html"]`)

    Object.entries(labels).forEach(([pageName, label]) => {
      const link = findNavLink(pageName)
      if (link) link.textContent = label
    })

    const rentalLabels = {
      penyewaan: '◇ Penyewaan',
      pengembalian: '↩ Pengembalian',
      denda: '! Denda'
    }

    let rentalTitle = Array.from(nav.querySelectorAll('.nav-title')).find(
      item => item.textContent.trim().toLowerCase() === 'penyewaan'
    )

    if (!rentalTitle) {
      rentalTitle = document.createElement('div')
      rentalTitle.className = 'nav-title'
      rentalTitle.textContent = 'Penyewaan'
      nav.insertBefore(rentalTitle, financeTitle)
    }

    const rentalLinks = Object.entries(rentalLabels).map(([pageName, label]) => {
      let link = findNavLink(pageName)

      if (!link) {
        link = document.createElement('a')
        link.href = `${pageName}.html`
        link.dataset.page = pageName
      }

      link.textContent = label
      return link
    })

    rentalTitle.after(...rentalLinks)

    const orderedFinanceLinks = [
      'modal-pemilik',
      'pembelian',
      'persediaan',
      'utang',
      'biaya-operasional'
    ].map(findNavLink).filter(Boolean)

    financeTitle.after(...orderedFinanceLinks)
  }

  setupMobileNavigation()

  const target = document.getElementById('currentUser') || document.querySelector('.topbar > .muted')
  if (target) target.textContent = 'Akses publik'

  if (
    ['pembelian', 'utang', 'biaya-operasional', 'buku-besar', 'neraca-saldo'].includes(p) &&
    !document.querySelector('script[src*="integrated-flow.js"]')
  ) {
    const integratedScript = document.createElement('script')
    integratedScript.src = '../js/integrated-flow.js'
    document.body.appendChild(integratedScript)
  }
}

if (document.readyState === 'loading') {
  document.addEventListener(
    'DOMContentLoaded',
    () => bootPage().catch(error =>
      window.lave.handleSupabaseError(error, {module: 'App', operation: 'INIT'})
    ),
    {once: true}
  )
} else {
  bootPage().catch(error =>
    window.lave.handleSupabaseError(error, {module: 'App', operation: 'INIT'})
  )
}