const SUPABASE_URL = "https://vmirgyitrohnmfhntbvq.supabase.co";
const SUPABASE_ANON_KEY = "sb_publishable_i67HUOx1_B85oitnRjKvCw_YIqj5eDe";

const supabaseClient = window.supabase.createClient(
  SUPABASE_URL,
  SUPABASE_ANON_KEY
);

const moneyFormat = new Intl.NumberFormat('id-ID', {
  style: 'currency',
  currency: 'IDR',
  maximumFractionDigits: 0
});

const safeNumber = v => Number(v || 0);

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

  currency: v => moneyFormat.format(safeNumber(v)),

  escape: v =>
    String(v ?? '')
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#039;'),

  toast: (m, t = 'success') => {
    const e = document.getElementById('toast');
    if (!e) return alert(m);
    e.textContent = m;
    e.className = 'toast show ' + t;
    setTimeout(() => e.className = 'toast', 2500)
  },

  formatDate: v => {
    if (!v) return '-';
    const d = new Date(v);
    return Number.isNaN(d.getTime())
      ? String(v)
      : d.toLocaleDateString('id-ID', {
          day: 'numeric',
          month: 'short',
          year: 'numeric'
        })
  },

  pad: (n, d = 2) => String(n).padStart(d, '0'),

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