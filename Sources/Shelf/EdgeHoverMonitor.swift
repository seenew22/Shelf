import AppKit
import Foundation

/// 마우스가 화면 좌우 끝에 닿았는지 지켜보다가 알려 줍니다.
///
/// 곧바로 선반을 펼치지 않고 두 단계로 나눕니다. 먼저 가장자리에 잠깐 닿으면 작은 손잡이만
/// 내밀고, 그 상태에서 마우스를 안쪽으로 끌어당기면 그때 선반을 펼칩니다. 이렇게 하면
/// 화면 끝을 스쳐 지나갈 때 선반이 튀어나오는 일이 없고, 열리기 전에 예고가 한 번 들어갑니다.
///
/// 전역 마우스 감시자를 다는 대신 마우스 위치를 짧은 주기로 확인합니다.
/// 감시자는 마우스가 움직일 때마다 깨어나서 오히려 부담이 크고, 여기서 필요한 것은
/// "가장자리에 머물렀는가"와 "안쪽으로 끌어당겼는가"라는 판단이라 주기적으로 보는 편이
/// 더 잘 맞습니다. 손쉬운 사용 권한도 필요하지 않습니다.
@MainActor
final class EdgeHoverMonitor {

    /// 화면 끝에서 이 거리 안쪽까지를 가장자리로 봅니다.
    static let edgeThickness: CGFloat = 2

    /// 선반 가장자리를 내밀기까지 화면 끝에 머물러야 하는 시간입니다.
    /// Dock 이 화면을 옮겨 올 때처럼, 뜻이 있었다는 것은 알 수 있으면서 답답하지는 않은 정도입니다.
    static let peekDwellDuration: TimeInterval = 0.15

    /// 내밀어 둔 선반을 안쪽으로 이만큼 잡아당기면 완전히 꺼냅니다.
    static let pullCommitDistance: CGFloat = 64

    /// 끌어당기지 않고 가장자리에 계속 머물기만 해도, 이 시간이 지나면 선반을 펼칩니다.
    /// 1초 가까이 화면 끝에 마우스를 붙여 두는 일은 실수로 일어나지 않기 때문에,
    /// 끌어당기기가 번거로울 때의 다른 길로 열어 두었습니다.
    static let holdToOpenDuration: TimeInterval = 0.55

    /// 화면 높이 중에서 감지에 쓰는 구간의 비율입니다. 세로 한가운데를 기준으로 잡습니다.
    ///
    /// 가장자리 전체를 감지하면 방해가 되는 자리가 너무 많습니다. 브라우저의 뒤로 가기
    /// 버튼이나 사이드바처럼 화면 왼쪽 위에는 마우스가 자주 가고, 아래쪽 모서리는 마우스를
    /// 잠시 치워 두는 자리이자 macOS 핫코너가 쓰는 자리입니다. 가운데 절반만 열어 두면
    /// 그런 곳을 모두 비켜 가면서도 겨냥하기에는 충분히 넓습니다.
    static let activeHeightFraction: CGFloat = 0.5

    /// 끌어당기는 동안 허용하는 세로 방향 흔들림입니다.
    /// 이보다 크게 벗어나면 끌어당길 뜻이 없다고 보고 손잡이를 거둡니다.
    static let verticalTolerance: CGFloat = 60

    /// 마우스 위치를 확인하는 주기입니다.
    static let pollInterval: TimeInterval = 0.04

    /// 창이 열린 뒤, 마우스가 창에서 이만큼 벗어나면 치울 준비를 합니다.
    static let releaseMargin: CGFloat = 100

    /// 그만큼 벗어난 상태가 이 시간 동안 이어져야 창을 치웁니다.
    /// 잠깐 스쳐 벗어났다고 곧바로 사라지면 꺼내 놓은 물건이 도망가는 것처럼 느껴집니다.
    static let releaseDelay: TimeInterval = 0.8

    /// 가장자리에 잠깐 머물렀을 때 호출됩니다. 선반을 내밀 자리를 함께 넘깁니다.
    var onPeekBegan: ((HorizontalEdge, NSScreen, CGFloat) -> Void)?

    /// 잡아당기는 동안, 화면 끝에서 안쪽으로 들어온 거리를 계속 알려 줍니다.
    var onPullChanged: ((CGFloat) -> Void)?

    /// 내밀어 둔 선반을 도로 집어넣어야 할 때 호출됩니다.
    var onPeekCancelled: (() -> Void)?

    /// 선반을 완전히 꺼내야 할 때 호출됩니다.
    var onCommit: ((HorizontalEdge, NSScreen, CGFloat) -> Void)?

    /// 창이 열린 상태에서 마우스가 충분히 멀어졌을 때 호출됩니다.
    var onPointerLeft: (() -> Void)?

    enum HorizontalEdge {
        case left
        case right
    }

    /// 마우스가 가장자리에 대해 지금 어느 단계에 있는지를 나타냅니다.
    private enum Stage {
        /// 가장자리와 무관한 곳에 있습니다.
        case away
        /// 가장자리에 닿아 머무는 중입니다.
        case dwelling(edge: HorizontalEdge, screen: NSScreen, since: Date)
        /// 선반 가장자리가 나와 있고, 잡아당기거나 계속 머물기를 기다립니다.
        case peeking(edge: HorizontalEdge, screen: NSScreen, anchorHeight: CGFloat, since: Date)
        /// 방금 선반을 열었거나 닫았습니다. 가장자리를 벗어나기 전까지는 다시 반응하지 않습니다.
        case settling
    }

    private var side: EdgeHoverSide = .off
    private var timer: Timer?
    private var stage: Stage = .away

    /// 창이 지금 떠 있는지 여부입니다. 떠 있는 동안에는 가장자리를 감지하지 않습니다.
    private var isPanelVisible = false

    /// 가장자리로 열린 창의 위치입니다. 이 경우에만 마우스가 멀어졌을 때 스스로 닫습니다.
    /// 단축키나 메뉴 바 아이콘으로 연 창은 마우스와 무관하게 그대로 두어야 하므로 nil입니다.
    private var autoCloseFrame: NSRect?

    /// 마우스가 창에서 멀어진 시각입니다. 충분히 오래 멀어져 있어야 창을 치웁니다.
    private var pointerAwaySince: Date?

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
        pointerAwaySince = nil
        // 창이 닫힌 직후에 마우스가 아직 가장자리에 있다면 곧바로 다시 열리지 않도록 합니다.
        stage = .settling
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
        cancelPeekIfNeeded()
        stage = .away
    }

    // MARK: - 단계 판단

    private func check() {
        let location = NSEvent.mouseLocation

        // 창을 끌어다 화면 끝에 붙이는 중이라면 선반이 끼어들지 않아야 합니다.
        if NSEvent.pressedMouseButtons != 0, !isPanelVisible {
            cancelPeekIfNeeded()
            stage = .away
            return
        }

        if isPanelVisible {
            if let autoCloseFrame {
                checkWhetherPointerLeft(location, panelFrame: autoCloseFrame)
            }
            return
        }

        switch stage {
        case .settling:
            if edge(at: location) == nil {
                stage = .away
            }

        case .away:
            if let (edge, screen) = edge(at: location) {
                stage = .dwelling(edge: edge, screen: screen, since: Date())
            }

        case .dwelling(let edge, let screen, let since):
            guard let (currentEdge, _) = self.edge(at: location), currentEdge == edge else {
                stage = .away
                return
            }
            guard Date().timeIntervalSince(since) >= Self.peekDwellDuration else { return }
            stage = .peeking(edge: edge, screen: screen, anchorHeight: location.y, since: since)
            onPeekBegan?(edge, screen, location.y)

        case .peeking(let edge, let screen, let anchorHeight, let since):
            // 끌어당기지 않아도 충분히 오래 머물렀다면 그대로 펼칩니다.
            if Date().timeIntervalSince(since) >= Self.holdToOpenDuration,
               self.edge(at: location) != nil {
                commit(edge: edge, screen: screen, at: anchorHeight)
                return
            }
            evaluatePull(at: location, edge: edge, screen: screen, anchorHeight: anchorHeight)
        }
    }

    private func commit(edge: HorizontalEdge, screen: NSScreen, at height: CGFloat) {
        stage = .settling
        onCommit?(edge, screen, height)
    }

    /// 손잡이가 나와 있는 동안, 안쪽으로 끌어당겼는지 판단합니다.
    private func evaluatePull(
        at location: NSPoint,
        edge: HorizontalEdge,
        screen: NSScreen,
        anchorHeight: CGFloat
    ) {
        // 다른 화면으로 넘어갔거나 세로로 크게 벗어났다면 끌어당길 뜻이 없다고 봅니다.
        guard screen.frame.contains(location),
              abs(location.y - anchorHeight) <= Self.verticalTolerance
        else {
            cancelPeekIfNeeded()
            stage = .away
            return
        }

        let inwardDistance = switch edge {
        case .left: location.x - screen.frame.minX
        case .right: screen.frame.maxX - location.x
        }

        // 잡아당긴 만큼 선반이 따라 나오도록 거리를 계속 알려 줍니다.
        onPullChanged?(inwardDistance)

        guard inwardDistance >= Self.pullCommitDistance else { return }
        commit(edge: edge, screen: screen, at: anchorHeight)
    }

    private func cancelPeekIfNeeded() {
        if case .peeking = stage {
            onPeekCancelled?()
        }
    }

    /// 마우스가 어느 쪽 가장자리에 있는지 판단합니다.
    /// 설정에서 끈 쪽과, 다른 화면이 이어져 있는 안쪽 경계는 무시합니다.
    private func edge(at location: NSPoint) -> (HorizontalEdge, NSScreen)? {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(location) }) else {
            return nil
        }
        let frame = screen.frame

        // 세로 한가운데 구간에서만 반응합니다.
        let activeHeight = frame.height * Self.activeHeightFraction
        guard abs(location.y - frame.midY) <= activeHeight / 2 else {
            return nil
        }

        if side.includesLeft,
           location.x <= frame.minX + Self.edgeThickness,
           !hasAdjoiningScreen(beyondX: frame.minX - 1, atHeight: location.y) {
            return (.left, screen)
        }

        if side.includesRight,
           location.x >= frame.maxX - 1 - Self.edgeThickness,
           !hasAdjoiningScreen(beyondX: frame.maxX + 1, atHeight: location.y) {
            return (.right, screen)
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
        guard NSEvent.pressedMouseButtons == 0 else {
            pointerAwaySince = nil
            return
        }

        let forgivingFrame = panelFrame.insetBy(dx: -Self.releaseMargin, dy: -Self.releaseMargin)
        guard !forgivingFrame.contains(location) else {
            pointerAwaySince = nil
            return
        }

        guard let awaySince = pointerAwaySince else {
            pointerAwaySince = Date()
            return
        }
        guard Date().timeIntervalSince(awaySince) >= Self.releaseDelay else { return }

        pointerAwaySince = nil
        onPointerLeft?()
    }
}
