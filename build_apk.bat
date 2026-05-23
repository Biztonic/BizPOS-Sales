@echo off
echo ==========================================
echo   Building BizPOS Sales APK (Release)
echo ==========================================

set FLUTTER_PATH=C:\src\flutter\bin\flutter.bat

echo [1/3] Cleaning project...
call %FLUTTER_PATH% clean

echo [2/3] Getting dependencies...
call %FLUTTER_PATH% pub get

echo [3/3] Building Release APK...
call %FLUTTER_PATH% build apk --release

echo ==========================================
echo   Build Complete!
echo   APK location: build\app\outputs\flutter-apk\app-release.apk
echo ==========================================
pause
