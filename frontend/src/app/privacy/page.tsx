import React from "react";
import Link from "next/link";
import { Shield, Lock, Eye, Trash2, Smartphone, Mail, ArrowLeft } from "lucide-react";

export const metadata = {
  title: "Privacy Policy - DOLSYX",
  description: "Privacy Policy for DOLSYX messaging and calling platform.",
};

export default function PrivacyPage() {
  return (
    <div className="min-h-screen bg-[#0b141a] text-[#e9edef] overflow-y-auto px-4 py-8 md:py-16">
      <div className="max-w-4xl mx-auto">
        {/* Navigation / Header */}
        <div className="mb-8 flex items-center justify-between border-b border-[#222d34] pb-4">
          <Link
            href="/"
            className="inline-flex items-center gap-2 text-[#00a884] hover:underline text-sm font-medium"
          >
            <ArrowLeft className="w-4 h-4" /> Back to DOLSYX
          </Link>
          <span className="text-xs text-[#8696a0]">Effective Date: January 1, 2026</span>
        </div>

        <div className="text-center mb-12">
          <div className="inline-flex items-center justify-center p-3 rounded-full bg-[#00a884]/10 text-[#00a884] mb-4">
            <Shield className="w-10 h-10" />
          </div>
          <h1 className="text-3xl md:text-4xl font-bold tracking-tight text-white mb-3">
            DOLSYX Privacy Policy
          </h1>
          <p className="text-[#8696a0] max-w-xl mx-auto text-sm md:text-base">
            Your privacy and security are our top priorities. Learn how DOLSYX handles, protects, and gives you control over your personal data.
          </p>
        </div>

        {/* Content Sections */}
        <div className="space-y-10 text-[#d1d7db] text-sm md:text-base leading-relaxed">
          {/* 1. Overview */}
          <section className="bg-[#111b21] p-6 rounded-2xl border border-[#222d34]">
            <h2 className="text-xl font-semibold text-white mb-3 flex items-center gap-2">
              <Lock className="w-5 h-5 text-[#00a884]" /> 1. End-to-End Encryption & Core Principles
            </h2>
            <p className="mb-3">
              DOLSYX provides private, real-time messaging, voice, and video communication. Messages and media sent between DOLSYX users utilize <strong>End-to-End Encryption (E2EE)</strong>.
            </p>
            <p>
              This means only you and the recipient can read or listen to what is sent. Nobody in between—not even DOLSYX servers or personnel—can access or decrypt your message contents or private keys.
            </p>
          </section>

          {/* 2. Information We Collect */}
          <section className="bg-[#111b21] p-6 rounded-2xl border border-[#222d34]">
            <h2 className="text-xl font-semibold text-white mb-3 flex items-center gap-2">
              <Eye className="w-5 h-5 text-[#00a884]" /> 2. Information We Collect
            </h2>
            <ul className="list-disc list-inside space-y-2 ml-2">
              <li>
                <strong>Account Information:</strong> When you register for DOLSYX, you provide an email address or phone number, display name (username), and optional profile photo and status bio.
              </li>
              <li>
                <strong>Contacts & Address Book:</strong> With your permission, DOLSYX accesses your contacts solely to detect which of your contacts are also using DOLSYX. We do not store or sell your address book.
              </li>
              <li>
                <strong>Device & Notification Tokens:</strong> We collect device identifiers and Firebase Cloud Messaging (FCM) tokens strictly to deliver incoming message and call push notifications.
              </li>
              <li>
                <strong>Call & Connection Metadata:</strong> Technical diagnostic logs (IP address, connection timestamp) are temporarily processed to route WebRTC peer-to-peer calls.
              </li>
            </ul>
          </section>

          {/* 3. Device Permissions */}
          <section className="bg-[#111b21] p-6 rounded-2xl border border-[#222d34]">
            <h2 className="text-xl font-semibold text-white mb-3 flex items-center gap-2">
              <Smartphone className="w-5 h-5 text-[#00a884]" /> 3. Device Permissions & Usage
            </h2>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4 mt-3">
              <div className="p-4 bg-[#0b141a] rounded-xl border border-[#202c33]">
                <h3 className="font-semibold text-white mb-1">Camera & Microphone</h3>
                <p className="text-xs text-[#8696a0]">
                  Required for real-time video/voice calling, sending voice notes, and taking photos/videos directly in chat.
                </p>
              </div>
              <div className="p-4 bg-[#0b141a] rounded-xl border border-[#202c33]">
                <h3 className="font-semibold text-white mb-1">Photos, Videos & Media</h3>
                <p className="text-xs text-[#8696a0]">
                  Allows you to select and share photos, videos, and documents with contacts and save received media to your gallery.
                </p>
              </div>
              <div className="p-4 bg-[#0b141a] rounded-xl border border-[#202c33]">
                <h3 className="font-semibold text-white mb-1">Notifications & Full Screen Intent</h3>
                <p className="text-xs text-[#8696a0]">
                  Ensures you receive immediate alerts for incoming messages and allows full-screen incoming call UI when your device is locked.
                </p>
              </div>
              <div className="p-4 bg-[#0b141a] rounded-xl border border-[#202c33]">
                <h3 className="font-semibold text-white mb-1">Biometrics / Fingerprint</h3>
                <p className="text-xs text-[#8696a0]">
                  Used solely on-device for the App Lock feature. Biometric data never leaves your device or touches DOLSYX servers.
                </p>
              </div>
            </div>
          </section>

          {/* 4. Data Sharing & Third Parties */}
          <section className="bg-[#111b21] p-6 rounded-2xl border border-[#222d34]">
            <h2 className="text-xl font-semibold text-white mb-3">4. Third-Party Services & Data Sharing</h2>
            <p className="mb-2">
              We do <strong>not</strong> sell, rent, or monetize your personal data or message history. We only interface with trusted infrastructure providers required to operate the service:
            </p>
            <ul className="list-disc list-inside space-y-1 ml-2 text-sm">
              <li><strong>Google Firebase:</strong> Used for secure push notification delivery.</li>
              <li><strong>Hosting & Server Infrastructure:</strong> Managed cloud servers for routing encrypted WebSockets.</li>
            </ul>
          </section>

          {/* 5. Account and Data Deletion */}
          <section className="bg-[#111b21] p-6 rounded-2xl border border-[#00a884]/30">
            <h2 className="text-xl font-semibold text-white mb-3 flex items-center gap-2">
              <Trash2 className="w-5 h-5 text-red-400" /> 5. Account & Data Deletion Rights
            </h2>
            <p className="mb-4">
              In full compliance with Google Play Store and international data privacy laws (GDPR, CCPA), you have complete ownership of your data and can permanently delete your account at any time:
            </p>
            <div className="space-y-3">
              <div className="p-4 bg-[#0b141a] rounded-xl">
                <p className="font-medium text-white mb-1">📱 In the Mobile App:</p>
                <p className="text-xs text-[#8696a0]">
                  Go to <strong>Settings &gt; Account &gt; Delete My Account</strong>. Confirming deletion immediately wipes your profile, cryptographic keys, contacts, and message records.
                </p>
              </div>
              <div className="p-4 bg-[#0b141a] rounded-xl">
                <p className="font-medium text-white mb-1">🌐 On the Web (Without App Installed):</p>
                <p className="text-xs text-[#8696a0] mb-2">
                  You can submit a deletion request directly via our dedicated deletion portal:
                </p>
                <Link
                  href="/delete-account"
                  className="inline-flex items-center gap-1.5 text-xs text-[#00a884] font-semibold hover:underline"
                >
                  <Trash2 className="w-3.5 h-3.5" /> Visit Account Deletion Request Page &rarr;
                </Link>
              </div>
            </div>
          </section>

          {/* 6. Contact Us */}
          <section className="bg-[#111b21] p-6 rounded-2xl border border-[#222d34]">
            <h2 className="text-xl font-semibold text-white mb-3 flex items-center gap-2">
              <Mail className="w-5 h-5 text-[#00a884]" /> 6. Contact Information
            </h2>
            <p className="mb-2">
              If you have any questions or privacy inquiries regarding this policy or DOLSYX services, please contact:
            </p>
            <p className="text-sm font-mono text-[#00a884]">
              support@dolsyx.com
            </p>
          </section>
        </div>

        {/* Footer */}
        <div className="mt-12 text-center text-xs text-[#8696a0] border-t border-[#222d34] pt-6 flex flex-wrap justify-center gap-6">
          <Link href="/terms" className="hover:text-white transition-colors">Terms of Service</Link>
          <Link href="/delete-account" className="hover:text-white transition-colors">Delete Account</Link>
          <span>&copy; {new Date().getFullYear()} DOLSYX. All rights reserved.</span>
        </div>
      </div>
    </div>
  );
}
