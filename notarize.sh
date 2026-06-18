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
STAGE=""

cleanup() {
    rm -f "$ZIP"
    if [ -n "$STAGE" ]; then
        rm -rf "$STAGE"
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
STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname AgentCaffeine -srcfolder "$STAGE" -ov -format UDZO "$DMG"

echo "==> 5/5 DMG Apple 공증 제출 및 스테이플 (수 분 소요)"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"

echo ""
echo "배포 준비 완료: $(pwd)/$DMG"
echo "GitHub Releases 등에 업로드하면 됩니다. SHA256 (Homebrew cask용):"
shasum -a 256 "$DMG"
