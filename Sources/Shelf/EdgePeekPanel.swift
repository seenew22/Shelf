import AppKit
import QuartzCore
import SwiftUI

/// 화면 가장자리에 마우스가 닿았을 때 살짝 내미는 손잡이입니다.
///
/// 곧바로 선반을 펼치는 대신 이 손잡이를 먼저 보여 주면, 사용자는 "여기서 뭔가 나온다"는
/// 것을 미리 알고 원하지 않으면 그냥 지나갈 수 있습니다. 손잡이를 안쪽으로 끌어당기듯
/// 마우스를 옮기면 그때 선반이 펼쳐집니다.
///
/// 눈에 확실히 띄어야 제 역할을 하므로, 배경이 비치는 재질 대신 강조색으로 채웁니다.
/// 화면 끝에 옅게 걸쳐 있으면 무엇이 나타났는지 알아볼 수 없습니다.
final class EdgePeekPanel: NSPanel {

    /// 눈에 보이는 손잡이의 크기입니다.
    static let tabWidth: CGFloat = 22
    static let tabHeight: CGFloat = 112

    /// 그림자를 담을 여백입니다.
    static let shadowMargin: CGFloat = 16

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
        // 화면 끝 너머에 숨어 있다가 밀려 나오는 것처럼 보이도록 살짝 어긋난 자리에서 시작합니다.
        let nudge: CGFloat = edge == .left ? -Self.tabWidth : Self.tabWidth
        setFrameOrigin(NSPoint(x: destination.x + nudge, y: destination.y))
        alphaValue = 0
        orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.17
            // 제자리를 지나쳤다가 돌아오게 해서 튕겨 나오는 느낌을 줍니다.
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.24, 1.8, 0.5, 1)
            animator().setFrameOrigin(destination)
            animator().alphaValue = 1
        }
    }

    func hide() {
        guard isVisible else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.09
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

/// 손잡이의 생김새입니다.
///
/// 화면 끝에 붙는 쪽은 각지게, 안쪽을 향하는 쪽만 둥글게 해서 화면에서 자라난 것처럼 보이게 합니다.
/// 안쪽을 가리키는 화살표로 "끌어당기면 열린다"를 알립니다.
private struct EdgePeekView: View {
    let edge: EdgeHoverMonitor.HorizontalEdge

    private var shape: UnevenRoundedRectangle {
        let radius: CGFloat = 8
        return switch edge {
        case .left:
            UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0,
                                   bottomTrailingRadius: radius, topTrailingRadius: radius)
        case .right:
            UnevenRoundedRectangle(topLeadingRadius: radius, bottomLeadingRadius: radius,
                                   bottomTrailingRadius: 0, topTrailingRadius: 0)
        }
    }

    var body: some View {
        shape
            .fill(
                LinearGradient(
                    colors: [Color.accentColor, Color.accentColor.opacity(0.82)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay {
                Image(systemName: edge == .left ? "chevron.right" : "chevron.left")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: EdgePeekPanel.tabWidth, height: EdgePeekPanel.tabHeight)
            .shadow(color: .black.opacity(0.35), radius: 8, x: edge == .left ? 4 : -4, y: 1)
            .padding(EdgePeekPanel.shadowMargin)
    }
}
