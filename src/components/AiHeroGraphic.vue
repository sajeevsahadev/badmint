<script setup>
// Marketing hero for AI Match Analysis — an animated mock of player tracking on a court,
// in the style of the reference (bounding boxes, live-analysis badge, coverage stat).
// Pure SVG/CSS, no data; used on the AI hub and marketing teasers.
</script>

<template>
  <div class="ai-hero">
    <svg viewBox="0 0 640 360" class="w-full h-auto block" xmlns="http://www.w3.org/2000/svg">
      <defs>
        <linearGradient id="aiCourt" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stop-color="#1f8a63" /><stop offset="100%" stop-color="#166b4c" />
        </linearGradient>
        <linearGradient id="aiBg" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0%" stop-color="#0b2a4a" /><stop offset="100%" stop-color="#10233f" />
        </linearGradient>
      </defs>

      <rect x="0" y="0" width="640" height="360" fill="url(#aiBg)" rx="14" />
      <!-- Court (perspective-ish trapezoid) -->
      <polygon points="150,70 490,70 600,320 40,320" fill="url(#aiCourt)" opacity="0.95" />
      <!-- lines -->
      <g stroke="#ffffff" stroke-opacity="0.7" stroke-width="1.5" fill="none">
        <polygon points="150,70 490,70 600,320 40,320" />
        <line x1="128" y1="195" x2="512" y2="195" stroke-width="2.5" />
        <line x1="320" y1="70" x2="320" y2="320" stroke-opacity="0.4" />
      </g>

      <!-- scanning line -->
      <rect class="scan" x="40" y="70" width="560" height="3" fill="#22d3ee" opacity="0.5" />

      <!-- Player 1 (near) -->
      <g>
        <rect x="250" y="210" width="78" height="92" fill="none" stroke="#22d3ee" stroke-width="2.5" rx="4" />
        <rect x="250" y="192" width="92" height="16" fill="#0e7490" rx="3" />
        <text x="256" y="204" fill="#fff" font-size="11" font-family="sans-serif" font-weight="700">Player 1 · 0.57</text>
        <circle cx="289" cy="256" r="10" fill="#22d3ee" opacity="0.25" />
      </g>
      <!-- Player 2 (far) -->
      <g>
        <rect x="360" y="110" width="56" height="70" fill="none" stroke="#fbbf24" stroke-width="2.5" rx="4" />
        <rect x="360" y="94" width="78" height="15" fill="#b45309" rx="3" />
        <text x="365" y="105" fill="#fff" font-size="10" font-family="sans-serif" font-weight="700">Player 2 · 0.62</text>
      </g>

      <!-- Live Analysis pill -->
      <g>
        <rect x="470" y="30" width="140" height="26" rx="13" fill="#000" opacity="0.45" />
        <circle class="pulse" cx="486" cy="43" r="4" fill="#34d399" />
        <text x="498" y="47" fill="#fff" font-size="12" font-family="sans-serif" font-weight="600">Live Analysis</text>
      </g>

      <!-- Coverage stat -->
      <g>
        <rect x="24" y="300" width="150" height="40" rx="8" fill="#000" opacity="0.5" />
        <text x="34" y="316" fill="#9ca3af" font-size="8" font-family="sans-serif" letter-spacing="1">COURT COVERAGE</text>
        <text x="34" y="334" fill="#fff" font-size="18" font-family="sans-serif" font-weight="800">94.3%</text>
      </g>

      <!-- Rally stats strip -->
      <g font-family="sans-serif">
        <text x="40" y="52" fill="#67e8f9" font-size="9" letter-spacing="1">RALLY TIME</text>
        <text x="40" y="66" fill="#fff" font-size="13" font-weight="700">3.5s</text>
        <text x="160" y="52" fill="#67e8f9" font-size="9" letter-spacing="1">SHOTS</text>
        <text x="160" y="66" fill="#fff" font-size="13" font-weight="700">7</text>
        <text x="280" y="52" fill="#67e8f9" font-size="9" letter-spacing="1">SMASH (est.)</text>
        <text x="280" y="66" fill="#fff" font-size="13" font-weight="700">291 km/h</text>
      </g>
    </svg>
  </div>
</template>

<style scoped>
.ai-hero { border-radius: 14px; overflow: hidden; }
.pulse { animation: aiPulse 1.3s ease-in-out infinite; }
@keyframes aiPulse { 0%,100% { opacity: 1; r: 4; } 50% { opacity: 0.4; r: 6; } }
.scan { animation: aiScan 3.2s linear infinite; }
@keyframes aiScan { 0% { transform: translateY(0); opacity: 0; } 10% { opacity: 0.5; } 90% { opacity: 0.5; } 100% { transform: translateY(247px); opacity: 0; } }
</style>
