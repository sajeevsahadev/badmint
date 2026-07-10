const CURRENCY = 'AED'

/** Format a number as an AED amount with 2 decimal places */
export const aed = n => `${CURRENCY} ${Number(n).toFixed(2)}`

/**
 * Parse a date string (YYYY-MM-DD) in local time, not UTC.
 * Appending T00:00:00 forces the Date constructor to treat it as local midnight
 * instead of UTC midnight (which would shift the date in UTC+ timezones).
 */
export const parseLocalDate = d => new Date(d + 'T00:00:00')

/** 'Jan', 'Feb', etc. from a date string */
export const fmtExpMonth = d =>
  d ? parseLocalDate(d).toLocaleDateString('en', { month: 'short' }) : '—'

/** Zero-padded day number from a date string */
export const fmtExpDay = d =>
  d ? String(parseLocalDate(d).getDate()).padStart(2, '0') : '—'

/** YYYY-MM-DD → dd-MM-yyyy (the app's display date format). '' if not a date. */
export const fmtDMY = d => {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(d || '')
  return m ? `${m[3]}-${m[2]}-${m[1]}` : ''
}

/**
 * Relative time label: "just now", "5m ago", "3h ago", "2d ago", or short date.
 * @param {string|Date} ts  ISO timestamp
 */
export function timeAgo(ts) {
  const mins = Math.floor((Date.now() - new Date(ts)) / 60000)
  if (mins < 1)  return 'just now'
  if (mins < 60) return `${mins}m ago`
  const hrs = Math.floor(mins / 60)
  if (hrs < 24)  return `${hrs}h ago`
  const days = Math.floor(hrs / 24)
  if (days < 7)  return `${days}d ago`
  return new Date(ts).toLocaleDateString('en-AE', { day: 'numeric', month: 'short' })
}

/**
 * Device icon from a User-Agent string.
 * Used in AdminPanel to show session origin at a glance.
 */
export function deviceIcon(ua) {
  if (!ua)                   return ''
  if (/iPhone|iPad/i.test(ua)) return '🍎'
  if (/Android/i.test(ua))    return '🤖'
  if (/Windows/i.test(ua))    return '🖥'
  if (/Mac/i.test(ua))        return '💻'
  return '🌐'
}

/** Human-readable "OS · Browser" label from a User-Agent string. */
export function deviceName(ua) {
  if (!ua || ua === 'unknown') return 'Unknown device'
  let os = 'Unknown'
  if (/iPhone/i.test(ua)) os = 'iPhone'
  else if (/iPad/i.test(ua)) os = 'iPad'
  else if (/Android/i.test(ua)) os = 'Android'
  else if (/Windows/i.test(ua)) os = 'Windows'
  else if (/Mac OS X|Macintosh/i.test(ua)) os = 'Mac'
  else if (/Linux/i.test(ua)) os = 'Linux'
  let browser = ''
  if (/Edg\//i.test(ua)) browser = 'Edge'
  else if (/OPR\/|Opera/i.test(ua)) browser = 'Opera'
  else if (/Chrome\//i.test(ua)) browser = 'Chrome'
  else if (/Firefox\//i.test(ua)) browser = 'Firefox'
  else if (/Safari\//i.test(ua)) browser = 'Safari'
  return browser ? `${os} · ${browser}` : os
}
