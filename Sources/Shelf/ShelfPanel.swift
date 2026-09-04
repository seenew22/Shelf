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
///
/// 창은 눈에 보이는 카드보다 사방으로 조금 큽니다. 그 여백에 그림자를 그리고,
/// 카드가 자라나는 움직임을 담을 자리로 씁니다.
final class ShelfPanel: NSPanel {

    /// 눈에 보이는 카드의 크기입니다.
    static let contentWidth: CGFloat = 340
    static let contentHeight: CGFloat = 460

    /// 그림자와 확대 여유를 담기 위해 창을 카드보다 이만큼 크게 잡습니다.
    /// 그림자가 잘려 보이지 않도록 번지는 거리와 아래로 치우친 정도를 넉넉히 덮을 만큼 둡니다.
    static let shadowMargin: CGFloat = 36

    /// 창이 어느 지점에서 자라나는지를 나타냅니다.
    enum SlideOrigin {
        /// 화면 왼쪽 가장자리에서 튀어나옵니다.
        case leadingEdge
        /// 화면 오른쪽 가장자리에서 튀어나옵니다.
        case trailingEdge
        /// 메뉴 바 아이콘 아래로 펼쳐집니다.
        case above
        /// 마우스 커서가 있는 왼쪽 위 모서리에서 펼쳐집니다.
        case cursor

        /// 자라나기 시작하는 기준점입니다.
        var anchor: UnitPoint {
            switch self {
            case .leadingEdge: .leading
            case .trailingEdge: .trailing
            case .above: .top
            case .cursor: .topLeading
            }
        }
    }

    /// 테두리가 없는 창은 기본적으로 키 입력을 받지 못하므로 직접 허용해 줍니다.
    override var canBecomeKey: Bool { true }

    /// 실제로 눈에 보이는 카드가 화면에서 차지하는 자리입니다.
    /// 바깥 여백은 투명하므로, 바깥 클릭 판정 같은 계산은 이 값을 기준으로 해야 합니다.
    var cardFrame: NSRect {
        frame.insetBy(dx: Self.shadowMargin, dy: Self.shadowMargin)
    }

    init(rootView: some View) {
        super.init(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: Self.contentWidth + Self.shadowMargin * 2,
                height: Self.contentHeight + Self.shadowMargin * 2
            ),
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
        // 그림자는 내용물 쪽에서 그립니다. 창 그림자는 카드가 자라는 동안 따라오지 못합니다.
        hasShadow = false
        isMovable = false
        // 나타나고 사라지는 움직임을 내용물 쪽에서 그리므로 시스템 기본 효과는 끕니다.
        animationBehavior = .none

        contentView = NSHostingView(rootView: rootView)
    }

    // MARK: - 위치 잡기
    //
    // 아래 함수들은 모두 "카드가 놓일 자리"를 계산한 뒤 창을 그만큼 바깥으로 물려서 놓습니다.

    /// 카드의 왼쪽 아래 모서리가 이 지점에 오도록 창을 옮깁니다.
    private func setCardOrigin(_ origin: NSPoint) {
        setFrameOrigin(NSPoint(x: origin.x - Self.shadowMargin, y: origin.y - Self.shadowMargin))
    }

    /// 상태 항목 아이콘 바로 아래에 창을 배치합니다.
    /// 화면 가장자리를 넘어가지 않도록 위치를 보정합니다.
    func position(below statusButton: NSStatusBarButton) {
        guard let buttonWindow = statusButton.window else { return }

        let anchor = buttonWindow.convertToScreen(
            statusButton.convert(statusButton.bounds, to: nil)
        )
        var origin = NSPoint(
            x: anchor.midX - Self.contentWidth / 2,
            y: anchor.minY - Self.contentHeight - 6
        )

        if let screen = buttonWindow.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - Self.contentWidth - 8)
            origin.y = max(origin.y, visible.minY + 8)
        }

        setCardOrigin(origin)
    }

    /// 마우스 커서 바로 옆에 창을 배치합니다.
    ///
    /// 단축키로 열었을 때 시선과 손이 이미 가 있는 자리에 창이 나타나므로,
    /// 화면 위쪽 메뉴 바까지 올라갔다 내려올 필요가 없습니다.
    func position(near cursorLocation: NSPoint) {
        // 커서 왼쪽 위 모서리에서 살짝 벗어난 지점을 카드의 왼쪽 위로 삼습니다.
        var origin = NSPoint(
            x: cursorLocation.x - 12,
            y: cursorLocation.y + 12 - Self.contentHeight
        )

        let screen = NSScreen.screens.first { $0.frame.contains(cursorLocation) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - Self.contentWidth - 8)
            origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - Self.contentHeight - 8)
        }

        setCardOrigin(origin)
    }

    // MARK: - 가장자리에서 잡아 빼기
    //
    // 화면 밖에 세워 둔 선반을 손으로 잡아 빼내는 것처럼 다룹니다.
    // 별도의 손잡이를 그리지 않고 선반 자체의 가장자리를 조금 내밀어 두면,
    // 잡아당기는 대상과 나오는 물건이 처음부터 같은 것이 됩니다.

    /// 화면 가장자리에서 창을 완전히 꺼냈을 때 드러나는 폭입니다.
    static var fullyRevealedWidth: CGFloat { contentWidth + edgeInset }

    /// 다 꺼낸 카드와 화면 끝 사이의 간격입니다.
    static let edgeInset: CGFloat = 8

    /// 카드의 가장자리 쪽 끝이 화면 안으로 `revealedWidth` 만큼만 들어오도록 창을 놓습니다.
    /// 나머지는 화면 밖에 있게 되며, 다 꺼내면 제자리에 놓입니다.
    func position(
        atEdge edge: EdgeHoverMonitor.HorizontalEdge,
        on screen: NSScreen,
        cursorHeight: CGFloat,
        revealedWidth: CGFloat
    ) {
        setCardOrigin(cardOrigin(atEdge: edge, on: screen, cursorHeight: cursorHeight, revealedWidth: revealedWidth))
    }

    /// 드러난 폭을 부드럽게 바꿉니다.
    /// - Parameter timing: 제자리를 지나쳤다가 돌아오게 하려면 넘치는 곡선을 넘깁니다.
    func animate(
        toRevealedWidth revealedWidth: CGFloat,
        atEdge edge: EdgeHoverMonitor.HorizontalEdge,
        on screen: NSScreen,
        cursorHeight: CGFloat,
        duration: TimeInterval,
        timing: CAMediaTimingFunction
    ) {
        let origin = cardOrigin(atEdge: edge, on: screen, cursorHeight: cursorHeight, revealedWidth: revealedWidth)
        let target = NSRect(
            x: origin.x - Self.shadowMargin,
            y: origin.y - Self.shadowMargin,
            width: frame.width,
            height: frame.height
        )

        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = timing
            // 창을 움직일 때는 반드시 setFrame 을 써야 합니다.
            // animator() 를 거친 setFrameOrigin 은 NSWindow 에서 아무 일도 하지 않고 조용히 무시됩니다.
            animator().setFrame(target, display: true)
        }
    }

    /// 지정한 조건으로 놓았을 때 카드가 차지하게 될 자리입니다.
    /// 움직임이 끝나기를 기다리지 않고 최종 위치를 알아야 할 때 씁니다.
    func restingCardFrame(
        atEdge edge: EdgeHoverMonitor.HorizontalEdge,
        on screen: NSScreen,
        cursorHeight: CGFloat,
        revealedWidth: CGFloat
    ) -> NSRect {
        NSRect(
            origin: cardOrigin(atEdge: edge, on: screen, cursorHeight: cursorHeight, revealedWidth: revealedWidth),
            size: NSSize(width: Self.contentWidth, height: Self.contentHeight)
        )
    }

    private func cardOrigin(
        atEdge edge: EdgeHoverMonitor.HorizontalEdge,
        on screen: NSScreen,
        cursorHeight: CGFloat,
        revealedWidth: CGFloat
    ) -> NSPoint {
        let visible = screen.visibleFrame

        let x = switch edge {
        case .left: visible.minX - Self.contentWidth + revealedWidth
        case .right: visible.maxX - revealedWidth
        }

        var y = cursorHeight - Self.contentHeight / 2
        y = min(max(y, visible.minY + Self.edgeInset), visible.maxY - Self.contentHeight - Self.edgeInset)

        return NSPoint(x: x, y: y)
    }
}
