import React from "react";
import Link from "next/link";
import { FileText, ArrowLeft, CheckCircle2, AlertTriangle, ShieldCheck } from "lucide-react";

export const metadata = {
  title: "Terms of Service - DOLSYX",
  description: "Terms of Service and user agreement for DOLSYX.",
};

export default function TermsPage() {
  return (
    <div className="min-h-screen bg-[#0b141a] text-[#e9edef] overflow-y-auto px-4 py-8 md:py-16">
      <div className="max-w-4xl mx-auto">
        {/* Navigation */}
        <div className="mb-8 flex items-center justify-between border-b border-[#222d34] pb-4">
          <Link
            href="/"
            className="inline-flex items-center gap-2 text-[#00a884] hover:underline text-sm font-medium"
          >
            <ArrowLeft className="w-4 h-4" /> Back to DOLSYX
          </Link>
          <span className="text-xs text-[#8696a0]">Last Updated: January 2026</span>
        </div>

        <div className="text-center mb-12">
          <div className="inline-flex items-center justify-center p-3 rounded-full bg-[#00a884]/10 text-[#00a884] mb-4">
            <FileText className="w-10 h-10" />
          </div>
          <h1 className="text-3xl md:text-4xl font-bold tracking-tight text-white mb-3">
            Terms of Service
          </h1>
          <p className="text-[#8696a0] max-w-xl mx-auto text-sm md:text-base">
            Please read these Terms of Service carefully before using the DOLSYX mobile application or website.
          </p>
        </div>

        <div className="space-y-8 text-[#d1d7db] text-sm md:text-base leading-relaxed">
          <section className="bg-[#111b21] p-6 rounded-2xl border border-[#222d34]">
            <h2 className="text-xl font-semibold text-white mb-3 flex items-center gap-2">
              <CheckCircle2 className="w-5 h-5 text-[#00a884]" /> 1. Acceptance of Terms
            </h2>
            <p>
              By downloading, installing, or accessing the DOLSYX app or web platform, you agree to be bound by these Terms of Service and our Privacy Policy. If you do not agree, you must not use DOLSYX.
            </p>
          </section>

          <section className="bg-[#111b21] p-6 rounded-2xl border border-[#222d34]">
            <h2 className="text-xl font-semibold text-white mb-3 flex items-center gap-2">
              <ShieldCheck className="w-5 h-5 text-[#00a884]" /> 2. Eligibility & Account Security
            </h2>
            <p className="mb-2">
              You must be at least 13 years old (or the legal minimum age in your country) to create a DOLSYX account.
            </p>
            <p>
              You are responsible for maintaining the security of your device and authentication credentials. You agree to notify us immediately of any unauthorized access to your account.
            </p>
          </section>

          <section className="bg-[#111b21] p-6 rounded-2xl border border-[#222d34]">
            <h2 className="text-xl font-semibold text-white mb-3 flex items-center gap-2">
              <AlertTriangle className="w-5 h-5 text-amber-400" /> 3. Acceptable Use & Conduct
            </h2>
            <p className="mb-2">When using DOLSYX, you agree not to:</p>
            <ul className="list-disc list-inside space-y-1.5 ml-2">
              <li>Violate any local, national, or international laws or regulations.</li>
              <li>Send spam, bulk automated messages, or unauthorized advertisements.</li>
              <li>Distribute malware, malicious links, or harmful computer code.</li>
              <li>Harass, threaten, defame, or infringe on the privacy or intellectual property of other users.</li>
              <li>Attempt to reverse-engineer or disrupt DOLSYX servers and communication protocols.</li>
            </ul>
          </section>

          <section className="bg-[#111b21] p-6 rounded-2xl border border-[#222d34]">
            <h2 className="text-xl font-semibold text-white mb-3">4. Service Availability & Termination</h2>
            <p>
              We strive to provide uninterrupted service, but do not guarantee 100% uptime. We reserve the right to suspend or terminate accounts that violate these terms. You may terminate your account at any time via the in-app deletion setting or our web deletion portal.
            </p>
          </section>
        </div>

        {/* Footer */}
        <div className="mt-12 text-center text-xs text-[#8696a0] border-t border-[#222d34] pt-6 flex flex-wrap justify-center gap-6">
          <Link href="/privacy" className="hover:text-white transition-colors">Privacy Policy</Link>
          <Link href="/delete-account" className="hover:text-white transition-colors">Delete Account</Link>
          <span>&copy; {new Date().getFullYear()} DOLSYX. All rights reserved.</span>
        </div>
      </div>
    </div>
  );
}
