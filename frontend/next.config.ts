import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  output: "standalone",
  // Allow public tunnel URLs for dev testing
  allowedDevOrigins: [
    "*.serveousercontent.com",
    "*.loca.lt",
    "*.ngrok.io",
    "*.ngrok-free.app",
  ],
};

export default nextConfig;
