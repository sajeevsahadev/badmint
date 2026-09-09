// AI match parsing — turns a spoken/typed doubles result ("Sajeev & Ravi beat
// Arun & John 21-15") into { sideA, sideB, scoreA, scoreB } with player ids
// resolved against the club roster the client passes in. The LLM only PARSES;
// the app still records via record_match after the user confirms (Design Rule 1).
// Uses Google Gemini Flash (free tier) via GEMINI_API_KEY. verify_jwt = true.

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}
const json = (o: unknown, s = 200) =>
  new Response(JSON.stringify(o), { status: s, headers: { ...cors, 'Content-Type': 'application/json' } })

const MODEL = 'gemini-3.6-flash'

// Normalise a name for comparison: lowercase, strip accents + non-alphanumerics.
function norm(s: string): string {
  return String(s || '').toLowerCase().normalize('NFKD').replace(/[̀-ͯ]/g, '').replace(/[^a-z0-9]/g, '')
}

function lev(a: string, b: string): number {
  const m = a.length, n = b.length
  if (!m) return n
  if (!n) return m
  const d = Array.from({ length: m + 1 }, (_, i) => [i, ...Array(n).fill(0)])
  for (let j = 0; j <= n; j++) d[0][j] = j
  for (let i = 1; i <= m; i++)
    for (let j = 1; j <= n; j++)
      d[i][j] = Math.min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1))
  return d[m][n]
}

type Row = { id: string; name: string }

// Map a spoken name to the closest roster player (exact → prefix → token → fuzzy).
function bestMatch(name: string, roster: Row[]): Row | null {
  const n = norm(name)
  if (!n) return null
  let hit = roster.find(r => norm(r.name) === n)
  if (hit) return hit
  hit = roster.find(r => { const rn = norm(r.name); return rn.startsWith(n) || n.startsWith(rn) })
  if (hit) return hit
  hit = roster.find(r => String(r.name).toLowerCase().split(/\s+/).some(w => norm(w) === n))
  if (hit) return hit
  let best: Row | null = null, bestD = Infinity
  for (const r of roster) { const d = lev(n, norm(r.name)); if (d < bestD) { bestD = d; best = r } }
  return best && bestD <= Math.max(1, Math.floor(n.length * 0.34)) ? best : null
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  try {
    const KEY = Deno.env.get('GEMINI_API_KEY')
    if (!KEY) return json({ error: 'AI entry is not configured yet.' }, 503)

    const b = await req.json()
    const text = String(b.text ?? '').trim()
    const roster: Row[] = (Array.isArray(b.roster) ? b.roster : []).filter((r: Row) => r && r.id && r.name)
    if (!text) return json({ error: 'Say who played and the score.' }, 400)
    if (roster.length < 4) return json({ error: 'Need at least 4 active players to record a match.' }, 400)

    const names = roster.map(r => r.name)
    const prompt = `You parse a spoken badminton DOUBLES result into structured data.
For reference, players in this club are: ${names.join(', ')}.
Sentence: "${text}"
Rules:
- Two teams, exactly 2 players each.
- "A and B beat/beats C and D 21-15" => team1 = [A, B] score1 = 21, team2 = [C, D] score2 = 15.
- If it says "lost to", the first team is the loser (lower score).
- Return each player's name EXACTLY as it appears in the sentence. Do NOT substitute a different roster name — name resolution happens later. (The club list is only to help you segment names correctly.)
Respond as JSON only.`

    let gRes: Response
    try {
      gRes = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent?key=${KEY}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          contents: [{ parts: [{ text: prompt }] }],
          generationConfig: {
            temperature: 0,
            responseMimeType: 'application/json',
            responseSchema: {
              type: 'object',
              properties: {
                team1: { type: 'array', items: { type: 'string' } },
                team2: { type: 'array', items: { type: 'string' } },
                score1: { type: 'integer' },
                score2: { type: 'integer' },
              },
              required: ['team1', 'team2', 'score1', 'score2'],
            },
          },
        }),
      })
    } catch {
      return json({ error: 'Could not reach the AI parser. Enter manually.' }, 502)
    }
    if (!gRes.ok) {
      const detail = (await gRes.text()).slice(0, 300)
      return json({ error: 'The AI parser rejected the request. Enter manually.', detail }, 502)
    }

    const g = await gRes.json()
    let parsed: { team1?: string[]; team2?: string[]; score1?: number; score2?: number }
    try {
      parsed = JSON.parse(g?.candidates?.[0]?.content?.parts?.[0]?.text ?? '{}')
    } catch {
      return json({ error: 'AI returned something unexpected. Enter manually.' }, 502)
    }

    const warnings: string[] = []
    const seen = new Set<string>()
    const mapSide = (arr: unknown) =>
      (Array.isArray(arr) ? arr : []).slice(0, 2).map((nm: string) => {
        const m = bestMatch(String(nm), roster)
        if (!m) { warnings.push(`Couldn't match "${nm}"`); return { name: String(nm), unmatched: true } }
        if (seen.has(m.id)) { warnings.push(`"${m.name}" matched twice`); return { name: m.name, unmatched: true } }
        seen.add(m.id)
        return { id: m.id, name: m.name }
      })

    const sideA = mapSide(parsed.team1)
    const sideB = mapSide(parsed.team2)

    return json({
      ok: true,
      sideA,
      sideB,
      scoreA: Number(parsed.score1) || 0,
      scoreB: Number(parsed.score2) || 0,
      warnings,
    })
  } catch (err) {
    return json({ error: err instanceof Error ? err.message : String(err) }, 500)
  }
})
