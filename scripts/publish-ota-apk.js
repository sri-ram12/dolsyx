const fs = require('fs');
const path = require('path');

const SERVER_URL = process.env.SERVER_URL || 'https://dolsyx-app.onrender.com';

async function publishOta() {
  console.log('🚀 [DOLSYX OTA] Publishing latest Android APK to Render server...');

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
  const form = new FormData();
  form.append('apk', blob, 'app-latest.apk');

  console.log(`⏳ Uploading to ${SERVER_URL}/api/app/upload-apk ...`);
  const uploadRes = await fetch(`${SERVER_URL}/api/app/upload-apk`, {
    method: 'POST',
    body: form,
  });

  const uploadData = await uploadRes.json();
  if (!uploadRes.ok || !uploadData.success) {
    console.error('❌ Failed to upload APK:', uploadData);
    process.exit(1);
  }

  console.log('✅ APK uploaded successfully to server!');

  // Check version endpoint
  const versionRes = await fetch(`${SERVER_URL}/api/app/version`);
  const versionData = await versionRes.json();
  console.log(`🎉 Version ${versionData.version} (Build ${versionData.buildNumber}) is now LIVE!`);
  console.log(`📲 Download URL: ${versionData.downloadUrl}`);
  console.log('👉 Any phone running DOLSYX will now receive the update pop-up automatically!');
}

publishOta().catch(err => {
  console.error('❌ Error publishing OTA:', err);
  process.exit(1);
});
