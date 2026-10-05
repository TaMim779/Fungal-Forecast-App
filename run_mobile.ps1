# Runs the Flutter app. Usage:
#   .\run_mobile.ps1            -> Chrome (fastest way to see it)
#   .\run_mobile.ps1 android    -> Android emulator (starts Pixel_9 if not running)
#   .\run_mobile.ps1 <deviceId> -> any device from `flutter devices`
param([string]$Target = "chrome")
$ErrorActionPreference = "Stop"
Set-Location "$PSScriptRoot\mobile"

flutter pub get | Out-Null

if ($Target -eq "android") {
    $running = flutter devices 2>$null | Select-String "emulator-"
    if (-not $running) {
        Write-Host "Starting Pixel_9 emulator..." -ForegroundColor Cyan
        flutter emulators --launch Pixel_9
        Start-Sleep -Seconds 25
    }
    # Emulator reaches the host machine via 10.0.2.2 (set this in the app's Settings > Server URL).
    flutter run -d emulator-5554 --dart-define=FF_API_URL=http://10.0.2.2:8000
} else {
    flutter run -d $Target
}
