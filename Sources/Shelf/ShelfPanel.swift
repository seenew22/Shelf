import AppKit
import QuartzCore
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

    /// 창이 어느 쪽에서 밀려 나올지를 나타냅니다.
    enum SlideOrigin {
        /// 화면 왼쪽 가장자리에서 밀려 나옵니다.
        case leadingEdge
        /// 화면 오른쪽 가장자리에서 밀려 나옵니다.
        case trailingEdge
        /// 메뉴 바 아이콘 아래로 내려옵니다.
        case above
        /// 제자리에서 살짝 떠오릅니다. 마우스 커서 옆에 열 때 사용합니다.
        case inPlace

        /// 나타나기 직전에 창이 놓일 위치의 어긋난 정도입니다.
        var offset: CGSize {
            switch self {
            case .leadingEdge: CGSize(width: -32, height: 0)
            case .trailingEdge: CGSize(width: 32, height: 0)
            case .above: CGSize(width: 0, height: 18)
            case .inPlace: CGSize(width: 0, height: -10)
            }
        }
    }

    private static let presentDuration: TimeInterval = 0.20
    private static let dismissDuration: TimeInterval = 0.13

    private var slideOrigin: SlideOrigin = .inPlace
    private var isDismissing = false

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
        // 나타나고 사라지는 움직임을 직접 그리므로 시스템 기본 효과는 끕니다.
        animationBehavior = .none

        contentView = NSHostingView(rootView: rootView)
    }

    // MARK: - 나타나고 사라지기

    /// 지정한 방향에서 밀려 나오면서 창을 띄웁니다.
    ///
    /// 위치는 미리 잡아 둔 상태여야 합니다. 그 위치를 목적지로 삼고, 조금 어긋난 자리에서
    /// 투명한 채로 시작해서 제자리로 미끄러져 들어옵니다.
    func present(slidingFrom origin: SlideOrigin) {
        slideOrigin = origin
        isDismissing = false

        let destination = frame
        let start = NSRect(
            x: destination.origin.x + origin.offset.width,
            y: destination.origin.y + origin.offset.height,
            width: destination.width,
            height: destination.height
        )

        setFrame(start, display: false)
        alphaValue = 0
        orderFrontRegardless()
        makeKey()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.presentDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true
            animator().setFrame(destination, display: true)
            animator().alphaValue = 1
        }
    }

    /// 들어왔던 방향으로 되돌아가면서 창을 감춥니다.
    func dismiss() {
        guard isVisible, !isDismissing else {
            orderOut(nil)
            return
        }
        isDismissing = true

        let current = frame
        let departure = NSRect(
            x: current.origin.x + slideOrigin.offset.width,
            y: current.origin.y + slideOrigin.offset.height,
            width: current.width,
            height: current.height
        )

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.dismissDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            context.allowsImplicitAnimation = true
            animator().setFrame(departure, display: true)
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.isDismissing else { return }
                self.isDismissing = false
                self.orderOut(nil)
                // 다음에 띄울 때를 위해 원래 상태로 되돌려 둡니다.
                self.alphaValue = 1
                self.setFrame(current, display: false)
            }
        }
    }

    // MARK: - 위치 잡기

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

    /// 마우스 커서 바로 옆에 창을 배치합니다.
    ///
    /// 단축키로 열었을 때 시선과 손이 이미 가 있는 자리에 창이 나타나므로,
    /// 화면 위쪽 메뉴 바까지 올라갔다 내려올 필요가 없습니다.
    func position(near cursorLocation: NSPoint) {
        let size = frame.size
        // 커서 왼쪽 위 모서리에서 살짝 벗어난 지점을 창의 왼쪽 위로 삼습니다.
        var origin = NSPoint(x: cursorLocation.x - 12, y: cursorLocation.y + 12 - size.height)

        let screen = NSScreen.screens.first { $0.frame.contains(cursorLocation) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
            origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        }

        setFrameOrigin(origin)
    }

    /// 화면의 좌우 가장자리에 붙여서 창을 배치합니다.
    ///
    /// 세로 위치는 마우스가 있던 높이를 기준으로 맞춰서, 시선이 가 있는 자리에 나타나게 합니다.
    func position(atEdge edge: EdgeHoverMonitor.HorizontalEdge, on screen: NSScreen, cursorHeight: CGFloat) {
        let size = frame.size
        let visible = screen.visibleFrame
        let inset: CGFloat = 8

        let x = switch edge {
        case .left: visible.minX + inset
        case .right: visible.maxX - size.width - inset
        }

        var y = cursorHeight - size.height / 2
        y = min(max(y, visible.minY + inset), visible.maxY - size.height - inset)

        setFrameOrigin(NSPoint(x: x, y: y))
    }
}
