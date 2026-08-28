@echo off
REM Script to setup ADB port forwarding and run Flutter app

echo Setting up ADB port forwarding...
adb reverse tcp:3306 tcp:3306
adb reverse tcp:8080 tcp:80

echo ADB port forwarding configured!
echo.
echo Starting Flutter app...
flutter run

