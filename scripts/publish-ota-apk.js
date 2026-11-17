import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const SERVER_URL = process.env.SERVER_URL || 'https://dolsyx-app.onrender.com';

async function publishOta() {
  console.log('🚀 [DOLSYX OTA] Publishing latest Android APK...');

  const candidatePaths = [
    path.resolve(__dirname, '../mobile_app/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk'),
    path.resolve(__dirname, '../mobile_app/build/app/outputs/flutter-apk/app-release.apk'),
    path.resolve(__dirname, '../mobile_app/build/app/outputs/flutter-apk/app-arm64-v8a-debug.apk'),
    path.resolve(__dirname, '../mobile_app/build/app/outputs/flutter-apk/app-debug.apk'),
  ];

  let apkPath = candidatePaths.find(p => fs.existsSync(p));
  if (!apkPath) {
    console.error('❌ No compiled APK found. Please run: cd mobile_app && flutter build apk --release --split-per-abi');
    process.exit(1);
  }

  const stat = fs.statSync(apkPath);
  const sizeMb = (stat.size / (1024 * 1024)).toFixed(1);
  console.log(`📦 Found APK: ${path.basename(apkPath)} (${sizeMb} MB)`);

  const fileData = fs.readFileSync(apkPath);
  const blob = new Blob([fileData]);

  // 1. Upload to permanent CDN (Catbox)
  console.log('⏳ Uploading to permanent public CDN (Catbox)...');
  const catboxForm = new FormData();
  catboxForm.append('reqtype', 'fileupload');
  catboxForm.append('fileToUpload', blob, 'dolsyx-latest.apk');

  const catboxRes = await fetch('https://catbox.moe/user/api.php', {
    method: 'POST',
    body: catboxForm,
  });
  const cdnUrl = (await catboxRes.text()).trim();
  console.log('✅ Permanent CDN URL:', cdnUrl);

  // 2. Update local update-config.json
  const configPaths = [
    path.resolve(__dirname, '../backend/update-config.json'),
    path.resolve(__dirname, '../update-config.json'),
  ];

  for (const cPath of configPaths) {
    if (fs.existsSync(cPath)) {
      const cfg = JSON.parse(fs.readFileSync(cPath, 'utf8'));
      cfg.downloadUrl = cdnUrl;
      cfg.fileSizeMb = `${sizeMb} MB`;
      cfg.hasApk = true;
      fs.writeFileSync(cPath, JSON.stringify(cfg, null, 2), 'utf8');
      console.log(`📝 Updated ${path.basename(cPath)} with permanent CDN URL`);
    }
  }

  // 3. Publish to Render server if online
  try {
    const pubRes = await fetch(`${SERVER_URL}/api/app/publish-version`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        downloadUrl: cdnUrl,
        fileSizeMb: `${sizeMb} MB`,
        hasApk: true,
      }),
    });
    if (pubRes.ok) {
      console.log('✅ Notified live Render server with new download URL!');
    }
  } catch (_) {}

  // 4. Verify version endpoint
  const versionRes = await fetch(`${SERVER_URL}/api/app/version`);
  const versionData = await versionRes.json();
  console.log(`🎉 Version ${versionData.version} (Build ${versionData.buildNumber}) is now LIVE!`);
  console.log(`📲 Direct Download URL: ${cdnUrl}`);
  console.log('👉 Any phone running DOLSYX will now receive the update pop-up automatically!');
}

publishOta().catch(err => {
  console.error('❌ Error publishing OTA:', err);
  process.exit(1);
});
