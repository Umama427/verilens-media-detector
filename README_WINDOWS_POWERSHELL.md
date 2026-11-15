# VeriLens â€” Windows D: Drive & PowerShell Setup Guide

## 1. Run One-Click PowerShell Setup on D: Drive
Open **Windows PowerShell** and run:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
D:
.\setup-d-drive.ps1
```

This creates the complete workspace at `D:\MediaVerifyAI` with:
- `D:\MediaVerifyAI\mobile_app` (Flutter + Dart Android application)
- `D:\MediaVerifyAI\backend_api` (Vercel + MongoDB Atlas Node/Express API)

## 2. MongoDB Atlas + MongoDB Compass
1. Create a free cluster in MongoDB Atlas and copy your `MONGODB_URI`.
2. Open **MongoDB Compass**, paste the same URI, and inspect the `media_verify_db` database (`scans` and `apk_downloads` collections).
3. Save your URI in `D:\MediaVerifyAI\backend_api\.env`.

## 3. Deploy Backend to Vercel
```powershell
cd "D:\MediaVerifyAI\backend_api"
npx vercel --prod
```

## 4. Build Android APK & Transfer to Phone
```powershell
cd "D:\MediaVerifyAI\mobile_app"
flutter build apk --release
```
Your installable APK will be generated at:
`D:\MediaVerifyAI\mobile_app\build\app\outputs\flutter-apk\app-release.apk`

To install directly via USB (Enable USB Debugging on Android):
```powershell
adb install build\app\outputs\flutter-apk\app-release.apk
```
