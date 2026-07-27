import type { Metadata, Viewport } from "next";
import "./globals.css";

import { AuthProvider } from "@/context/auth-context";
import { SocketProvider } from "@/context/socket-context";
import { ThemeProvider } from "@/context/theme-context";
import { ToastProvider } from "@/context/toast-context";

const geistSans = {
  variable: "font-sans",
};

const geistMono = {
  variable: "font-mono",
};

export const metadata: Metadata = {
  title: "DOLSYX - Premium Real-time Messaging",
  description: "Experience premium, modern, real-time messaging with DOLSYX.",
  manifest: "/manifest.json",
  appleWebApp: {
    capable: true,
    statusBarStyle: "black-translucent",
    title: "DOLSYX",
  },
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  maximumScale: 1,
  userScalable: false,
  viewportFit: "cover",
  interactiveWidget: "resizes-content",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html
      lang="en"
      className={`${geistSans.variable} ${geistMono.variable} antialiased`}
      style={{ height: "100dvh" }}
    >
      <body
        className="flex flex-col bg-[var(--theme-bg-app)] text-[var(--theme-text-primary)] transition-colors duration-300 selection:bg-[var(--theme-accent)] selection:text-[var(--theme-accent-text)] safe-top safe-bottom safe-left safe-right"
        style={{ height: "100dvh", overscrollBehavior: "none" }}
      >
        <ToastProvider>
          <ThemeProvider>
            <AuthProvider>
              <SocketProvider>{children}</SocketProvider>
            </AuthProvider>
          </ThemeProvider>
        </ToastProvider>
      </body>
    </html>
  );
}
