#!/usr/bin/env bash
# Shelf를 빌드해서 실행 가능한 .app 번들로 조립합니다.
#
#   ./build.sh            릴리스 구성으로 빌드합니다
#   ./build.sh debug      디버그 구성으로 빌드합니다
#   ./build.sh release run  빌드한 뒤 바로 실행합니다
#
# Xcode 없이 Command Line Tools만으로 동작하도록 만들었습니다.
set -euo pipefail

APP_NAME="Shelf"
CONFIGURATION="${1:-release}"
SHOULD_RUN="${2:-}"

cd "$(dirname "$0")"

echo "▸ ${CONFIGURATION} 구성으로 컴파일합니다"
swift build -c "$CONFIGURATION"

BIN_PATH="$(swift build -c "$CONFIGURATION" --show-bin-path)"
BUNDLE="${PWD}/${APP_NAME}.app"

echo "▸ 앱 번들을 조립합니다: ${BUNDLE}"
rm -rf "$BUNDLE"
mkdir -p "${BUNDLE}/Contents/MacOS" "${BUNDLE}/Contents/Resources"

cp "${BIN_PATH}/${APP_NAME}" "${BUNDLE}/Contents/MacOS/${APP_NAME}"
cp "Resources/Info.plist" "${BUNDLE}/Contents/Info.plist"

# 의존성 패키지가 함께 만들어낸 리소스 번들을 옮겨 넣습니다.
shopt -s nullglob
for resource_bundle in "${BIN_PATH}"/*.bundle; do
	cp -R "$resource_bundle" "${BUNDLE}/Contents/Resources/"
done
shopt -u nullglob

# 개인용이라 정식 서명은 필요하지 않지만, 서명이 아예 없으면 전역 단축키 등록처럼
# 시스템 권한이 얽힌 기능이 불안정해질 수 있어서 임시 서명을 붙여 둡니다.
echo "▸ 임시 서명을 적용합니다"
codesign --force --sign - "$BUNDLE" >/dev/null 2>&1

echo "✓ 빌드가 완료되었습니다: ${BUNDLE}"

if [ "$SHOULD_RUN" = "run" ]; then
	echo "▸ 실행 중인 기존 인스턴스를 종료합니다"
	pkill -x "$APP_NAME" 2>/dev/null || true
	sleep 0.5
	open "$BUNDLE"
	echo "✓ 메뉴 바에서 트레이 모양 아이콘을 확인해 주세요"
fi
