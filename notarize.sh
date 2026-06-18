#!/bin/bash
# AgentCaffeine 공증(notarization) + DMG 배포 패키징 스크립트
#
# 사전 준비 (최초 1회):
#   1. Apple Developer Program 가입 후 Developer ID Application 인증서 발급 (README.md 참고)
#   2. 공증 자격 증명 저장:
#      xcrun notarytool store-credentials agentcaffeine \
#        --apple-id "본인 Apple ID 이메일" \
#        --team-id "팀 ID (10자리)" \
#        --password "앱 암호(appleid.apple.com에서 생성한 app-specific password)"
#
# 사용법: ./build.sh 로 정식 서명 빌드 후 ./notarize.sh
set -e
cd "$(dirname "$0")"

APP=AgentCaffeine.app
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG="AgentCaffeine-$VERSION.dmg"
PROFILE="${NOTARY_PROFILE:-agentcaffeine}"
ZIP=AgentCaffeine.zip
WORK_DIR=""
DMG_MOUNT=""

cleanup() {
    rm -f "$ZIP"
    if [ -n "$DMG_MOUNT" ] && [ -d "$DMG_MOUNT" ]; then
        hdiutil detach "$DMG_MOUNT" -quiet 2>/dev/null || hdiutil detach "$DMG_MOUNT" -force -quiet 2>/dev/null || true
    fi
    if [ -n "$WORK_DIR" ]; then
        rm -rf "$WORK_DIR"
    fi
}
trap cleanup EXIT

# 정식 서명 확인 (ad-hoc 빌드는 공증 불가)
if ! codesign -dv --verbose=4 "$APP" 2>&1 | grep -q "Authority=Developer ID Application"; then
    echo "오류: $APP 이 Developer ID로 서명되어 있지 않습니다. 인증서 설치 후 ./build.sh 를 다시 실행하세요."
    exit 1
fi

echo "==> 1/5 앱 공증 제출용 zip 생성"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> 2/5 앱 Apple 공증 제출 (수 분 소요)"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait

echo "==> 3/5 앱 공증 티켓 스테이플"
xcrun stapler staple "$APP"

echo "==> 4/5 DMG 생성"
rm -f "$DMG"
find /Volumes -maxdepth 1 -type d -name "AgentCaffeine*" -print0 | while IFS= read -r -d '' volume; do
    hdiutil detach "$volume" -quiet 2>/dev/null || hdiutil detach "$volume" -force -quiet 2>/dev/null || true
done
WORK_DIR=$(mktemp -d)
RW_DMG="$WORK_DIR/AgentCaffeine-rw.dmg"

hdiutil create -volname AgentCaffeine -size 32m -fs HFS+ -ov "$RW_DMG"
ATTACH_OUTPUT=$(hdiutil attach "$RW_DMG" -readwrite -noverify -noautoopen)
DMG_MOUNT=$(echo "$ATTACH_OUTPUT" | awk '/\/Volumes\// { print substr($0, index($0, "/Volumes/")); exit }')
if [ -z "$DMG_MOUNT" ]; then
    echo "오류: DMG 마운트 위치를 찾지 못했습니다."
    echo "$ATTACH_OUTPUT"
    exit 1
fi
sleep 1

cp -R "$APP" "$DMG_MOUNT/"
ln -s /Applications "$DMG_MOUNT/Applications"
mkdir -p "$DMG_MOUNT/.background"
swift dmg_background.swift "$DMG_MOUNT/.background/background.png"

osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "AgentCaffeine"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {100, 100, 848, 514}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 96
        set background picture of viewOptions to POSIX file "$DMG_MOUNT/.background/background.png"
        set position of item "AgentCaffeine.app" of container window to {180, 190}
        set position of item "Applications" of container window to {560, 190}
        close
        open
        update without registering applications
        delay 1
        close
    end tell
end tell
APPLESCRIPT

sync
for _ in 1 2 3 4 5; do
    if hdiutil detach "$DMG_MOUNT" -quiet; then
        DMG_MOUNT=""
        break
    fi
    sleep 1
done
if [ -n "$DMG_MOUNT" ]; then
    hdiutil detach "$DMG_MOUNT" -force -quiet
    DMG_MOUNT=""
fi

hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG"

echo "==> 5/5 DMG Apple 공증 제출 및 스테이플 (수 분 소요)"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"

echo ""
echo "배포 준비 완료: $(pwd)/$DMG"
echo "GitHub Releases 등에 업로드하면 됩니다. SHA256 (Homebrew cask용):"
shasum -a 256 "$DMG"
