import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  output: "standalone",
  // Allow public tunnel URLs for dev testing
  allowedDevOrigins: [
    "*.serveousercontent.com",
    "*.loca.lt",
    "*.ngrok.io",
    "*.ngrok-free.app",
    "*.trycloudflare.com",
    "*.lhr.life",
  ],
  images: {
    // Allow images from any hostname (covers tunnels, local network, etc.)
    remotePatterns: [
      {
        protocol: "http",
        hostname: "**",
      },
      {
        protocol: "https",
        hostname: "**",
      },
    ],
    unoptimized: true,
  },
  async rewrites() {
    const backendUrl = (process.env.NEXT_PUBLIC_API_URL || process.env.BACKEND_URL || "https://dolsyx-app.onrender.com").replace(/\/+$/, "");
    return [
      {
        source: "/api/:path*",
        destination: `${backendUrl}/api/:path*`,
      },
      {
        source: "/socket.io/:path*",
        destination: `${backendUrl}/socket.io/:path*`,
      },
      {
        source: "/uploads/:path*",
        destination: `${backendUrl}/uploads/:path*`,
      },
    ];
  },
};

export default nextConfig;
