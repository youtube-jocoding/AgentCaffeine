#!/bin/bash
# AgentCaffeine 빌드 스크립트
# Developer ID 인증서가 키체인에 있으면 정식 서명(공증 가능), 없으면 ad-hoc 서명(로컬 실행용)
set -e
cd "$(dirname "$0")"

APP=AgentCaffeine.app
DEPLOYMENT_TARGET=$(/usr/libexec/PlistBuddy -c "Print LSMinimumSystemVersion" Info.plist)
BUILD_ARCHS="${BUILD_ARCHS:-arm64 x86_64}"
BUILD_DIR=$(mktemp -d)

cleanup() {
    rm -rf "$BUILD_DIR"
}
trap cleanup EXIT

BINARIES=()
for ARCH in $BUILD_ARCHS; do
    SWIFT_TARGET="${ARCH}-apple-macosx${DEPLOYMENT_TARGET}"
    OUTPUT="$BUILD_DIR/AgentCaffeine-$ARCH"
    echo "빌드 대상: $SWIFT_TARGET"
    swiftc -O -target "$SWIFT_TARGET" main.swift -o "$OUTPUT"
    BINARIES+=("$OUTPUT")
done

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

if [ "${#BINARIES[@]}" -eq 1 ]; then
    cp "${BINARIES[0]}" "$APP/Contents/MacOS/AgentCaffeine"
else
    lipo -create "${BINARIES[@]}" -output "$APP/Contents/MacOS/AgentCaffeine"
fi
cp Info.plist "$APP/Contents/Info.plist"
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Developer ID Application 인증서 자동 감지 (SIGN_IDENTITY 환경변수로 직접 지정도 가능)
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
    | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)"/\1/')}"

if [ -n "$IDENTITY" ]; then
    codesign --force --options runtime --timestamp \
        --entitlements entitlements.plist \
        --sign "$IDENTITY" "$APP"
    echo "정식 서명 완료: $IDENTITY"
    echo "배포하려면 다음 단계로 ./notarize.sh 를 실행하세요."
else
    codesign --force --sign - "$APP"
    echo "(!) Developer ID 인증서가 없어 ad-hoc 서명했습니다. 이 Mac에서만 실행 가능합니다."
    echo "    배포용 빌드는 Apple Developer Program 가입 후 인증서 발급이 필요합니다. (README.md 참고)"
fi

echo "빌드 완료: $(pwd)/$APP"
