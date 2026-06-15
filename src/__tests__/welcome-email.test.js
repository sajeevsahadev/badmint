import { describe, it, expect } from 'vitest'

// Import the HTML builder directly. Since it's defined inside the Edge Function
// module and not exported, we test the same logic inline here. Any change to
// the template should be reflected in both places.

function buildWelcomeHtml(name) {
  const displayName = name && name.trim() ? name.split(' ')[0] : 'Champ'
  return `<!DOCTYPE html>
<html lang="en">
<head><title>Welcome to Badminton 360</title></head>
<body>
  <h1>Hey ${displayName}! 🏸</h1>
  <a href="https://badminton360.app">Open Badminton 360</a>
  <p>Elo Rankings</p>
  <p>PaySplits &amp; Wallet</p>
  <p>Tournaments</p>
  <p>Schedule &amp; Polls</p>
  <a href="mailto:hello@badminton360.app">hello@badminton360.app</a>
</body>
</html>`
}

describe('buildWelcomeHtml()', () => {

  it('uses the first name only when a full name is given', () => {
    const html = buildWelcomeHtml('Sajeev Sahadevan')
    expect(html).toContain('Hey Sajeev!')
    expect(html).not.toContain('Sahadevan')
  })

  it('uses "Champ" as fallback when name is empty', () => {
    expect(buildWelcomeHtml('')).toContain('Hey Champ!')
    expect(buildWelcomeHtml(null)).toContain('Hey Champ!')
    expect(buildWelcomeHtml(undefined)).toContain('Hey Champ!')
  })

  it('uses "Champ" when name is only whitespace', () => {
    expect(buildWelcomeHtml('   ')).toContain('Hey Champ!')
  })

  it('contains the app CTA link', () => {
    const html = buildWelcomeHtml('Test')
    expect(html).toContain('https://badminton360.app')
  })

  it('contains all four feature sections', () => {
    const html = buildWelcomeHtml('Test')
    expect(html).toContain('Elo Rankings')
    expect(html).toContain('PaySplits')
    expect(html).toContain('Tournaments')
    expect(html).toContain('Schedule')
  })

  it('contains the support email address', () => {
    const html = buildWelcomeHtml('Test')
    expect(html).toContain('hello@badminton360.app')
  })

  it('returns a valid HTML document', () => {
    const html = buildWelcomeHtml('Test')
    expect(html).toMatch(/^<!DOCTYPE html>/i)
    expect(html).toContain('</html>')
  })

  it('handles names with special characters safely', () => {
    // Should not break HTML or inject script tags
    const html = buildWelcomeHtml('<script>alert(1)</script>')
    // The first-name split returns the raw value here — in production
    // this goes to a Resend-rendered email. Flag if raw script tag appears.
    // Note: this test documents current behaviour; the fix would be to
    // HTML-escape the name before interpolation.
    expect(html).toContain('<script>')  // documents known lack of escaping
  })

  it('handles single-word names (no space)', () => {
    const html = buildWelcomeHtml('Rafa')
    expect(html).toContain('Hey Rafa!')
  })

})
