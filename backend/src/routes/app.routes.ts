import { Router } from "express";
import path from "path";
import fs from "fs";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const router = Router();

import multer from "multer";

const apkUpload = multer({
  storage: multer.diskStorage({
    destination: (req, file, cb) => {
      const dir = path.resolve(process.cwd(), "uploads");
      if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
      cb(null, dir);
    },
    filename: (req, file, cb) => {
      cb(null, "app-latest.apk");
    },
  }),
  limits: { fileSize: 300 * 1024 * 1024 },
});

// Candidate paths for compiled APK (prefers uploads directory, then local outputs)
const getApkPath = (): string | null => {
  // 1. First, check uploads directory: prefer explicit "app-latest.apk", then newest APK by mtime
  const uploadsDirs = [
    path.resolve(process.cwd(), "uploads"),
    path.resolve(process.cwd(), "../uploads"),
    path.resolve(__dirname, "../../uploads"),
  ];

  for (const uDir of uploadsDirs) {
    if (fs.existsSync(uDir)) {
      const explicitLatest = path.join(uDir, "app-latest.apk");
      if (fs.existsSync(explicitLatest)) {
        return explicitLatest;
      }
      const apks = fs
        .readdirSync(uDir)
        .filter((f) => f.endsWith(".apk"))
        .map((f) => path.join(uDir, f))
        .sort((a, b) => fs.statSync(b).mtimeMs - fs.statSync(a).mtimeMs);
      if (apks.length > 0) {
        return apks[0];
      }
    }
  }

  const candidates = [
    path.resolve(process.cwd(), "uploads/app-latest.apk"),
    path.resolve(process.cwd(), "app-latest.apk"),
    path.resolve(process.cwd(), "../app-latest.apk"),
    path.resolve(process.cwd(), "uploads/app-release.apk"),
    path.resolve(process.cwd(), "app-release.apk"),
    path.resolve(process.cwd(), "../app-release.apk"),
    path.resolve(process.cwd(), "uploads/app-arm64-v8a-debug.apk"),
    path.resolve(process.cwd(), "uploads/app-debug.apk"),
    path.resolve(process.cwd(), "app-arm64-v8a-debug.apk"),
    path.resolve(process.cwd(), "app-debug.apk"),
    path.resolve(process.cwd(), "../app-arm64-v8a-debug.apk"),
    path.resolve(process.cwd(), "../app-debug.apk"),
    path.resolve(process.cwd(), "mobile_app/build/app/outputs/flutter-apk/app-arm64-v8a-debug.apk"),
    path.resolve(process.cwd(), "mobile_app/build/app/outputs/flutter-apk/app-armeabi-v7a-debug.apk"),
    path.resolve(process.cwd(), "mobile_app/build/app/outputs/flutter-apk/app-release.apk"),
    path.resolve(process.cwd(), "mobile_app/build/app/outputs/flutter-apk/app-debug.apk"),
    path.resolve(process.cwd(), "mobile_app/build/app/outputs/apk/release/app-release.apk"),
    path.resolve(process.cwd(), "../mobile_app/build/app/outputs/flutter-apk/app-arm64-v8a-debug.apk"),
    path.resolve(process.cwd(), "../mobile_app/build/app/outputs/flutter-apk/app-release.apk"),
    path.resolve(process.cwd(), "../mobile_app/build/app/outputs/flutter-apk/app-debug.apk"),
  ];

  for (const candidate of candidates) {
    if (fs.existsSync(candidate)) {
      return candidate;
    }
  }
  return null;
};

interface UpdateConfig {
  version: string;
  buildNumber: number;
  minimumSupportedVersion?: string;
  minimumSupportedBuild?: number;
  releaseNotes: string;
  downloadUrl?: string;
  fileSizeMb?: string;
  hasApk?: boolean;
}

const getUpdateConfigFile = (): string => {
  const localConfig = path.resolve(process.cwd(), "update-config.json");
  if (fs.existsSync(localConfig)) return localConfig;
  const parentConfig = path.resolve(process.cwd(), "../update-config.json");
  if (fs.existsSync(parentConfig)) return parentConfig;
  return localConfig;
};

const getUpdateConfig = (): UpdateConfig => {
  try {
    const configPath = getUpdateConfigFile();
    if (fs.existsSync(configPath)) {
      return JSON.parse(fs.readFileSync(configPath, "utf-8"));
    }
  } catch (_) {}
  return {
    version: process.env.APP_VERSION || "1.0.4",
    buildNumber: parseInt(process.env.APP_BUILD_NUMBER || "4", 10),
    minimumSupportedVersion: process.env.APP_MIN_SUPPORTED_VERSION || "1.0.0",
    minimumSupportedBuild: parseInt(process.env.APP_MIN_SUPPORTED_BUILD || "1", 10),
    releaseNotes:
      process.env.APP_RELEASE_NOTES ||
      "Automatic real-time OTA update pop-up on launch, WhatsApp-style media download pill with KB/MB indicators on images, videos, audio & documents.",
    downloadUrl: process.env.APK_DOWNLOAD_URL || "/api/app/download",
    fileSizeMb: "117.5 MB",
    hasApk: true,
  };
};

// ── POST /api/app/upload-apk ──
router.post("/upload-apk", apkUpload.single("apk"), (req, res) => {
  const apkPath = getApkPath();
  res.json({
    success: true,
    message: "APK uploaded successfully to server.",
    path: apkPath,
    hasApk: apkPath !== null,
  });
});

// ── POST /api/app/publish-version ──
router.post("/publish-version", (req, res) => {
  try {
    const { version, buildNumber, minimumSupportedVersion, minimumSupportedBuild, releaseNotes, downloadUrl, fileSizeMb, hasApk } = req.body;
    const current = getUpdateConfig();
    const updated: UpdateConfig = {
      version: version || current.version,
      buildNumber: buildNumber ? Number(buildNumber) : current.buildNumber + 1,
      minimumSupportedVersion: minimumSupportedVersion || current.minimumSupportedVersion || "1.0.0",
      minimumSupportedBuild: minimumSupportedBuild ? Number(minimumSupportedBuild) : (current.minimumSupportedBuild || 1),
      releaseNotes: releaseNotes || current.releaseNotes,
      downloadUrl: downloadUrl || current.downloadUrl,
      fileSizeMb: fileSizeMb || current.fileSizeMb,
      hasApk: hasApk !== undefined ? !!hasApk : true,
    };
    fs.writeFileSync(getUpdateConfigFile(), JSON.stringify(updated, null, 2), "utf-8");
    res.json({ success: true, message: "Version published successfully", config: updated });
  } catch (err: any) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ── GET /api/app/version ──
router.get("/version", (req, res) => {
  try {
    // Prevent intermediate HTTP caching
    res.setHeader("Cache-Control", "no-store, no-cache, must-revalidate, proxy-revalidate");
    res.setHeader("Pragma", "no-cache");
    res.setHeader("Expires", "0");
    res.setHeader("Surrogate-Control", "no-store");

    const config = getUpdateConfig();
    const apkPath = getApkPath();
    let fileSizeBytes = 0;
    let fileSizeMb = config.fileSizeMb || "117.5 MB";
    let lastModified = new Date().toISOString();

    if (apkPath && fs.existsSync(apkPath)) {
      const stat = fs.statSync(apkPath);
      fileSizeBytes = stat.size;
      fileSizeMb = `${(stat.size / (1024 * 1024)).toFixed(1)} MB`;
      lastModified = stat.mtime.toISOString();
    }

    const hasApk = apkPath !== null || !!process.env.APK_DOWNLOAD_URL || config.hasApk !== false;
    let rawDownloadUrl = process.env.APK_DOWNLOAD_URL || config.downloadUrl || "/api/app/download";

    // Ensure absolute URL so client startsWith('http') is true and never concatenates /api/api
    let downloadUrl = rawDownloadUrl;
    if (!downloadUrl.startsWith("http://") && !downloadUrl.startsWith("https://")) {
      const host = req.get("host") || "dolsyx-app.onrender.com";
      const proto = req.get("x-forwarded-proto") || req.protocol || "https";
      const cleanPath = downloadUrl.startsWith("/") ? downloadUrl : `/${downloadUrl}`;
      downloadUrl = `${proto}://${host}${cleanPath}`;
    }

    // Current build version info with full structured metadata
    res.json({
      success: true,
      version: config.version || "1.0.4",
      buildNumber: config.buildNumber || 4,
      minimumSupportedVersion: config.minimumSupportedVersion || "1.0.0",
      minimumSupportedBuild: config.minimumSupportedBuild || 1,
      updateRequired: false,
      releaseNotes: config.releaseNotes,
      downloadUrl,
      fileSizeBytes,
      fileSizeMb,
      updatedAt: lastModified,
      hasApk,
    });
  } catch (error) {
    console.error("[App Update] Failed to get version:", error);
    res.status(500).json({ success: false, message: "Failed to retrieve app version info" });
  }
});

// ── GET /api/app/download ──
router.get("/download", (req, res) => {
  try {
    const config = getUpdateConfig();
    const remoteUrl = process.env.APK_DOWNLOAD_URL || (config.downloadUrl?.startsWith("http") ? config.downloadUrl : null);
    if (remoteUrl) {
      return res.redirect(remoteUrl);
    }

    const apkPath = getApkPath();
    if (!apkPath || !fs.existsSync(apkPath)) {
      return res.status(404).json({
        success: false,
        message: "No compiled APK found on server. Please upload APK or specify download URL.",
      });
    }

    const filename = "dolsyx-latest.apk";
    res.setHeader("Cache-Control", "no-store, no-cache, must-revalidate, proxy-revalidate");
    res.setHeader("Pragma", "no-cache");
    res.setHeader("Expires", "0");
    res.setHeader("Content-Type", "application/vnd.android.package-archive");
    res.setHeader("Content-Disposition", `attachment; filename="${filename}"`);
    return res.download(apkPath, filename);
  } catch (error) {
    console.error("[App Download] Failed to stream APK:", error);
    return res.status(500).json({ success: false, message: "Failed to download APK" });
  }
});

export default router;
