// Country → first-level administrative subdivisions (states / emirates /
// provinces / governorates), used to make the club "region" picker adapt to
// the club's country instead of always showing UAE emirates.
//
// This is static reference data — kept in the bundle (small, offline, no
// query) rather than DB master tables. Countries NOT listed here fall back to
// a free-text region input, so the app still works everywhere; add a country's
// list below when its subdivisions are needed.
//
// `label` is what that country calls the level (Emirate / State / Province /
// Governorate / Region), shown as the field label and the "— Select … —" hint.

export const SUBDIVISIONS = {
  AE: { label: 'Emirate', options: [
    'Abu Dhabi', 'Dubai', 'Sharjah', 'Ajman', 'Umm Al Quwain', 'Ras Al Khaimah', 'Fujairah',
  ]},
  IN: { label: 'State', options: [
    'Andhra Pradesh', 'Arunachal Pradesh', 'Assam', 'Bihar', 'Chhattisgarh', 'Goa', 'Gujarat',
    'Haryana', 'Himachal Pradesh', 'Jharkhand', 'Karnataka', 'Kerala', 'Madhya Pradesh',
    'Maharashtra', 'Manipur', 'Meghalaya', 'Mizoram', 'Nagaland', 'Odisha', 'Punjab',
    'Rajasthan', 'Sikkim', 'Tamil Nadu', 'Telangana', 'Tripura', 'Uttar Pradesh',
    'Uttarakhand', 'West Bengal',
    'Andaman & Nicobar Islands', 'Chandigarh', 'Dadra & Nagar Haveli and Daman & Diu',
    'Delhi', 'Jammu & Kashmir', 'Ladakh', 'Lakshadweep', 'Puducherry',
  ]},
  SA: { label: 'Region', options: [
    'Riyadh', 'Makkah', 'Madinah', 'Eastern Province', 'Asir', 'Tabuk', 'Hail',
    'Northern Borders', 'Jazan', 'Najran', 'Al Bahah', 'Al Jawf', 'Qassim',
  ]},
  QA: { label: 'Municipality', options: [
    'Doha', 'Al Rayyan', 'Al Wakrah', 'Al Khor', 'Al Daayen', 'Umm Salal',
    'Al Shamal', 'Al Shahaniya',
  ]},
  OM: { label: 'Governorate', options: [
    'Muscat', 'Dhofar', 'Musandam', 'Al Buraimi', 'Ad Dakhiliyah', 'Al Batinah North',
    'Al Batinah South', 'Ash Sharqiyah North', 'Ash Sharqiyah South', 'Adh Dhahirah', 'Al Wusta',
  ]},
  BH: { label: 'Governorate', options: ['Capital', 'Muharraq', 'Northern', 'Southern'] },
  KW: { label: 'Governorate', options: [
    'Al Asimah', 'Hawalli', 'Al Farwaniyah', 'Mubarak Al-Kabeer', 'Al Ahmadi', 'Al Jahra',
  ]},
  PK: { label: 'Province', options: [
    'Punjab', 'Sindh', 'Khyber Pakhtunkhwa', 'Balochistan', 'Gilgit-Baltistan',
    'Azad Jammu & Kashmir', 'Islamabad Capital Territory',
  ]},
  US: { label: 'State', options: [
    'Alabama', 'Alaska', 'Arizona', 'Arkansas', 'California', 'Colorado', 'Connecticut',
    'Delaware', 'Florida', 'Georgia', 'Hawaii', 'Idaho', 'Illinois', 'Indiana', 'Iowa',
    'Kansas', 'Kentucky', 'Louisiana', 'Maine', 'Maryland', 'Massachusetts', 'Michigan',
    'Minnesota', 'Mississippi', 'Missouri', 'Montana', 'Nebraska', 'Nevada', 'New Hampshire',
    'New Jersey', 'New Mexico', 'New York', 'North Carolina', 'North Dakota', 'Ohio',
    'Oklahoma', 'Oregon', 'Pennsylvania', 'Rhode Island', 'South Carolina', 'South Dakota',
    'Tennessee', 'Texas', 'Utah', 'Vermont', 'Virginia', 'Washington', 'West Virginia',
    'Wisconsin', 'Wyoming',
  ]},
  GB: { label: 'Nation', options: ['England', 'Scotland', 'Wales', 'Northern Ireland'] },
  AU: { label: 'State', options: [
    'New South Wales', 'Victoria', 'Queensland', 'Western Australia', 'South Australia',
    'Tasmania', 'Australian Capital Territory', 'Northern Territory',
  ]},
  CA: { label: 'Province', options: [
    'Ontario', 'Quebec', 'British Columbia', 'Alberta', 'Manitoba', 'Saskatchewan',
    'Nova Scotia', 'New Brunswick', 'Newfoundland and Labrador', 'Prince Edward Island',
    'Northwest Territories', 'Yukon', 'Nunavut',
  ]},
}

/** { label, options } for a country's subdivisions, or null (→ free-text). */
export function subdivisionsFor(countryCode) {
  return SUBDIVISIONS[String(countryCode || '').toUpperCase()] || null
}

/** The label a country uses for its region level, or a generic fallback. */
export function regionLabelFor(countryCode) {
  return subdivisionsFor(countryCode)?.label || 'State / Region'
}
