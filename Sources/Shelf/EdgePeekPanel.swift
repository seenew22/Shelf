import AppKit
import SwiftUI

/// 화면 가장자리에 마우스가 닿았을 때 살짝 내미는 작은 손잡이입니다.
///
/// 곧바로 선반을 펼치는 대신 이 손잡이를 먼저 보여 주면, 사용자는 "여기서 뭔가 나온다"는
/// 것을 미리 알고 원하지 않으면 그냥 지나갈 수 있습니다. 손잡이를 안쪽으로 끌어당기듯
/// 마우스를 옮기면 그때 선반이 펼쳐집니다.
final class EdgePeekPanel: NSPanel {

    /// 눈에 보이는 손잡이의 크기입니다.
    static let tabWidth: CGFloat = 13
    static let tabHeight: CGFloat = 86

    /// 그림자를 담을 여백입니다.
    static let shadowMargin: CGFloat = 12

    private var edge: EdgeHoverMonitor.HorizontalEdge = .left

    init() {
        super.init(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: Self.tabWidth + Self.shadowMargin * 2,
                height: Self.tabHeight + Self.shadowMargin * 2
            ),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .popUpMenu
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        animationBehavior = .none
        // 손잡이는 보여 주기만 할 뿐이므로, 그 아래에 있는 것을 누르는 데 방해가 되면 안 됩니다.
        ignoresMouseEvents = true

        contentView = NSHostingView(rootView: EdgePeekView(edge: edge))
    }

    /// 지정한 가장자리에 손잡이를 붙여서 보여 줍니다.
    func show(at edge: EdgeHoverMonitor.HorizontalEdge, on screen: NSScreen, centeredAt height: CGFloat) {
        self.edge = edge
        (contentView as? NSHostingView<EdgePeekView>)?.rootView = EdgePeekView(edge: edge)

        let visible = screen.visibleFrame
        let tabX = switch edge {
        case .left: visible.minX
        case .right: visible.maxX - Self.tabWidth
        }
        var tabY = height - Self.tabHeight / 2
        tabY = min(max(tabY, visible.minY), visible.maxY - Self.tabHeight)

        let destination = NSPoint(x: tabX - Self.shadowMargin, y: tabY - Self.shadowMargin)
        // 가장자리 바깥에서 살짝 밀려 나오도록 조금 어긋난 자리에서 시작합니다.
        let nudge: CGFloat = edge == .left ? -Self.tabWidth : Self.tabWidth
        setFrameOrigin(NSPoint(x: destination.x + nudge, y: destination.y))
        alphaValue = 0
        orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().setFrameOrigin(destination)
            animator().alphaValue = 1
        }
    }

    func hide() {
        guard isVisible else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.10
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.alphaValue == 0 else { return }
                self.orderOut(nil)
                self.alphaValue = 1
            }
        }
    }
}

/// 손잡이의 생김새입니다. 안쪽을 가리키는 화살표로 "끌어당기면 열린다"를 알립니다.
private struct EdgePeekView: View {
    let edge: EdgeHoverMonitor.HorizontalEdge

    var body: some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(.regularMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
            }
            .overlay {
                Image(systemName: edge == .left ? "chevron.right" : "chevron.left")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: EdgePeekPanel.tabWidth, height: EdgePeekPanel.tabHeight)
            .shadow(color: .black.opacity(0.24), radius: 6, x: edge == .left ? 3 : -3)
            .padding(EdgePeekPanel.shadowMargin)
    }
}
