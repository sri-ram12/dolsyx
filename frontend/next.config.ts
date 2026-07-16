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
    return [
      {
        source: "/api/:path*",
        destination: "http://localhost:4000/api/:path*",
      },
      {
        source: "/socket.io/:path*",
        destination: "http://localhost:4000/socket.io/:path*",
      },
      {
        source: "/uploads/:path*",
        destination: "http://localhost:4000/uploads/:path*",
      },
    ];
  },
};

export default nextConfig;
