import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  ...(process.env.VERCEL ? {} : { output: "standalone" }),
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
    // On Vercel Services, top-level vercel.json rewrites route /api, /socket.io, and /uploads to the backend service
    if (process.env.VERCEL) {
      return [];
    }
    const envApi = process.env.NEXT_PUBLIC_API_URL || process.env.INTERNAL_BACKEND_URL || process.env.BACKEND_URL;
    const backendUrl = (envApi && !envApi.includes("onrender.com") ? envApi : "http://localhost:4000").replace(/\/+$/, "");
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
