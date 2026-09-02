import AppKit
import SwiftUI

/// 히스토리 목록을 담는 떠 있는 창입니다.
///
/// 일반적인 창이나 `NSPopover` 대신 `.nonactivatingPanel` 속성을 가진 패널을 사용합니다.
/// 이렇게 하면 창이 떠 있는 동안에도 원래 작업하던 앱이 활성 상태를 유지하기 때문에,
/// 항목을 끌어다 놓을 대상 앱의 포커스를 흐트러뜨리지 않습니다.
/// macOS 14부터는 전역 단축키만으로 앱을 활성 상태로 올릴 수 없게 바뀌었는데,
/// 이 패널은 활성화를 요구하지 않으므로 그 제약도 함께 피해 갑니다.
final class ShelfPanel: NSPanel {

    static let contentWidth: CGFloat = 340
    static let contentHeight: CGFloat = 460

    /// 테두리가 없는 창은 기본적으로 키 입력을 받지 못하므로 직접 허용해 줍니다.
    override var canBecomeKey: Bool { true }

    init(rootView: some View) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Self.contentWidth, height: Self.contentHeight),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .popUpMenu
        // 앱이 비활성 상태가 되어도 창을 숨기지 않습니다.
        hidesOnDeactivate = false
        // 모든 데스크탑 공간과 전체 화면 앱 위에서도 보이도록 합니다.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovable = false
        animationBehavior = .utilityWindow

        contentView = NSHostingView(rootView: rootView)
    }

    /// 상태 항목 아이콘 바로 아래에 창을 배치합니다.
    /// 화면 가장자리를 넘어가지 않도록 위치를 보정합니다.
    func position(below statusButton: NSStatusBarButton) {
        guard let buttonWindow = statusButton.window else { return }

        let anchor = buttonWindow.convertToScreen(
            statusButton.convert(statusButton.bounds, to: nil)
        )
        let size = frame.size
        var origin = NSPoint(
            x: anchor.midX - size.width / 2,
            y: anchor.minY - size.height - 6
        )

        if let screen = buttonWindow.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
            origin.y = max(origin.y, visible.minY + 8)
        }

        setFrameOrigin(origin)
    }
}
