# Development Scripts

These scripts help set up ADB port forwarding automatically before running the Flutter app.

## Scripts

### `run_with_adb.bat` (Windows Batch)
Run this script to automatically set up port forwarding and start the Flutter app.

**Usage:**
```bash
.\scripts\run_with_adb.bat
```

### `run_with_adb.ps1` (PowerShell)
PowerShell version with colored output.

**Usage:**
```powershell
.\scripts\run_with_adb.ps1
```

## Port Forwarding

The scripts automatically set up:
- **Port 3306** (MySQL): `adb reverse tcp:3306 tcp:3306`
- **Port 8080** (HTTP API): `adb reverse tcp:8080 tcp:80`

## Manual Setup

If you prefer to run commands manually:

```bash
adb reverse tcp:3306 tcp:3306
adb reverse tcp:8080 tcp:80
flutter run
```

## Note

- Make sure your Android device is connected via USB
- ADB must be in your system PATH
- XAMPP (Apache and MySQL) must be running

