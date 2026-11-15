# VeriLens AI — Multimodal Fake Image & Voice Deepfake Detection

Cross-platform **Flutter (Android APK + Chrome Web)** forensic platform backed by a **Vercel Node.js / Express API** (`https://verilens-api-delta.vercel.app`) for detecting **AI-generated images**, **deepfake / cloned voices**, and **misleading social forwards**.

## Core Features
- **Image Forensics**: EXIF hardware verification, AI generator detection (Midjourney, DALL-E, Stable Diffusion, ComfyUI), Live Webcam & Gallery scan.
- **Voice Deepfake Detection**: Live microphone recording & audio file upload (`MP3`, `WAV`, `M4A`, `WebM`) to detect synthetic voice clones vs. authentic human speech.
- **Social Claim Verifier**: Check WhatsApp, Instagram, and SMS forwards with attached screenshots.
- **Real-Time Email OTP Security**: Register, Login, and Forgot/Reset Password with real-time 6-digit Email OTP verification.

## Quick Commands (Windows PowerShell)
- **Run on Chrome**: `Set-Location D:\MediaVerifyAI\mobile_app; flutter run -d chrome`
- **Run on Android Emulator**: `Set-Location D:\MediaVerifyAI\mobile_app; flutter run -d emulator-5554`
- **Direct Android APK**: Exported automatically to `D:\VeriLens-AI.apk` via `.\deploy-all.ps1`