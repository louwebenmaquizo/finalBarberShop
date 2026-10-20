# Set JAVA_HOME to JDK 17
$jdk17 = "C:\Users\Administrator\.jdk17"
if (Test-Path "$jdk17\bin\java.exe") {
    $env:JAVA_HOME = $jdk17
    $env:PATH = "$jdk17\bin;" + $env:PATH
    Write-Host "Using JDK 17 from $jdk17" -ForegroundColor Cyan
}

# Guard: only the Supabase URL and publishable key may be compiled into the app.
$config = Get-Content "supabase.local.json" -Raw | ConvertFrom-Json
$forbidden = $config.PSObject.Properties.Name | Where-Object { $_ -notin @("SUPABASE_URL", "SUPABASE_PUBLISHABLE_KEY") }
if ($forbidden) {
    Write-Host "supabase.local.json contains keys that would be embedded in the app: $($forbidden -join ', ')" -ForegroundColor Red
    Write-Host "Remove them. Server secrets such as GEMINI_API_KEY belong in 'supabase secrets set'." -ForegroundColor Red
    exit 1
}

Write-Host "Building Release APK: Maquizo_LiemBarberShop.apk..." -ForegroundColor Green
flutter build apk --release --dart-define-from-file=supabase.local.json

if ($LASTEXITCODE -eq 0) {
    $sourceApk = "build\app\outputs\flutter-apk\app-release.apk"
    $targetApk = "build\app\outputs\flutter-apk\Maquizo_LiemBarberShop.apk"
    $rootApk = "Maquizo_LiemBarberShop.apk"

    if (Test-Path $sourceApk) {
        Copy-Item -Path $sourceApk -Destination $targetApk -Force
        Copy-Item -Path $sourceApk -Destination $rootApk -Force
        Write-Host "`n SUCCESS! APK generated at:" -ForegroundColor Green
        Write-Host "1. $rootApk (Project Root: c:\barber\Maquizo_LiemBarberShop.apk)" -ForegroundColor Yellow
        Write-Host "2. $targetApk" -ForegroundColor Yellow
    }
} else {
    Write-Host "`n Build failed. Please check the logs above." -ForegroundColor Red
}
