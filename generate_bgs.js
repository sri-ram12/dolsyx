/**
 * generate_bgs.js
 * Creates all WhatsApp-style chat backgrounds locally using SVG → PNG.
 * No internet required. Run: node generate_bgs.js
 * Requires: npm install sharp (or use the SVG fallback)
 */

const fs = require('fs');
const path = require('path');

const dir = path.join(__dirname, 'frontend/public/chat-backgrounds');
if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });

// ─── SVG Generators ──────────────────────────────────────────────────────────

const backgrounds = {

  // 1. Classic WhatsApp Dark Doodle
  'wa-dark-doodle': () => `<svg xmlns="http://www.w3.org/2000/svg" width="1080" height="1920">
    <rect width="1080" height="1920" fill="#1a1a2e"/>
    <defs>
      <pattern id="p" x="0" y="0" width="120" height="120" patternUnits="userSpaceOnUse">
        <!-- heart -->
        <path d="M20,28 L30,18 Q37,11 44,18 Q51,11 58,18 L68,28 Q75,38 44,55 Q13,38 20,28Z" fill="none" stroke="#ffffff22" stroke-width="1.5"/>
        <!-- star -->
        <polygon points="100,10 103,20 114,20 105,27 108,37 100,31 92,37 95,27 86,20 97,20" fill="none" stroke="#ffffff22" stroke-width="1.5"/>
        <!-- speech bubble -->
        <rect x="5" y="70" width="35" height="22" rx="5" fill="none" stroke="#ffffff22" stroke-width="1.5"/>
        <path d="M15,92 L12,100 L22,92" fill="none" stroke="#ffffff22" stroke-width="1.5"/>
        <!-- music note -->
        <path d="M80,65 L95,60 L95,75 Q95,80 90,80 Q85,80 85,75 Q85,70 90,70 L95,68" fill="none" stroke="#ffffff22" stroke-width="1.5"/>
        <!-- flower -->
        <circle cx="30" cy="100" r="5" fill="none" stroke="#ffffff22" stroke-width="1.5"/>
        <circle cx="22" cy="100" r="4" fill="none" stroke="#ffffff22" stroke-width="1.5"/>
        <circle cx="38" cy="100" r="4" fill="none" stroke="#ffffff22" stroke-width="1.5"/>
        <circle cx="26" cy="93" r="4" fill="none" stroke="#ffffff22" stroke-width="1.5"/>
        <circle cx="34" cy="93" r="4" fill="none" stroke="#ffffff22" stroke-width="1.5"/>
        <!-- lightning bolt -->
        <path d="M100,70 L93,85 L100,83 L93,100" fill="none" stroke="#ffffff22" stroke-width="1.5"/>
      </pattern>
    </defs>
    <rect width="1080" height="1920" fill="url(#p)"/>
  </svg>`,

  // 2. Classic WhatsApp Light Doodle
  'wa-light-doodle': () => `<svg xmlns="http://www.w3.org/2000/svg" width="1080" height="1920">
    <rect width="1080" height="1920" fill="#f0ebe3"/>
    <defs>
      <pattern id="p" x="0" y="0" width="120" height="120" patternUnits="userSpaceOnUse">
        <path d="M20,28 L30,18 Q37,11 44,18 Q51,11 58,18 L68,28 Q75,38 44,55 Q13,38 20,28Z" fill="none" stroke="#c8a882" stroke-width="1.5"/>
        <polygon points="100,10 103,20 114,20 105,27 108,37 100,31 92,37 95,27 86,20 97,20" fill="none" stroke="#c8a882" stroke-width="1.5"/>
        <rect x="5" y="70" width="35" height="22" rx="5" fill="none" stroke="#c8a882" stroke-width="1.5"/>
        <path d="M15,92 L12,100 L22,92" fill="none" stroke="#c8a882" stroke-width="1.5"/>
        <path d="M80,65 L95,60 L95,75 Q95,80 90,80 Q85,80 85,75 Q85,70 90,70 L95,68" fill="none" stroke="#c8a882" stroke-width="1.5"/>
        <circle cx="30" cy="100" r="5" fill="none" stroke="#c8a882" stroke-width="1.5"/>
        <circle cx="22" cy="100" r="4" fill="none" stroke="#c8a882" stroke-width="1.5"/>
        <circle cx="38" cy="100" r="4" fill="none" stroke="#c8a882" stroke-width="1.5"/>
        <circle cx="26" cy="93" r="4" fill="none" stroke="#c8a882" stroke-width="1.5"/>
        <circle cx="34" cy="93" r="4" fill="none" stroke="#c8a882" stroke-width="1.5"/>
        <path d="M100,70 L93,85 L100,83 L93,100" fill="none" stroke="#c8a882" stroke-width="1.5"/>
      </pattern>
    </defs>
    <rect width="1080" height="1920" fill="url(#p)"/>
  </svg>`,

  // 3. WhatsApp Green/Teal Hexagon
  'wa-teal-hex': () => `<svg xmlns="http://www.w3.org/2000/svg" width="1080" height="1920">
    <rect width="1080" height="1920" fill="#075E54"/>
    <defs>
      <pattern id="p" x="0" y="0" width="80" height="92" patternUnits="userSpaceOnUse">
        <polygon points="40,4 72,22 72,58 40,76 8,58 8,22" fill="none" stroke="#04443c" stroke-width="1.5"/>
        <polygon points="0,50 32,68 32,104" fill="none" stroke="#04443c" stroke-width="1.5"/>
        <polygon points="80,50 48,68 48,104" fill="none" stroke="#04443c" stroke-width="1.5"/>
      </pattern>
    </defs>
    <rect width="1080" height="1920" fill="url(#p)" opacity="0.8"/>
  </svg>`,

  // 4. Midnight Blue Diagonal Grid
  'wa-midnight-grid': () => `<svg xmlns="http://www.w3.org/2000/svg" width="1080" height="1920">
    <rect width="1080" height="1920" fill="#0a0f1e"/>
    <defs>
      <pattern id="p" x="0" y="0" width="40" height="40" patternUnits="userSpaceOnUse">
        <path d="M0,40 L40,0 M-5,5 L5,-5 M35,45 L45,35" stroke="#ffffff08" stroke-width="1"/>
      </pattern>
    </defs>
    <rect width="1080" height="1920" fill="url(#p)"/>
  </svg>`,

  // 5. Dark Charcoal Polka Dots
  'wa-polka-dots': () => `<svg xmlns="http://www.w3.org/2000/svg" width="1080" height="1920">
    <rect width="1080" height="1920" fill="#1c1c1c"/>
    <defs>
      <pattern id="p" x="0" y="0" width="36" height="36" patternUnits="userSpaceOnUse">
        <circle cx="18" cy="18" r="2.5" fill="#ffffff18"/>
      </pattern>
    </defs>
    <rect width="1080" height="1920" fill="url(#p)"/>
  </svg>`,

  // 6. Deep Purple Gradient Abstract
  'wa-purple-abstract': () => `<svg xmlns="http://www.w3.org/2000/svg" width="1080" height="1920">
    <defs>
      <radialGradient id="g1" cx="30%" cy="20%" r="70%">
        <stop offset="0%" stop-color="#3d1a6e"/>
        <stop offset="100%" stop-color="#0d0618"/>
      </radialGradient>
      <radialGradient id="g2" cx="80%" cy="80%" r="60%">
        <stop offset="0%" stop-color="#1a0a4e"/>
        <stop offset="100%" stop-color="#0d0618" stop-opacity="0"/>
      </radialGradient>
    </defs>
    <rect width="1080" height="1920" fill="url(#g1)"/>
    <rect width="1080" height="1920" fill="url(#g2)"/>
  </svg>`,

  // 7. Warm Olive/Army Green
  'wa-olive': () => `<svg xmlns="http://www.w3.org/2000/svg" width="1080" height="1920">
    <rect width="1080" height="1920" fill="#2d3319"/>
    <defs>
      <pattern id="p" x="0" y="0" width="60" height="60" patternUnits="userSpaceOnUse">
        <path d="M0,30 Q15,0 30,30 Q45,60 60,30" fill="none" stroke="#3d4520" stroke-width="1.5"/>
        <path d="M0,60 Q15,30 30,60" fill="none" stroke="#3d4520" stroke-width="1.5"/>
      </pattern>
    </defs>
    <rect width="1080" height="1920" fill="url(#p)"/>
  </svg>`,

  // 8. Classic Dark Geometric Triangles
  'wa-triangles': () => `<svg xmlns="http://www.w3.org/2000/svg" width="1080" height="1920">
    <rect width="1080" height="1920" fill="#111827"/>
    <defs>
      <pattern id="p" x="0" y="0" width="60" height="60" patternUnits="userSpaceOnUse">
        <polygon points="0,0 30,0 0,30" fill="#ffffff05"/>
        <polygon points="60,0 30,0 60,30" fill="#ffffff08"/>
        <polygon points="0,60 30,60 0,30" fill="#ffffff08"/>
        <polygon points="60,60 30,60 60,30" fill="#ffffff05"/>
        <polygon points="30,0 60,0 30,60 0,60" fill="#ffffff03"/>
      </pattern>
    </defs>
    <rect width="1080" height="1920" fill="url(#p)"/>
  </svg>`,

  // 9. Soft Pink WhatsApp Style
  'wa-soft-pink': () => `<svg xmlns="http://www.w3.org/2000/svg" width="1080" height="1920">
    <rect width="1080" height="1920" fill="#fce4ec"/>
    <defs>
      <pattern id="p" x="0" y="0" width="80" height="80" patternUnits="userSpaceOnUse">
        <circle cx="40" cy="40" r="15" fill="none" stroke="#f8bbd0" stroke-width="1.5"/>
        <circle cx="0" cy="0" r="10" fill="none" stroke="#f8bbd0" stroke-width="1"/>
        <circle cx="80" cy="0" r="10" fill="none" stroke="#f8bbd0" stroke-width="1"/>
        <circle cx="0" cy="80" r="10" fill="none" stroke="#f8bbd0" stroke-width="1"/>
        <circle cx="80" cy="80" r="10" fill="none" stroke="#f8bbd0" stroke-width="1"/>
      </pattern>
    </defs>
    <rect width="1080" height="1920" fill="url(#p)"/>
  </svg>`,

  // 10. Classic Dark Circuit Board
  'wa-circuit': () => `<svg xmlns="http://www.w3.org/2000/svg" width="1080" height="1920">
    <rect width="1080" height="1920" fill="#0d1117"/>
    <defs>
      <pattern id="p" x="0" y="0" width="100" height="100" patternUnits="userSpaceOnUse">
        <line x1="0" y1="50" x2="30" y2="50" stroke="#00ff9920" stroke-width="1"/>
        <line x1="70" y1="50" x2="100" y2="50" stroke="#00ff9920" stroke-width="1"/>
        <line x1="50" y1="0" x2="50" y2="30" stroke="#00ff9920" stroke-width="1"/>
        <line x1="50" y1="70" x2="50" y2="100" stroke="#00ff9920" stroke-width="1"/>
        <line x1="30" y1="50" x2="50" y2="30" stroke="#00ff9920" stroke-width="1"/>
        <line x1="50" y1="30" x2="70" y2="50" stroke="#00ff9920" stroke-width="1"/>
        <circle cx="50" cy="50" r="4" fill="none" stroke="#00ff9935" stroke-width="1.5"/>
        <circle cx="0" cy="0" r="3" fill="#00ff9910"/>
        <circle cx="100" cy="100" r="3" fill="#00ff9910"/>
        <circle cx="0" cy="100" r="3" fill="#00ff9910"/>
        <circle cx="100" cy="0" r="3" fill="#00ff9910"/>
      </pattern>
    </defs>
    <rect width="1080" height="1920" fill="url(#p)"/>
  </svg>`,

  // 11. Classic WhatsApp Dark Blue-Green
  'wa-dark-teal': () => `<svg xmlns="http://www.w3.org/2000/svg" width="1080" height="1920">
    <defs>
      <linearGradient id="g" x1="0%" y1="0%" x2="100%" y2="100%">
        <stop offset="0%" stop-color="#001a14"/>
        <stop offset="50%" stop-color="#00291e"/>
        <stop offset="100%" stop-color="#001a14"/>
      </linearGradient>
    </defs>
    <rect width="1080" height="1920" fill="url(#g)"/>
    <defs>
      <pattern id="p" x="0" y="0" width="50" height="50" patternUnits="userSpaceOnUse">
        <circle cx="25" cy="25" r="1.5" fill="#00af8420"/>
      </pattern>
    </defs>
    <rect width="1080" height="1920" fill="url(#p)"/>
  </svg>`,

  // 12. Rose Gold Elegant
  'wa-rose-gold': () => `<svg xmlns="http://www.w3.org/2000/svg" width="1080" height="1920">
    <defs>
      <linearGradient id="g" x1="0%" y1="0%" x2="100%" y2="100%">
        <stop offset="0%" stop-color="#1a0a12"/>
        <stop offset="40%" stop-color="#2e1520"/>
        <stop offset="100%" stop-color="#1a0a12"/>
      </linearGradient>
    </defs>
    <rect width="1080" height="1920" fill="url(#g)"/>
    <defs>
      <pattern id="p" x="0" y="0" width="80" height="80" patternUnits="userSpaceOnUse">
        <path d="M0,40 Q20,20 40,40 Q60,60 80,40" fill="none" stroke="#c0706018" stroke-width="1.5"/>
        <path d="M0,80 Q20,60 40,80" fill="none" stroke="#c0706018" stroke-width="1.5"/>
        <path d="M40,0 Q60,20 80,0" fill="none" stroke="#c0706018" stroke-width="1.5"/>
      </pattern>
    </defs>
    <rect width="1080" height="1920" fill="url(#p)"/>
  </svg>`,

};

// Write all SVGs
let count = 0;
for (const [name, svgFn] of Object.entries(backgrounds)) {
  const svgPath = path.join(dir, `${name}.svg`);
  fs.writeFileSync(svgPath, svgFn(), 'utf8');
  count++;
  console.log(`✓ ${name}.svg`);
}

console.log(`\n✅ Generated ${count} SVG backgrounds in:\n   ${dir}`);
console.log('\nℹ️  SVGs are served directly — no PNG conversion needed.');
console.log('   Next.js/Vite serves them from /public as static files.');
