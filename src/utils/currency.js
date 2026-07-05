// Per-club currency helpers.
// Money is stored as a plain number; each club carries a 3-letter ISO 4217
// currency code (clubs.currency, default 'AED'). We render "<CODE> <amount>"
// — code prefix rather than a symbol, so it's unambiguous everywhere
// ($ / ₹ / د.إ can be ambiguous or render poorly).

// Common currencies offered in the picker (code → label). Ordered by likely use.
export const CURRENCIES = [
  { code: 'AED', label: 'AED — UAE Dirham' },
  { code: 'INR', label: 'INR — Indian Rupee' },
  { code: 'USD', label: 'USD — US Dollar' },
  { code: 'GBP', label: 'GBP — British Pound' },
  { code: 'EUR', label: 'EUR — Euro' },
  { code: 'SAR', label: 'SAR — Saudi Riyal' },
  { code: 'QAR', label: 'QAR — Qatari Riyal' },
  { code: 'OMR', label: 'OMR — Omani Rial' },
  { code: 'BHD', label: 'BHD — Bahraini Dinar' },
  { code: 'KWD', label: 'KWD — Kuwaiti Dinar' },
  { code: 'PKR', label: 'PKR — Pakistani Rupee' },
  { code: 'LKR', label: 'LKR — Sri Lankan Rupee' },
  { code: 'BDT', label: 'BDT — Bangladeshi Taka' },
  { code: 'NPR', label: 'NPR — Nepalese Rupee' },
  { code: 'PHP', label: 'PHP — Philippine Peso' },
  { code: 'MYR', label: 'MYR — Malaysian Ringgit' },
  { code: 'SGD', label: 'SGD — Singapore Dollar' },
  { code: 'IDR', label: 'IDR — Indonesian Rupiah' },
  { code: 'THB', label: 'THB — Thai Baht' },
  { code: 'AUD', label: 'AUD — Australian Dollar' },
  { code: 'CAD', label: 'CAD — Canadian Dollar' },
  { code: 'CNY', label: 'CNY — Chinese Yuan' },
  { code: 'JPY', label: 'JPY — Japanese Yen' },
  { code: 'ZAR', label: 'ZAR — South African Rand' },
  { code: 'EGP', label: 'EGP — Egyptian Pound' },
]

const CURRENCY_CODES = new Set(CURRENCIES.map(c => c.code))

// ISO country code → default currency. Only a practical subset; anything not
// listed falls back to AED (the app's original default).
const COUNTRY_CURRENCY = {
  AE: 'AED', IN: 'INR', US: 'USD', GB: 'GBP',
  SA: 'SAR', QA: 'QAR', OM: 'OMR', BH: 'BHD', KW: 'KWD',
  PK: 'PKR', LK: 'LKR', BD: 'BDT', NP: 'NPR',
  PH: 'PHP', MY: 'MYR', SG: 'SGD', ID: 'IDR', TH: 'THB',
  AU: 'AUD', CA: 'CAD', CN: 'CNY', JP: 'JPY', ZA: 'ZAR', EG: 'EGP',
  // Eurozone (subset)
  DE: 'EUR', FR: 'EUR', ES: 'EUR', IT: 'EUR', NL: 'EUR', IE: 'EUR', PT: 'EUR',
}

/** Normalise any input to a supported 3-letter code, or 'AED'. */
export function normCurrency(code) {
  const c = String(code || '').trim().toUpperCase()
  return CURRENCY_CODES.has(c) ? c : 'AED'
}

/** Suggest a currency from an ISO country code (e.g. 'IN' → 'INR'). */
export function currencyForCountry(countryCode) {
  const cc = String(countryCode || '').trim().toUpperCase()
  return COUNTRY_CURRENCY[cc] || 'AED'
}

/** Format a number as "<CODE> 12.34". Falls back to AED for a blank code. */
export function formatMoney(amount, code = 'AED') {
  const cur = String(code || 'AED').trim().toUpperCase() || 'AED'
  return `${cur} ${Number(amount).toFixed(2)}`
}

/**
 * Suggest a club currency from geo signals: prefer the IP-detected ISO
 * currency when it's a supported non-AED code, else map from the country
 * code (which itself falls back to AED). Used at club creation.
 */
export function suggestCurrency(geoCurrency, countryCode) {
  const fromGeo = normCurrency(geoCurrency)
  return fromGeo !== 'AED' ? fromGeo : currencyForCountry(countryCode)
}
