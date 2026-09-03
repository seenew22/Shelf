import AppKit
import Foundation

/// 마우스가 화면 좌우 끝에 닿았는지 지켜보다가 알려 줍니다.
///
/// 전역 마우스 감시자를 다는 대신 마우스 위치를 짧은 주기로 확인합니다.
/// 감시자는 마우스가 움직일 때마다 깨어나서 오히려 부담이 크고, 여기서 필요한 것은
/// "가장자리에 잠시 머물렀는가"라는 판단이라 주기적으로 보는 편이 더 잘 맞습니다.
/// 손쉬운 사용 권한도 필요하지 않습니다.
@MainActor
final class EdgeHoverMonitor {

    /// 화면 끝에서 이 거리 안쪽까지를 가장자리로 봅니다.
    static let edgeThickness: CGFloat = 2

    /// 가장자리에 이만큼 머물러야 창을 엽니다. 지나가다 스치는 경우와 구분하기 위한 값입니다.
    static let dwellDuration: TimeInterval = 0.25

    /// 마우스 위치를 확인하는 주기입니다.
    static let pollInterval: TimeInterval = 0.06

    /// 창이 열린 뒤, 마우스가 창에서 이만큼 벗어나면 다시 닫습니다.
    static let releaseMargin: CGFloat = 48

    /// 가장자리에 머물렀을 때 호출됩니다. 어느 쪽 끝인지와 그 화면을 함께 넘깁니다.
    var onEdgeReached: ((HorizontalEdge, NSScreen, NSPoint) -> Void)?

    /// 창이 열린 상태에서 마우스가 충분히 멀어졌을 때 호출됩니다.
    var onPointerLeft: (() -> Void)?

    enum HorizontalEdge {
        case left
        case right
    }

    private var side: EdgeHoverSide = .off
    private var timer: Timer?

    /// 가장자리에 처음 닿은 시각입니다. 머문 시간을 재는 데 씁니다.
    private var edgeEntryDate: Date?

    /// 한 번 연 뒤에는 마우스가 가장자리를 벗어나기 전까지 다시 열지 않습니다.
    private var isWaitingForPointerToLeaveEdge = false

    /// 창이 지금 떠 있는지 여부입니다. 떠 있는 동안에는 가장자리를 감지해도 다시 열지 않습니다.
    private var isPanelVisible = false

    /// 가장자리로 열린 창의 위치입니다. 이 경우에만 마우스가 멀어졌을 때 스스로 닫습니다.
    /// 단축키나 메뉴 바 아이콘으로 연 창은 마우스와 무관하게 그대로 두어야 하므로 nil입니다.
    private var autoCloseFrame: NSRect?

    func update(side newSide: EdgeHoverSide) {
        side = newSide
        if newSide == .off {
            stop()
        } else {
            start()
        }
    }

    /// 창이 열리고 닫힐 때마다 앱 쪽에서 알려 줍니다.
    /// - Parameters:
    ///   - isVisible: 창이 떠 있는지 여부입니다.
    ///   - autoCloseFrame: 가장자리로 연 창의 위치입니다. 다른 방법으로 열었다면 nil을 넘깁니다.
    func panelDidChangeVisibility(isVisible: Bool, autoCloseFrame: NSRect?) {
        self.isPanelVisible = isVisible
        self.autoCloseFrame = isVisible ? autoCloseFrame : nil
        if !isVisible {
            edgeEntryDate = nil
        }
    }

    private func start() {
        guard timer == nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.check()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        edgeEntryDate = nil
        isWaitingForPointerToLeaveEdge = false
    }

    private func check() {
        let location = NSEvent.mouseLocation

        if isPanelVisible {
            if let autoCloseFrame {
                checkWhetherPointerLeft(location, panelFrame: autoCloseFrame)
            }
            // 창이 떠 있는 동안에는 가장자리를 감지해도 다시 열지 않습니다.
            return
        }

        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(location) }) else {
            edgeEntryDate = nil
            isWaitingForPointerToLeaveEdge = false
            return
        }

        guard let edge = edge(at: location, on: screen) else {
            edgeEntryDate = nil
            isWaitingForPointerToLeaveEdge = false
            return
        }

        // 직전에 창을 연 뒤 아직 가장자리를 벗어나지 않았다면 다시 열지 않습니다.
        guard !isWaitingForPointerToLeaveEdge else { return }

        guard let entry = edgeEntryDate else {
            edgeEntryDate = Date()
            return
        }

        guard Date().timeIntervalSince(entry) >= Self.dwellDuration else { return }

        edgeEntryDate = nil
        isWaitingForPointerToLeaveEdge = true
        onEdgeReached?(edge, screen, location)
    }

    /// 마우스가 어느 쪽 가장자리에 있는지 판단합니다.
    /// 설정에서 끈 쪽과, 다른 화면이 이어져 있는 안쪽 경계는 무시합니다.
    private func edge(at location: NSPoint, on screen: NSScreen) -> HorizontalEdge? {
        let frame = screen.frame

        if side.includesLeft,
           location.x <= frame.minX + Self.edgeThickness,
           !hasAdjoiningScreen(beyondX: frame.minX - 1, atHeight: location.y) {
            return .left
        }

        if side.includesRight,
           location.x >= frame.maxX - 1 - Self.edgeThickness,
           !hasAdjoiningScreen(beyondX: frame.maxX + 1, atHeight: location.y) {
            return .right
        }

        return nil
    }

    /// 그 방향에 다른 화면이 이어져 있는지 확인합니다.
    ///
    /// 모니터를 나란히 놓으면 두 화면이 맞닿은 경계는 마우스가 그냥 통과하는 통로가 됩니다.
    /// 거기서 선반이 열리면 화면을 오갈 때마다 방해가 되므로, 바깥쪽으로 더 이상 화면이 없는
    /// 진짜 끝에서만 반응하게 합니다. 맞닿은 높이만 따지므로, 화면 높이가 서로 달라서
    /// 일부만 겹치는 배치에서는 겹치지 않는 구간에서 정상적으로 열립니다.
    private func hasAdjoiningScreen(beyondX x: CGFloat, atHeight y: CGFloat) -> Bool {
        let probe = NSPoint(x: x, y: y)
        return NSScreen.screens.contains { $0.frame.contains(probe) }
    }

    /// 창이 떠 있는 동안, 마우스가 충분히 멀어졌으면 닫도록 알립니다.
    ///
    /// 항목을 끌고 있는 중에는 닫지 않습니다. 드래그로 다른 앱에 떨구려면 마우스가
    /// 창 밖으로 나가는 것이 당연하기 때문입니다.
    private func checkWhetherPointerLeft(_ location: NSPoint, panelFrame: NSRect) {
        guard NSEvent.pressedMouseButtons == 0 else { return }
        let forgivingFrame = panelFrame.insetBy(dx: -Self.releaseMargin, dy: -Self.releaseMargin)
        guard !forgivingFrame.contains(location) else { return }
        onPointerLeft?()
    }
}
