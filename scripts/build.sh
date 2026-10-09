#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build/ModuleCache
swiftc -module-cache-path build/ModuleCache Shared/CalendarData.swift Checks/Check.swift -o build/check
./build/check
swiftc -module-cache-path build/ModuleCache Shared/CalendarData.swift Checks/LanguageBridge.swift -o build/language-check
./build/language-check
# 用真实宿主 bundle ID 回归检查偏好初始化；不启动窗口或读取日历。
checks_root=$(mktemp -d "${TMPDIR:-/tmp}/easycalendar-checks.XXXXXX")
trap 'rm -r "$checks_root"' EXIT
mkdir -p "$checks_root/PreferencesCheck.app/Contents/MacOS"
cp build/check "$checks_root/PreferencesCheck.app/Contents/MacOS/PreferencesCheck"
cat > "$checks_root/PreferencesCheck.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.spacesands.OpenCalendarWidget</string>
<key>CFBundleExecutable</key><string>PreferencesCheck</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSBackgroundOnly</key><true/>
</dict></plist>
PLIST
"$checks_root/PreferencesCheck.app/Contents/MacOS/PreferencesCheck" --host-preferences
xcodebuild -project OpenCalendarWidget.xcodeproj -scheme OpenCalendarWidget -configuration "${1:-Debug}" -destination "platform=macOS,arch=arm64" -derivedDataPath build/DerivedData CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= build > build/build.log 2>&1 || {
    tail -n 60 build/build.log
    exit 1
}
printf '%s\n' 'BUILD SUCCEEDED' "App: $(pwd)/build/DerivedData/Build/Products/${1:-Debug}/EasyCalendar.app"
