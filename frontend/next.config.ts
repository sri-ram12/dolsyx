import type { NextConfig } from "next";
import path from "path";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const nextConfig: NextConfig = {
  output: "standalone",
  // Fix workspace root detection with multiple lockfiles
  outputFileTracingRoot: path.join(__dirname, "../"),
  // Allow public tunnel URLs for dev testing
  allowedDevOrigins: [
    "ae93390ba332db0e-103-168-80-66.serveousercontent.com",
    "*.serveousercontent.com",
    "*.loca.lt",
    "*.ngrok.io",
  ],
};

export default nextConfig;
