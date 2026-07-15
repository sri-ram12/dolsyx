const fs = require('fs');
const https = require('https');
const path = require('path');

// New, hand-picked stunning wallpapers for the chat background picker
const backgrounds = [
  // Milky Way Galaxy
  { id: "1419242268926-1bcdf39d2d2c", name: "bg-galaxy" },
  // Northern Lights (Aurora Borealis)
  { id: "1531366936337-7c912a4589a7", name: "bg-northern-lights" },
  // Cherry Blossom in bloom
  { id: "1522383225754-adde995ac847", name: "bg-cherry-blossom" },
  // Cyberpunk / Neon City at night
  { id: "1477959858617-67f85cf4f1df", name: "bg-cyberpunk-city" },
  // Mountain Sunset with orange sky
  { id: "1506905925346-21bda4d32df4", name: "bg-mountain-sunset" },
  // Misty Forest Path
  { id: "1448375240890-4208d36f4af0", name: "bg-forest-path" },
  // Tropical Ocean / Crystal Clear Water
  { id: "1505118380757-91f5f5632de0", name: "bg-tropical-ocean" },
  // Dark Fluid Abstract Art
  { id: "1557672172-1542acf31b45", name: "bg-dark-abstract" },
  // Autumn Bokeh (warm golden leaves)
  { id: "1507003211169-0a1dd7228f2d", name: "bg-autumn-bokeh" },
  // Rainy Window with city lights bokeh
  { id: "1501854140801-50d01698950b", name: "bg-rainy-window" },
];

const dir = path.join(__dirname, 'frontend/public/chat-backgrounds');
if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });

console.log("Starting downloads...");
console.log(`Saving to: ${dir}\n`);

let completed = 0;
let failed = 0;

function download(url, dest, name, attempt) {
  attempt = attempt || 1;
  const file = fs.createWriteStream(dest);

  const req = https.get(url, (response) => {
    if (response.statusCode === 301 || response.statusCode === 302) {
      file.close();
      fs.unlinkSync(dest);
      download(response.headers.location, dest, name, attempt);
      return;
    }
    if (response.statusCode !== 200) {
      file.close();
      fs.unlinkSync(dest);
      console.error(`✗ ${name} — HTTP ${response.statusCode}`);
      failed++;
      return;
    }
    response.pipe(file);
    file.on('finish', () => {
      file.close();
      completed++;
      console.log(`✓ ${name}.jpg  (${completed}/${backgrounds.length})`);
      if (completed + failed === backgrounds.length) {
        console.log(`\nDone! ${completed} downloaded, ${failed} failed.`);
      }
    });
  });

  req.on('error', (err) => {
    file.close();
    try { fs.unlinkSync(dest); } catch (_) {}
    if (attempt < 3) {
      console.warn(`⟳ Retrying ${name}... (attempt ${attempt + 1})`);
      setTimeout(() => download(url, dest, name, attempt + 1), 1500);
    } else {
      console.error(`✗ ${name} — ${err.message}`);
      failed++;
    }
  });
}

backgrounds.forEach(({ id, name }) => {
  const url = `https://images.unsplash.com/photo-${id}?w=1080&q=85&auto=format&fit=crop`;
  const dest = path.join(dir, `${name}.jpg`);
  download(url, dest, name);
});
