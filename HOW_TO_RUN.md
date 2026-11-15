============================================================
VERILENS AI - CHROME & ANDROID EMULATOR CHALANE KA TARIKA
============================================================

1) GOOGLE CHROME PAR CHALANE KE LIYE:
   Set-Location D:\MediaVerifyAI\mobile_app
   flutter run -d chrome

2) ANDROID EMULATOR START KARKE CHALANE KE LIYE:
   flutter emulators
   flutter emulators --launch Medium_Phone_API_36.1
   Set-Location D:\MediaVerifyAI\mobile_app
   flutter run -d emulator-5554

3) DIRECT APK (D:\VeriLens-AI.apk) EMULATOR PAR INSTALL KARNE KE LIYE:
   D:\Android\SDK\platform-tools\adb.exe -s emulator-5554 install -r D:\VeriLens-AI.apk
   D:\Android\SDK\platform-tools\adb.exe -s emulator-5554 shell monkey -p com.example.media_verify_ai -c android.intent.category.LAUNCHER 1

4) SAB KUCH AUTO-UPDATE (VERCEL + D:\VeriLens-AI.apk + GITHUB) KE LIYE:
   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
   Set-Location D:\MediaVerifyAI
   .\deploy-all.ps1