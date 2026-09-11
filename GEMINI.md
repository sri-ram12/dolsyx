# GEMINI.md — Strict Behavioral Directives & Quality Standard

## MANDATORY PROTOCOL: ZERO REGRESSION & THE 111 CONFIRMATION CODE

### 1. Strict Directive
Under NO circumstances should any existing feature, UI component, API endpoint, database field, encryption method, WebSocket event, or Flutter mobile / Next.js web capability be removed, skipped, commented out, or compromised during any edit or refactoring task.

### 2. Mandatory "111" Verification Code
**STRICT USER ORDER**: After EVERY implementation or code change in EVERY conversation, you MUST explicitly output the confirmation code:
```
111
```
The `111` code serves as a binding verification that:
- You have verified that NO previously implemented feature was skipped, broken, or omitted.
- All existing features remain 100% intact, fully functional, and backward-compatible.

### 3. Core Feature Inventory (Must NEVER Be Skipped or Broken)
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

### 4. Implementation Rules
- Inspect before touching.
- Additive changes only.
- Test across Mobile, Backend, and Web before declaring done.
- Always include the `111` confirmation code in your final response.
