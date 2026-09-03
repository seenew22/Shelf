import AppKit
import QuartzCore
import SwiftUI

/// 손잡이의 현재 모습을 담습니다. 끌어당긴 정도에 따라 화면이 따라 움직입니다.
@MainActor
final class EdgePeekState: ObservableObject {
    @Published var edge: EdgeHoverMonitor.HorizontalEdge = .left

    /// 끌어당김이 얼마나 진행되었는지를 0에서 1 사이로 나타냅니다.
    @Published var pullProgress: CGFloat = 0
}

/// 화면 가장자리에 마우스가 닿았을 때 내미는 손잡이입니다.
///
/// 곧바로 선반을 펼치는 대신 이 손잡이를 먼저 보여 주면, 사용자는 "여기서 뭔가 나온다"는
/// 것을 미리 알고 원하지 않으면 그냥 지나갈 수 있습니다.
///
/// 손잡이는 가만히 있지 않고 **끌어당기는 만큼 안쪽으로 늘어납니다.** 가만히 있다가
/// 어느 순간 사라지고 창이 뜨면 두 동작이 이어져 보이지 않지만, 늘어나는 모습을 보여 주면
/// 옆으로 잡아 빼는 동작이라는 것이 설명 없이도 전달됩니다.
final class EdgePeekPanel: NSPanel {

    /// 아직 끌어당기지 않았을 때의 손잡이 폭입니다.
    static let tabWidth: CGFloat = 26

    /// 끝까지 끌어당겼을 때 여기에 더해지는 폭입니다.
    static let maximumStretch: CGFloat = 46

    static let tabHeight: CGFloat = 130

    /// 그림자를 담을 여백입니다.
    static let shadowMargin: CGFloat = 18

    private let state = EdgePeekState()

    init() {
        super.init(
            contentRect: NSRect(
                x: 0,
                y: 0,
                // 늘어날 자리까지 미리 확보해 두면 창 크기를 바꾸지 않고도 손잡이만 자랄 수 있습니다.
                width: Self.tabWidth + Self.maximumStretch + Self.shadowMargin * 2,
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

        contentView = NSHostingView(rootView: EdgePeekView(state: state))
    }

    /// 지정한 가장자리에 손잡이를 붙여서 보여 줍니다.
    func show(at edge: EdgeHoverMonitor.HorizontalEdge, on screen: NSScreen, centeredAt height: CGFloat) {
        state.edge = edge
        state.pullProgress = 0

        let visible = screen.visibleFrame
        // 창은 늘어날 자리까지 포함하므로, 가장자리 쪽 끝을 화면 끝에 맞춥니다.
        let windowX = switch edge {
        case .left: visible.minX - Self.shadowMargin
        case .right: visible.maxX - frame.width + Self.shadowMargin
        }
        var tabY = height - Self.tabHeight / 2
        tabY = min(max(tabY, visible.minY), visible.maxY - Self.tabHeight)

        let destination = NSPoint(x: windowX, y: tabY - Self.shadowMargin)
        // 화면 끝 너머에 숨어 있다가 밀려 나오는 것처럼 보이도록 살짝 어긋난 자리에서 시작합니다.
        let nudge: CGFloat = edge == .left ? -Self.tabWidth : Self.tabWidth
        setFrameOrigin(NSPoint(x: destination.x + nudge, y: destination.y))
        alphaValue = 0
        orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.13
            // 제자리를 지나쳤다가 돌아오게 해서 튕겨 나오는 느낌을 줍니다.
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.24, 1.8, 0.5, 1)
            animator().setFrameOrigin(destination)
            animator().alphaValue = 1
        }
    }

    /// 끌어당긴 정도를 반영해서 손잡이를 늘립니다.
    ///
    /// 마우스 위치는 일정 주기로만 확인하므로 값이 띄엄띄엄 들어옵니다.
    /// 짧은 애니메이션으로 그 사이를 메워서 끊겨 보이지 않게 합니다.
    func updatePull(progress: CGFloat) {
        withAnimation(.easeOut(duration: 0.06)) {
            state.pullProgress = min(max(progress, 0), 1)
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
                self.state.pullProgress = 0
            }
        }
    }
}

/// 손잡이의 생김새입니다.
///
/// 화면 끝에 붙는 쪽은 각지게, 안쪽을 향하는 쪽만 둥글게 해서 화면에서 자라난 것처럼 보이게 합니다.
/// 화살표는 가만히 있지 않고 안쪽으로 천천히 오갑니다. 잡아당기라는 뜻을 알리기 위한 것입니다.
private struct EdgePeekView: View {
    @ObservedObject var state: EdgePeekState
    @State private var isNudging = false

    private var width: CGFloat {
        EdgePeekPanel.tabWidth + EdgePeekPanel.maximumStretch * state.pullProgress
    }

    private var shape: UnevenRoundedRectangle {
        let radius: CGFloat = 10
        return switch state.edge {
        case .left:
            UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0,
                                   bottomTrailingRadius: radius, topTrailingRadius: radius)
        case .right:
            UnevenRoundedRectangle(topLeadingRadius: radius, bottomLeadingRadius: radius,
                                   bottomTrailingRadius: 0, topTrailingRadius: 0)
        }
    }

    /// 안쪽을 향하는 방향입니다. 왼쪽 가장자리에서는 오른쪽이 안쪽입니다.
    private var inwardSign: CGFloat {
        state.edge == .left ? 1 : -1
    }

    var body: some View {
        shape
            .fill(
                LinearGradient(
                    colors: [Color.accentColor, Color.accentColor.opacity(0.78)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay {
                shape.strokeBorder(Color.white.opacity(0.28), lineWidth: 1)
            }
            .overlay {
                Image(systemName: state.edge == .left ? "chevron.compact.right" : "chevron.compact.left")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .offset(x: inwardSign * (isNudging ? 3 : -1))
            }
            .frame(width: width, height: EdgePeekPanel.tabHeight)
            .shadow(color: .black.opacity(0.5), radius: 12, x: inwardSign * 5, y: 2)
            .shadow(color: .black.opacity(0.3), radius: 3, x: inwardSign * 1)
            .frame(
                maxWidth: .infinity,
                alignment: state.edge == .left ? .leading : .trailing
            )
            .padding(EdgePeekPanel.shadowMargin)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    isNudging = true
                }
            }
    }
}
