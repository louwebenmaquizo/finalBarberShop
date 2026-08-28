# PowerShell script to setup ADB port forwarding and run Flutter app

Write-Host "Setting up ADB port forwarding..." -ForegroundColor Cyan

# Setup port forwarding
adb reverse tcp:3306 tcp:3306
adb reverse tcp:8080 tcp:80

Write-Host "ADB port forwarding configured!" -ForegroundColor Green
Write-Host ""

Write-Host "Starting Flutter app..." -ForegroundColor Cyan
flutter run

