const fs = require('fs');
const https = require('https');
const path = require('path');

// Only re-downloading the 4 that got 404 — with corrected Unsplash IDs
const backgrounds = [
  // Milky Way / Galaxy (corrected)
  { id: "1462332420958-a05d1e002ef2", name: "bg-galaxy" },
  // Cherry Blossom (corrected)
  { id: "1516912481800-3f0a0e4a86e5", name: "bg-cherry-blossom" },
  // Misty Forest Path (corrected)
  { id: "1448375240890-4208d36f4af0&w=1080", name: "bg-forest-path", correctedUrl: "https://images.unsplash.com/photo-1448375240890-4208d36f4af0?w=1080&q=85&auto=format&fit=crop" },
  // Dark Fluid Abstract Art (corrected)
  { id: "1558618666-fcd25c85cd64", name: "bg-dark-abstract" },
];

const dir = path.join(__dirname, 'frontend/public/chat-backgrounds');
if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });

console.log("Re-downloading failed images with corrected IDs...\n");

let completed = 0;
let failed = 0;
const total = backgrounds.length;

function download(url, dest, name, attempt) {
  attempt = attempt || 1;
  const file = fs.createWriteStream(dest);

  const req = https.get(url, (response) => {
    if (response.statusCode === 301 || response.statusCode === 302) {
      file.close();
      try { fs.unlinkSync(dest); } catch (_) {}
      download(response.headers.location, dest, name, attempt);
      return;
    }
    if (response.statusCode !== 200) {
      file.close();
      try { fs.unlinkSync(dest); } catch (_) {}
      console.error(`✗ ${name} — HTTP ${response.statusCode}`);
      failed++;
      if (completed + failed === total) {
        console.log(`\nDone! ${completed} downloaded, ${failed} failed.`);
      }
      return;
    }
    response.pipe(file);
    file.on('finish', () => {
      file.close();
      completed++;
      console.log(`✓ ${name}.jpg  (${completed}/${total})`);
      if (completed + failed === total) {
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

backgrounds.forEach(({ id, name, correctedUrl }) => {
  const url = correctedUrl || `https://images.unsplash.com/photo-${id}?w=1080&q=85&auto=format&fit=crop`;
  const dest = path.join(dir, `${name}.jpg`);
  download(url, dest, name);
});
