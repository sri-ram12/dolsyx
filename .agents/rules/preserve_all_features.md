# Mandatory Rule: 1000% Strict Feature Preservation & Zero Regression

## Core Directive
Under NO circumstances should any existing feature, UI component, API endpoint, database field, encryption method, or Flutter mobile app capability be removed, skipped, commented out, or regress during any future edit or refactoring task.

## Verified App Features (Checkpoint 5441 & Beyond)
1. **End-to-End Encryption (E2EE)**: AES-GCM-256 / RSA cryptographic flow for messages, keys, and media attachments.
2. **WebRTC Audio & Video Calling**: Full offer/answer/ICE candidate signaling, active call screen, ringing UI, call timer, and mute/camera controls.
3. **Full-Screen Ringing & Notifications**: Android intent ringing screen, incoming call notification with ANSWER / DECLINE action buttons.
4. **WhatsApp-Style Location Cards**: Map tile previews, GPS coordinate sharing, and route tracing/navigation triggers.
5. **Real-Time Cross-Platform Poll Sync**: Multi-choice polls with live socket voting synchronization.
6. **Top 3-Dots Action Menu**: Copy text, autofill input, pin message, edit message, delete message (for everyone / for me), save to gallery.
7. **Direct Gallery Saver**: Native image and video downloading directly into Android device photo gallery (`gal` plugin).
8. **Call Logs & Talk Duration Tracking**: Recording call history, call type (audio/video/missed), start time, and duration in seconds.
9. **Bulk Media & View Once Media**: Multi-file gallery picker, View-Once photo/video self-destruct mechanism.
10. **Backend & Frontend Sync**: Full compatibility across Express backend (TypeScript, Socket.io, Prisma/Database) and Next.js / Flutter clients.

## Execution Rules for All Edits
1. **Audit Before Modifying**: Inspect existing function signatures, state models, and database schema before making any changes.
2. **Additive Changes Only**: Extend existing controllers, handlers, widgets, and routes rather than replacing or rewriting them from scratch.
3. **Cross-Platform Verification**: Verify that backend route changes do not break Flutter mobile app or Next.js web frontend contracts.
4. **Zero Feature Dropping**: Always verify every existing feature listed in `CHECKPOINT_5441.txt` remains intact after making edits.
