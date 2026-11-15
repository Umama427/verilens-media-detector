$ErrorActionPreference = "Stop"
$RootDir = "D:\MediaVerifyAI"
$MobileDir = Join-Path $RootDir "mobile_app"
$BackendDir = Join-Path $RootDir "backend_api"
$AdbExe = "D:\Android\SDK\platform-tools\adb.exe"

Write-Host "==> 1/4 Deploying Backend to Vercel..." -ForegroundColor Cyan
Push-Location $BackendDir
npx vercel --prod
Pop-Location

Write-Host "==> 2/4 Analyzing & Building Android Release APK..." -ForegroundColor Cyan
Push-Location $MobileDir
flutter analyze
flutter build apk --release

if (Test-Path $AdbExe) {
  $devices = & $AdbExe devices
  if ($devices -match "emulator-5554\s+device") {
    Write-Host "==> 3/4 Installing & Launching APK on emulator-5554..." -ForegroundColor Cyan
    & $AdbExe -s emulator-5554 install -r ".\build\app\outputs\flutter-apk\app-release.apk"
    & $AdbExe -s emulator-5554 shell monkey -p com.example.media_verify_ai -c android.intent.category.LAUNCHER 1
  } else {
    Write-Host "  [i] emulator-5554 not running; APK saved at $MobileDir\build\app\outputs\flutter-apk\app-release.apk" -ForegroundColor Yellow
  }
}
Pop-Location

Write-Host "==> 4/4 Pushing Updates to GitHub..." -ForegroundColor Cyan
Push-Location $RootDir
git add .
$status = git status --porcelain
if ($status) {
  git commit -m "Auto-update VeriLens Auth, Voice Deepfake, Image Forensics, APK & Vercel API"
}
git push -u origin main
Pop-Location

Write-Host "==> DONE! Vercel, APK, and GitHub are all synced." -ForegroundColor Green