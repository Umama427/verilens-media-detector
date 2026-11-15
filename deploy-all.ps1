# ==============================================================================
# VeriLens One-Click Auto-Sync: Vercel + D:\VeriLens-AI.apk + Emulator + GitHub
# Safe Scope: Only operates inside D:\MediaVerifyAI and copies APK to D:\VeriLens-AI.apk
# ==============================================================================
$ErrorActionPreference = "Stop"
$RootDir = "D:\MediaVerifyAI"
$MobileDir = Join-Path $RootDir "mobile_app"
$BackendDir = Join-Path $RootDir "backend_api"
$AdbExe = "D:\Android\SDK\platform-tools\adb.exe"
$DirectApkDest = "D:\VeriLens-AI.apk"

Write-Host "==> 1/4 Installing Backend Deps & Deploying to Vercel..." -ForegroundColor Cyan
Push-Location $BackendDir
npm install
npx vercel --prod
if ($LASTEXITCODE -ne 0) { Pop-Location; throw "Vercel deploy failed." }
Pop-Location

Write-Host "==> 2/4 Analyzing & Building Android Release APK..." -ForegroundColor Cyan
Push-Location $MobileDir
flutter analyze
if ($LASTEXITCODE -ne 0) { Pop-Location; throw "flutter analyze failed." }
flutter build apk --release
if ($LASTEXITCODE -ne 0) { Pop-Location; throw "flutter build apk failed." }

$BuiltApk = Join-Path $MobileDir "build\app\outputs\flutter-apk\app-release.apk"
if (Test-Path $BuiltApk) {
  Copy-Item -Path $BuiltApk -Destination $DirectApkDest -Force
  Write-Host "  [+] Direct APK saved to $DirectApkDest" -ForegroundColor Green
}

if (Test-Path $AdbExe) {
  $devices = & $AdbExe devices
  if ($devices -match "emulator-5554\s+device") {
    Write-Host "==> 3/4 Installing & Launching APK on emulator-5554..." -ForegroundColor Cyan
    & $AdbExe -s emulator-5554 install -r $BuiltApk
    & $AdbExe -s emulator-5554 shell monkey -p com.example.media_verify_ai -c android.intent.category.LAUNCHER 1
  } else {
    Write-Host "  [i] emulator-5554 not running; direct APK ready at $DirectApkDest" -ForegroundColor Yellow
  }
}
Pop-Location

Write-Host "==> 4/4 Pushing Updates to GitHub..." -ForegroundColor Cyan
Push-Location $RootDir
git add .
$status = git status --porcelain
if ($status) {
  git commit -m "Add real-time Email OTP, direct D:\ APK export, HOW_TO_RUN & GitHub README"
}
git push -u origin main
Pop-Location

Write-Host "==> DONE! Vercel, D:\VeriLens-AI.apk, and GitHub are all synced." -ForegroundColor Green