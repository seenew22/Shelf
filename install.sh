#!/usr/bin/env bash
# Shelf 를 설치합니다. 이미 설치되어 있으면 최신으로 갱신합니다.
#
#   ./install.sh
#
# 설치와 갱신이 같은 명령입니다. 처음이면 내려받아 설치하고, 이미 있으면 새 변경만
# 받아서 다시 빌드합니다. 히스토리와 설정은 앱 바깥에 저장되므로 갱신해도 그대로입니다.
#
# 바꿀 수 있는 값 (거의 쓸 일 없습니다)
#   SHELF_REPOSITORY   내려받을 주소 (SSH 를 쓰려면 여기에 지정)
#   SHELF_SOURCE_DIR   소스를 둘 자리 (기본값 ~/.shelf)
#   SHELF_APP_DIR      앱을 둘 자리 (기본값 /Applications)
set -euo pipefail

REPOSITORY="${SHELF_REPOSITORY:-https://github.com/seenew22/Shelf.git}"
SOURCE_DIR="${SHELF_SOURCE_DIR:-$HOME/.shelf}"
APP_DIR="${SHELF_APP_DIR:-/Applications}"
APP_NAME="Shelf"

# 1. 빌드에 필요한 명령어 도구가 있는지 확인합니다.
if ! xcrun --find swiftc >/dev/null 2>&1; then
	echo "▸ 빌드에 필요한 명령어 도구가 없습니다. 설치 창을 띄웁니다."
	xcode-select --install || true
	echo
	echo "  설치가 끝난 뒤에 이 명령을 다시 실행해 주세요."
	exit 1
fi

# 2. 소스를 받아옵니다. 이미 있으면 새 변경만 가져옵니다.
if [ -d "$SOURCE_DIR/.git" ]; then
	echo "▸ 새 변경을 받아옵니다: $SOURCE_DIR"
	git -C "$SOURCE_DIR" fetch --quiet origin
	git -C "$SOURCE_DIR" pull --quiet --ff-only
else
	echo "▸ 내려받습니다: $SOURCE_DIR"
	git clone --quiet "$REPOSITORY" "$SOURCE_DIR"
fi

# 3. 두 종류의 맥에서 모두 도는 앱으로 빌드합니다.
"$SOURCE_DIR/build.sh" --universal

# 4. 자리에 놓고 실행합니다.
echo "▸ ${APP_DIR} 에 놓습니다"
mkdir -p "$APP_DIR"
pkill -x "$APP_NAME" 2>/dev/null || true
sleep 0.5
rm -rf "${APP_DIR:?}/${APP_NAME}.app"
mv "$SOURCE_DIR/${APP_NAME}.app" "$APP_DIR/"

open "${APP_DIR}/${APP_NAME}.app"

echo
echo "✓ 준비되었습니다. 메뉴 바에서 트레이 모양 아이콘을 확인해 주세요."
echo "  히스토리 열기: ⌘⇧V"
echo "  나중에 갱신할 때도 같은 명령을 다시 실행하면 됩니다."
