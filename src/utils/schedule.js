// Weekly-digest schedule options + display helper (per-club).

// Day of week: 0 = Sunday … 6 = Saturday (matches JS Date.getDay()).
export const DAYS = [
  { value: 0, label: 'Sunday' },
  { value: 1, label: 'Monday' },
  { value: 2, label: 'Tuesday' },
  { value: 3, label: 'Wednesday' },
  { value: 4, label: 'Thursday' },
  { value: 5, label: 'Friday' },
  { value: 6, label: 'Saturday' },
]

// 24 hourly options with a friendly 12-hour label.
export const HOURS = Array.from({ length: 24 }, (_, h) => {
  const ampm = h < 12 ? 'AM' : 'PM'
  const h12 = h % 12 === 0 ? 12 : h % 12
  return { value: h, label: `${h12}:00 ${ampm}` }
})

// Curated timezones (IANA names). Default is Asia/Dubai (the app's home).
export const TIMEZONES = [
  { value: 'Asia/Dubai',       label: 'Gulf (Dubai, Abu Dhabi)' },
  { value: 'Asia/Kolkata',     label: 'India (IST)' },
  { value: 'Asia/Karachi',     label: 'Pakistan (PKT)' },
  { value: 'Asia/Colombo',     label: 'Sri Lanka' },
  { value: 'Asia/Dhaka',       label: 'Bangladesh' },
  { value: 'Asia/Kathmandu',   label: 'Nepal' },
  { value: 'Asia/Riyadh',      label: 'Saudi Arabia' },
  { value: 'Asia/Qatar',       label: 'Qatar' },
  { value: 'Asia/Singapore',   label: 'Singapore / Malaysia' },
  { value: 'Asia/Manila',      label: 'Philippines' },
  { value: 'Europe/London',    label: 'UK (London)' },
  { value: 'Europe/Berlin',    label: 'Central Europe' },
  { value: 'America/New_York', label: 'US Eastern' },
  { value: 'America/Los_Angeles', label: 'US Pacific' },
  { value: 'Australia/Sydney', label: 'Australia (Sydney)' },
]

const dayLabel = dow => DAYS.find(d => d.value === dow)?.label ?? 'Sunday'
const hourLabel = h => HOURS.find(x => x.value === h)?.label ?? `${h}:00`
const tzLabel = tz => TIMEZONES.find(z => z.value === tz)?.label ?? tz

/** "Sundays at 9:00 PM (Gulf)" — for showing the current schedule. */
export function describeSchedule(dow, hour, tz) {
  return `${dayLabel(dow)}s at ${hourLabel(hour)} (${tzLabel(tz)})`
}
