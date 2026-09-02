#!/usr/bin/env bash
# Shelf를 빌드해서 실행 가능한 .app 번들로 조립합니다.
#
#   ./build.sh                기본값. 이 맥의 구조에 맞춰 릴리스로 빌드합니다
#   ./build.sh --run          빌드한 뒤 바로 실행합니다
#   ./build.sh --debug        디버그 구성으로 빌드합니다
#   ./build.sh --universal    애플 실리콘과 인텔 양쪽에서 도는 앱을 만듭니다
#
# 옵션은 함께 쓸 수 있습니다. 예: ./build.sh --universal --run
# Xcode 없이 Command Line Tools만으로 동작합니다.
set -euo pipefail

APP_NAME="Shelf"
DEPLOYMENT_TARGET="14.0"
CONFIGURATION="release"
SHOULD_RUN="no"
UNIVERSAL="no"

for argument in "$@"; do
	case "$argument" in
		--run) SHOULD_RUN="yes" ;;
		--debug) CONFIGURATION="debug" ;;
		--release) CONFIGURATION="release" ;;
		--universal) UNIVERSAL="yes" ;;
		-h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
		*) echo "알 수 없는 옵션입니다: $argument (사용법은 --help)" >&2; exit 1 ;;
	esac
done

cd "$(dirname "$0")"

echo "▸ ${CONFIGURATION} 구성으로 컴파일합니다"
swift build -c "$CONFIGURATION"
NATIVE_BINARY="$(swift build -c "$CONFIGURATION" --show-bin-path)/${APP_NAME}"
BIN_PATH="$(dirname "$NATIVE_BINARY")"

# 다른 구조용 바이너리를 따로 빌드해서 하나로 합칩니다.
# SwiftPM의 --arch 옵션은 Xcode에 딸린 xcbuild를 요구하므로 여기서는 쓸 수 없고,
# 대신 목표 구조를 직접 지정해서 한 번 더 빌드한 뒤 lipo로 묶습니다.
CROSS_BINARY=""
if [ "$UNIVERSAL" = "yes" ]; then
	HOST_ARCHITECTURE="$(uname -m)"
	if [ "$HOST_ARCHITECTURE" = "arm64" ]; then
		OTHER_ARCHITECTURE="x86_64"
	else
		OTHER_ARCHITECTURE="arm64"
	fi

	echo "▸ ${OTHER_ARCHITECTURE} 구조용으로 한 번 더 컴파일합니다"
	SCRATCH=".build-cross-${OTHER_ARCHITECTURE}"
	TRIPLE="${OTHER_ARCHITECTURE}-apple-macos${DEPLOYMENT_TARGET}"
	if swift build -c "$CONFIGURATION" --scratch-path "$SCRATCH" \
		-Xswiftc -target -Xswiftc "$TRIPLE" \
		-Xcc -target -Xcc "$TRIPLE" >/dev/null 2>&1
	then
		CROSS_BINARY="$(find "$SCRATCH" -type f -name "$APP_NAME" -perm -111 | head -1)"
	fi

	if [ -z "$CROSS_BINARY" ]; then
		echo "  ⚠ ${OTHER_ARCHITECTURE} 빌드에 실패했습니다. ${HOST_ARCHITECTURE} 전용으로 계속 진행합니다"
	fi
fi

BUNDLE="${PWD}/${APP_NAME}.app"

echo "▸ 앱 번들을 조립합니다: ${BUNDLE}"
rm -rf "$BUNDLE"
mkdir -p "${BUNDLE}/Contents/MacOS" "${BUNDLE}/Contents/Resources"

if [ -n "$CROSS_BINARY" ]; then
	lipo -create "$NATIVE_BINARY" "$CROSS_BINARY" -output "${BUNDLE}/Contents/MacOS/${APP_NAME}"
else
	cp "$NATIVE_BINARY" "${BUNDLE}/Contents/MacOS/${APP_NAME}"
fi

cp "Resources/Info.plist" "${BUNDLE}/Contents/Info.plist"

# 어느 시점의 소스로 만든 앱인지 알 수 있도록 git 커밋 해시를 새겨 둡니다.
# 커밋하지 않은 수정이 남아 있으면 뒤에 +를 붙입니다.
GIT_REVISION="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
if ! git diff --quiet HEAD 2>/dev/null; then
	GIT_REVISION="${GIT_REVISION}+"
fi
plutil -replace CFBundleVersion -string "$GIT_REVISION" "${BUNDLE}/Contents/Info.plist"

# 언어별 문자열 폴더를 번들에 넣습니다. 언어를 추가하면 자동으로 함께 복사됩니다.
shopt -s nullglob
for language_directory in Resources/*.lproj; do
	cp -R "$language_directory" "${BUNDLE}/Contents/Resources/"
done

# 의존성 패키지가 함께 만들어낸 리소스 번들이 있으면 옮겨 넣습니다.
for resource_bundle in "${BIN_PATH}"/*.bundle; do
	cp -R "$resource_bundle" "${BUNDLE}/Contents/Resources/"
done
shopt -u nullglob

# 개인용이라 정식 서명은 필요하지 않지만, 서명이 아예 없으면 전역 단축키 등록처럼
# 시스템 권한이 얽힌 기능이 불안정해질 수 있어서 임시 서명을 붙여 둡니다.
echo "▸ 임시 서명을 적용합니다"
codesign --force --sign - "$BUNDLE" >/dev/null 2>&1

echo "✓ 빌드가 완료되었습니다: ${BUNDLE}"
echo "  지원 구조: $(lipo -archs "${BUNDLE}/Contents/MacOS/${APP_NAME}")"
echo "  버전: $(plutil -extract CFBundleShortVersionString raw "${BUNDLE}/Contents/Info.plist") (${GIT_REVISION})"

if [ "$SHOULD_RUN" = "yes" ]; then
	echo "▸ 실행 중인 기존 인스턴스를 종료합니다"
	pkill -x "$APP_NAME" 2>/dev/null || true
	sleep 0.5
	open "$BUNDLE"
	echo "✓ 메뉴 바에서 트레이 모양 아이콘을 확인해 주세요"
fi
