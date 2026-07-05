import { describe, it, expect } from 'vitest'
import { DAYS, HOURS, TIMEZONES, describeSchedule } from '../utils/schedule'

describe('schedule constants', () => {
  it('DAYS is Sun..Sat as 0..6', () => {
    expect(DAYS.map(d => d.value)).toEqual([0, 1, 2, 3, 4, 5, 6])
    expect(DAYS[0].label).toBe('Sunday')
    expect(DAYS[6].label).toBe('Saturday')
  })
  it('HOURS has 24 entries with 12-hour labels', () => {
    expect(HOURS).toHaveLength(24)
    expect(HOURS[0].label).toBe('12:00 AM')
    expect(HOURS[12].label).toBe('12:00 PM')
    expect(HOURS[21].label).toBe('9:00 PM')
    expect(HOURS[13].label).toBe('1:00 PM')
  })
  it('TIMEZONES are valid IANA names usable by Intl', () => {
    for (const z of TIMEZONES) {
      expect(() => new Intl.DateTimeFormat('en-US', { timeZone: z.value })).not.toThrow()
    }
  })
})

describe('describeSchedule()', () => {
  it('describes the default Sunday 9 PM Gulf schedule', () => {
    expect(describeSchedule(0, 21, 'Asia/Dubai')).toBe('Sundays at 9:00 PM (Gulf (Dubai, Abu Dhabi))')
  })
  it('handles other days/times', () => {
    expect(describeSchedule(3, 8, 'Asia/Kolkata')).toBe('Wednesdays at 8:00 AM (India (IST))')
  })
})
