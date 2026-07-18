// Curated country list for club-country pickers (Manage.vue's "Country"
// selector). Same coverage as utils/currency.js's country→currency map, kept
// as a separate small module since country and currency are related but
// distinct concepts (a club's country doesn't have to imply its currency).
export const COUNTRIES = [
  'AE', 'IN', 'US', 'GB', 'SA', 'QA', 'OM', 'BH', 'KW',
  'PK', 'LK', 'BD', 'NP', 'PH', 'MY', 'SG', 'ID', 'TH',
  'AU', 'CA', 'CN', 'JP', 'ZA', 'EG', 'DE', 'FR', 'ES', 'IT', 'NL', 'IE', 'PT',
]

/** Human-readable country name from an ISO-2 code, e.g. 'AE' -> 'United Arab Emirates'. */
export function countryName(code) {
  try { return new Intl.DisplayNames(['en'], { type: 'region' }).of(code) || code }
  catch { return code }
}
