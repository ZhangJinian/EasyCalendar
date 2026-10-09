#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
project="$PWD"
app="/Applications/EasyCalendar.app"
identifier="local.spacesands.OpenCalendarWidget"
widget_identifier="$identifier.widget"
registry="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
plugin="$app/Contents/PlugIns/OpenCalendarWidgetExtension.appex"

# 先验证新版，避免把注册状态切到不完整的应用。
[ -f "$app/Contents/Info.plist" ] && [ -f "$plugin/Contents/Info.plist" ] || {
    echo '请先将新版 EasyCalendar.app 安装到应用程序。' >&2; exit 1;
}
[ "$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$app/Contents/Info.plist")" = "$identifier" ]
[ "$(/usr/bin/plutil -extract CFBundleDisplayName raw -o - "$app/Contents/Info.plist")" = EasyCalendar ]
/usr/bin/codesign --verify --deep --strict "$app"

# 只解除本项目构建副本的注册；保留应用文件、日历和完成记录。
if [ -d "$project/build" ]; then
    while IFS= read -r -d '' bundle; do
        info="$bundle/Contents/Info.plist"
        [ -f "$info" ] || continue
        bundle_id=$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$info" 2>/dev/null) || continue
        case "$bundle_id" in
            "$identifier") "$registry" -u "$bundle" || true ;;
            "$widget_identifier")
                if removal=$(/usr/bin/pluginkit -r "$bundle" 2>&1); then
                    :
                elif [ "$removal" != "remove: no plugin at $bundle" ]; then
                    printf '%s\n' "$removal" >&2
                    exit 1
                fi
                ;;
        esac
    done < <(/usr/bin/find "$project/build" -type d \( -name '*.app' -o -name '*.appex' \) -print0)
fi
"$registry" -u /Applications/OpenCalendarWidget.app >/dev/null 2>&1 || true
"$registry" -f "$app"
/usr/bin/pluginkit -a "$plugin"
/usr/bin/pluginkit -e use -i "$widget_identifier"
registered=$(/usr/bin/pluginkit -m -A -D -v -i "$widget_identifier")
printf '%s\n' "$registered"
printf '%s\n' "$registered" | /usr/bin/grep -Fq "$plugin" || {
    echo '未找到新版扩展注册路径，请保留上方输出。' >&2; exit 1;
}
/usr/bin/killall NotificationCenter 2>/dev/null || true
echo '已注册应用程序中的 EasyCalendar。关闭并重新打开“编辑小组件”，搜索 EasyCalendar。'
