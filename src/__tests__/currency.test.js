import { describe, it, expect } from 'vitest'
import { formatMoney, normCurrency, currencyForCountry, suggestCurrency, CURRENCIES } from '../utils/currency'

describe('formatMoney()', () => {
  it('formats with the given currency code and 2 decimals', () => {
    expect(formatMoney(10, 'INR')).toBe('INR 10.00')
    expect(formatMoney(10.5, 'USD')).toBe('USD 10.50')
    expect(formatMoney(5, 'AED')).toBe('AED 5.00')
  })
  it('rounds to 2 decimals', () => {
    expect(formatMoney(10.555, 'INR')).toBe('INR 10.55')
    expect(formatMoney(10.556, 'INR')).toBe('INR 10.56')
  })
  it('accepts numeric strings', () => {
    expect(formatMoney('25.5', 'GBP')).toBe('GBP 25.50')
  })
  it('falls back to AED when code is blank/missing', () => {
    expect(formatMoney(5)).toBe('AED 5.00')
    expect(formatMoney(5, '')).toBe('AED 5.00')
    expect(formatMoney(5, null)).toBe('AED 5.00')
  })
  it('upper-cases the code', () => {
    expect(formatMoney(5, 'inr')).toBe('INR 5.00')
  })
})

describe('normCurrency()', () => {
  it('keeps a supported code', () => {
    expect(normCurrency('INR')).toBe('INR')
    expect(normCurrency('inr')).toBe('INR')
  })
  it('falls back to AED for unsupported or invalid input', () => {
    expect(normCurrency('XYZ')).toBe('AED')
    expect(normCurrency('')).toBe('AED')
    expect(normCurrency(null)).toBe('AED')
    expect(normCurrency('IN')).toBe('AED')
  })
})

describe('currencyForCountry()', () => {
  it('maps known countries', () => {
    expect(currencyForCountry('IN')).toBe('INR')
    expect(currencyForCountry('AE')).toBe('AED')
    expect(currencyForCountry('us')).toBe('USD')
    expect(currencyForCountry('DE')).toBe('EUR')
  })
  it('falls back to AED for unknown/blank', () => {
    expect(currencyForCountry('ZZ')).toBe('AED')
    expect(currencyForCountry('')).toBe('AED')
    expect(currencyForCountry(null)).toBe('AED')
  })
})

describe('suggestCurrency()', () => {
  it('prefers a supported non-AED IP currency', () => {
    expect(suggestCurrency('INR', 'US')).toBe('INR')
  })
  it('falls back to the country map when IP currency is AED/blank/unsupported', () => {
    expect(suggestCurrency('AED', 'IN')).toBe('INR')
    expect(suggestCurrency('', 'GB')).toBe('GBP')
    expect(suggestCurrency('XYZ', 'IN')).toBe('INR')
    expect(suggestCurrency(null, 'US')).toBe('USD')
  })
  it('ends at AED when nothing is known', () => {
    expect(suggestCurrency('', '')).toBe('AED')
    expect(suggestCurrency(null, null)).toBe('AED')
  })
})

describe('CURRENCIES list', () => {
  it('every picker code is a valid 3-letter uppercase ISO code', () => {
    for (const c of CURRENCIES) expect(c.code).toMatch(/^[A-Z]{3}$/)
  })
  it('has no duplicate codes', () => {
    const codes = CURRENCIES.map(c => c.code)
    expect(new Set(codes).size).toBe(codes.length)
  })
})
