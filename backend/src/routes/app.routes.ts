import { Router } from "express";
import path from "path";
import fs from "fs";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const router = Router();

// Candidate paths for compiled APK
const getApkPath = (): string | null => {
  const candidates = [
    path.resolve(process.cwd(), "app-debug.apk"),
    path.resolve(process.cwd(), "../app-debug.apk"),
    path.resolve(process.cwd(), "mobile_app/build/app/outputs/flutter-apk/app-debug.apk"),
    path.resolve(process.cwd(), "../mobile_app/build/app/outputs/flutter-apk/app-debug.apk"),
    path.resolve(__dirname, "../../../app-debug.apk"),
    path.resolve(__dirname, "../../app-debug.apk"),
  ];

  for (const candidate of candidates) {
    if (fs.existsSync(candidate)) {
      return candidate;
    }
  }
  return null;
};

// ── GET /api/app/version ──
router.get("/version", (req, res) => {
  try {
    const apkPath = getApkPath();
    let fileSizeBytes = 0;
    let fileSizeMb = "0";
    let lastModified = new Date().toISOString();

    if (apkPath) {
      const stat = fs.statSync(apkPath);
      fileSizeBytes = stat.size;
      fileSizeMb = (stat.size / (1024 * 1024)).toFixed(1);
      lastModified = stat.mtime.toISOString();
    }

    // Current build version info
    res.json({
      success: true,
      version: "1.0.2",
      buildNumber: 2,
      releaseNotes: "In-app OTA self-updater, 200MB video sharing, performance and reliability updates.",
      downloadUrl: "/api/app/download",
      fileSizeBytes,
      fileSizeMb: `${fileSizeMb} MB`,
      updatedAt: lastModified,
      hasApk: apkPath !== null,
    });
  } catch (error) {
    console.error("[App Update] Failed to get version:", error);
    res.status(500).json({ success: false, message: "Failed to retrieve app version info" });
  }
});

// ── GET /api/app/download ──
router.get("/download", (req, res) => {
  try {
    const apkPath = getApkPath();
    if (!apkPath) {
      return res.status(404).json({
        success: false,
        message: "No compiled APK found on server. Please compile mobile_app first.",
      });
    }

    const filename = "dolsyx-latest.apk";
    res.setHeader("Content-Type", "application/vnd.android.package-archive");
    res.setHeader("Content-Disposition", `attachment; filename="${filename}"`);
    return res.download(apkPath, filename);
  } catch (error) {
    console.error("[App Download] Failed to stream APK:", error);
    return res.status(500).json({ success: false, message: "Failed to download APK" });
  }
});

export default router;
