// GENERATED FILE - SOURCE OF TRUTH: backend/SUPABASE/app.js
// DO NOT EDIT MANUALLY.
// Supabase CDN must load before this file, and frontend/js/app.js after it.

const APP_CONFIG = {
  name: 'LAVÉ Dress Rental & Accounting System',
  version: null
};

const SUPABASE_URL = 'https://vmirgyitrohnmfhntbvq.supabase.co';
const SUPABASE_ANON_KEY = 'sb_publishable_i67HUOx1_B85oitnRjKvCw_YIqj5eDe';

const SUPABASE_CONFIG = {
  service: 'Supabase',
  databaseEngine: 'PostgreSQL',
  url: SUPABASE_URL,
  publicKey: SUPABASE_ANON_KEY,
  browserKeyType: 'publishable/anon',
  auth: {
    provider: 'Supabase Auth',
    integratedInSql: true,
    frontendLoginEnabled: false
  },
  rls: {
    policiesDefinedByMigrations: true,
    disabledByPublicAccessMigration: '36_public_access.sql'
  }
};

const DATABASE_CONFIG = {
  schema: 'public',
  directory: './database',
  contains: [
    'schema',
    'seed',
    'functions',
    'triggers',
    'views',
    'RPC',
    'security',
    'accounting logic'
  ]
};

const ACCOUNTING_CONFIG = {
  table: 'accounts',
  seededAccounts: [
    { code: '101', name: 'Kas', type: 'Asset' },
    { code: '102', name: 'Piutang Usaha', type: 'Asset' },
    { code: '103', name: 'Persediaan Dress', type: 'Asset' },
    { code: '104', name: 'Peralatan', type: 'Asset' },
    { code: '201', name: 'Utang Usaha', type: 'Liability' },
    { code: '202', name: 'Deposit Pelanggan', type: 'Liability' },
    { code: '301', name: 'Modal Pemilik', type: 'Equity' },
    { code: '401', name: 'Pendapatan Sewa', type: 'Revenue' },
    { code: '402', name: 'Pendapatan Denda', type: 'Revenue' },
    { code: '403', name: 'Pendapatan Pembatalan', type: 'Revenue' },
    { code: '501', name: 'Beban Laundry', type: 'Expense' },
    { code: '502', name: 'Beban Repair', type: 'Expense' },
    { code: '503', name: 'Beban Listrik', type: 'Expense' },
    { code: '504', name: 'Beban Internet', type: 'Expense' },
    { code: '505', name: 'Beban Promosi', type: 'Expense' },
    { code: '506', name: 'Beban Transportasi', type: 'Expense' },
    { code: '507', name: 'Beban Sewa Tempat', type: 'Expense' },
    { code: '508', name: 'Beban Lain-lain', type: 'Expense' }
  ],
  referencedButNotSeededCodes: ['1120']
};

const supabaseClient = window.supabase.createClient(
  SUPABASE_URL,
  SUPABASE_ANON_KEY
);

const moneyFormat = new Intl.NumberFormat('id-ID', {
  style: 'currency',
  currency: 'IDR',
  maximumFractionDigits: 0
});

const safeNumber = value => Number(value || 0);

window.lave = {
  supabase: supabaseClient,
  profile: {profile_role: 'admin'},
  hasRole: () => true,

  handleSupabaseError: (error, context = {}) => {
    console.error('Supabase error', {
      ...context,
      code: error?.code,
      message: error?.message,
      details: error?.details,
      hint: error?.hint
    });
    return error
  },

  currency: value => moneyFormat.format(safeNumber(value)),

  escape: value =>
    String(value ?? '')
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#039;'),

  toast: (message, type = 'success') => {
    const element = document.getElementById('toast');
    if (!element) return alert(message);
    element.textContent = message;
    element.className = 'toast show ' + type;
    setTimeout(() => element.className = 'toast', 2500)
  },

  formatDate: value => {
    if (!value) return '-';
    const date = new Date(value);
    return Number.isNaN(date.getTime())
      ? String(value)
      : date.toLocaleDateString('id-ID', {
        day: 'numeric',
        month: 'short',
        year: 'numeric'
      })
  },

  pad: (value, digits = 2) => String(value).padStart(digits, '0'),

  nextCode: async type => {
    const {data, error} = await supabaseClient.rpc('next_business_code', {
      p_type: type
    });
    if (error) throw error;
    return data
  },

  rentalCode: async () => window.lave.nextCode('rental'),
  paymentCode: async () => window.lave.nextCode('payment')
};