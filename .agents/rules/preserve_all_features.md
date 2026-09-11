# Mandatory Rule: 1000% Strict Feature Preservation & Zero Regression (Code: 111)

## Core Directive
Under NO circumstances should ANY existing feature, UI component, API endpoint, database field, encryption method, WebSocket event, or Flutter mobile / Next.js web capability be removed, skipped, commented out, or regress during any edit or refactoring task.

## Mandatory "111" Verification Protocol
**STRICT USER ORDER**: After EVERY implementation or code change in EVERY conversation, the agent MUST explicitly output the confirmation code:
```
111
```
The `111` code serves as a binding verification that:
1. All previously implemented features were thoroughly inspected and verified.
2. ZERO existing features or tasks were skipped, broken, or omitted.
3. Every feature remains 100% intact, fully functional, and backward-compatible.

---

## Complete Verified Feature Inventory (Must NEVER Be Skipped or Broken)

1. **Linked Devices / QR Login (WhatsApp-Web Style)**:
   - Laptop QR code generation (`/login` with `&api=` origin and 120s TTL).
   - Mobile QR camera scan with instant pairing format detection.
   - Biometric confirmation (fingerprint/Face ID) on phone.
   - Real-time WebSocket + 1.5s fast polling status sync.
   - Independent 30-day scoped JWT issuance for laptop session.
   - Remote device management & one-tap device revocation.

2. **End-to-End Encryption (E2EE)**:
   - Full Double Ratchet / X3DH key exchange.
   - Web Crypto API Subtle native HKDF SHA-256 key derivation (`DOLSYX_CONV_V1_SALT_2025` + `conversation_ratchet_key`).
   - 4-Tier decryption fallback (Standard AES-GCM, Legacy AES-GCM, Mobile AES-CBC, Legacy Web AES-CBC).
   - Universal Base64 decoding with automatic padding recovery.
   - Client-side E2EE media pre-encryption & dual-cipher decryption.

3. **WebRTC Audio & Video Calling**:
   - Offer / answer / ICE candidate signaling via Socket.IO.
   - Active call screen, call timer, mute/unmute, and camera flip/toggle.
   - Ringing overlay & push call alerts.

4. **Full-Screen Ringing & Notifications**:
   - Android native intent incoming call screen with ANSWER / DECLINE actions.
   - Firebase Cloud Messaging (FCM) background push notifications.

5. **WhatsApp-Style Location Sharing**:
   - Map tile previews, GPS coordinate exchange, and direct route navigation.

6. **Real-Time Cross-Platform Polls**:
   - Multi-choice polls with live socket vote aggregation and sync.

7. **Message Action Menu (Top 3-Dots)**:
   - Copy text, autofill input, pin message, edit message, delete for everyone / for me, and star message.

8. **Direct Photo & Video Gallery Saver**:
   - Saving media directly into the device's native photo gallery (`gal` package).

9. **Call Logs & Talk Duration Tracking**:
   - Database tracking of call history, call type (audio/video/missed), start time, and duration in seconds.

10. **View-Once & Bulk Media**:
    - Multi-file gallery picker and View-Once photo/video self-destruct mechanism.

---

## Rules of Engagement for All Future Edits
1. **Audit Before Modifying**: Inspect existing function signatures, state models, and database schema before making changes.
2. **Additive Changes Only**: Extend existing controllers, handlers, widgets, and routes rather than replacing or rewriting them.
3. **Cross-Platform Verification**: Verify that backend changes preserve compatibility across both Flutter mobile and Next.js web clients.
4. **Always Conclude with `111`**: Conclude responses with the `111` confirmation code verifying zero regression.
