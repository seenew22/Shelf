import SwiftUI

/// 화면 가장자리에 마우스를 대서 창을 여는 기능의 설정값입니다.
enum EdgeHoverSide: String, CaseIterable, Identifiable, Sendable {
    case off
    case left
    case right
    case both

    var id: String { rawValue }

    var includesLeft: Bool { self == .left || self == .both }
    var includesRight: Bool { self == .right || self == .both }

    var stringKey: StringKey {
        switch self {
        case .off: .edgeOff
        case .left: .edgeLeft
        case .right: .edgeRight
        case .both: .edgeBoth
        }
    }
}

/// 창이 나타날 때의 움직임 종류입니다.
enum PanelAnimationStyle: String, CaseIterable, Identifiable, Sendable {
    /// 작은 방울이 부풀어 오르듯 모서리가 펴지면서 커집니다.
    case droplet
    /// 서랍을 빼내듯 한 방향으로 곧게 펼쳐집니다. 튀지 않고 차분합니다.
    case drawer
    /// 작은 크기에서 힘차게 튀어나옵니다. 가장 빠르고 활기찹니다.
    case pop
    /// 거의 움직이지 않고 조용히 나타납니다. 움직임이 거슬릴 때 고르시면 됩니다.
    case calm

    var id: String { rawValue }

    var stringKey: StringKey {
        switch self {
        case .droplet: .animationDroplet
        case .drawer: .animationDrawer
        case .pop: .animationPop
        case .calm: .animationCalm
        }
    }

    /// 창이 제자리에 도착하는 순간의 몸짓입니다.
    ///
    /// 크기 변화만으로는 네 방식이 결국 "크기가 다르게 변하는 사각형"으로 수렴합니다.
    /// 기울기와 눌림, 목록이 차례로 차오르는 정도까지 달리해야 성격이 갈립니다.
    var flourish: Flourish {
        switch self {
        // 젤리처럼 옆으로 퍼졌다가 되돌아옵니다.
        case .droplet: Flourish(tiltDegrees: 0, squash: CGSize(width: 1.18, height: 0.84), rowStagger: 0.022)
        // 서랍이 끝까지 밀려 들어가 멈추듯, 군더더기 없이 섭니다.
        case .drawer: Flourish(tiltDegrees: 0, squash: CGSize(width: 1.0, height: 1.0), rowStagger: 0)
        // 비스듬히 튀어나왔다가 바로 서면서 세로로 늘어납니다.
        case .pop: Flourish(tiltDegrees: -9, squash: CGSize(width: 0.80, height: 1.22), rowStagger: 0.04)
        // 아무 몸짓도 하지 않습니다.
        case .calm: Flourish(tiltDegrees: 0, squash: CGSize(width: 1.0, height: 1.0), rowStagger: 0)
        }
    }

    /// 도착하는 순간의 몸짓을 이루는 값들입니다.
    struct Flourish {
        /// 도착 직전의 기울기입니다. 0 이 아니면 비스듬히 나타났다가 바로 섭니다.
        var tiltDegrees: Double
        /// 도착 직전의 눌린 정도입니다. 가로로 퍼지거나 세로로 늘어난 채로 도착합니다.
        var squash: CGSize
        /// 목록의 항목이 하나씩 차오르는 간격입니다. 0 이면 한꺼번에 나타납니다.
        var rowStagger: TimeInterval
    }

    /// 물러날 때의 몸짓입니다. 나타날 때와 짝이 맞아야 같은 성격으로 읽힙니다.
    ///
    /// 기울기는 나타날 때와 반대로 줍니다. 들어올 때 왼쪽으로 기울었다면 나갈 때는
    /// 오른쪽으로 기울면서 물러나야, 한 번 왔다가 되돌아간 것처럼 보입니다.
    var departure: (tiltDegrees: Double, animation: Animation, duration: TimeInterval) {
        switch self {
        case .droplet: (0, .spring(duration: 0.28, bounce: 0.35), 0.28)
        case .drawer: (0, .easeIn(duration: 0.20), 0.20)
        case .pop: (13, .spring(duration: 0.24, bounce: 0.45), 0.24)
        case .calm: (0, .easeOut(duration: 0.14), 0.14)
        }
    }

    /// 도착한 뒤 제자리를 찾아가는 움직임입니다.
    var settle: Animation {
        switch self {
        case .droplet: .spring(duration: 0.54, bounce: 0.55)
        case .drawer: .spring(duration: 0.30, bounce: 0.12)
        case .pop: .spring(duration: 0.48, bounce: 0.72)
        case .calm: .easeOut(duration: 0.18)
        }
    }

    /// 화면 가장자리에서 미리 내밀어 두는 폭입니다. 이만큼이 잡는 자리가 됩니다.
    var edgeGripWidth: CGFloat {
        switch self {
        case .droplet: 30
        case .drawer: 24
        case .pop: 38
        case .calm: 22
        }
    }

    /// 마우스를 당긴 거리에 견주어 선반이 따라 나오는 비율입니다.
    /// 값이 클수록 손짓보다 크게 반응해서 가볍게 느껴지고, 작을수록 묵직하게 느껴집니다.
    var edgePullGain: CGFloat {
        switch self {
        case .droplet: 2.4
        case .drawer: 1.6
        case .pop: 3.4
        case .calm: 1.3
        }
    }

    /// 화면 가장자리에서 선반 끝이 처음 나올 때의 움직임입니다.
    var edgeReveal: (duration: TimeInterval, controlPoints: (Float, Float, Float, Float)) {
        switch self {
        case .droplet: (0.30, (0.25, 1.35, 0.40, 1))
        case .drawer: (0.34, (0.30, 0.00, 0.30, 1))
        case .pop: (0.18, (0.16, 1.90, 0.40, 1))
        case .calm: (0.36, (0.33, 0.00, 0.40, 1))
        }
    }

    /// 가장자리에서 꺼냈던 선반이 도로 들어가는 움직임입니다.
    ///
    /// 제어점의 두 번째 값을 음수로 두면, 들어가기 직전에 바깥쪽으로 살짝 부풀었다가
    /// 빨려 들어갑니다. 몸을 웅크렸다 튀어나가는 것과 같은 원리로, 되돌아가는 동작에
    /// 힘이 실려 보입니다.
    var edgeDeparture: (duration: TimeInterval, controlPoints: (Float, Float, Float, Float)) {
        switch self {
        case .droplet: (0.34, (0.55, -0.42, 0.72, 1))
        case .drawer: (0.26, (0.40, 0.00, 0.70, 1))
        case .pop: (0.24, (0.72, -0.75, 0.78, 1))
        case .calm: (0.20, (0.40, 0.00, 0.60, 1))
        }
    }

    /// 가장자리에서 잡아 뺀 선반이 제자리에 놓일 때의 움직임입니다.
    /// 제어점의 두 번째 값이 1을 넘으면 제자리를 지나쳤다가 되돌아옵니다.
    var edgeSnap: (duration: TimeInterval, controlPoints: (Float, Float, Float, Float)) {
        switch self {
        case .droplet: (0.42, (0.18, 1.62, 0.42, 1))
        case .drawer: (0.34, (0.22, 1.14, 0.36, 1))
        case .pop: (0.26, (0.14, 2.00, 0.36, 1))
        case .calm: (0.30, (0.25, 1.00, 0.35, 1))
        }
    }
}

/// 언어를 제외한 앱 설정을 담습니다.
@MainActor
final class Preferences: ObservableObject {

    private static let edgeHoverKey = "edgeHoverSide"
    private static let animationStyleKey = "panelAnimationStyle"

    /// 기본값은 사용 안 함입니다. 화면 끝을 스치기만 해도 창이 뜨면 거슬릴 수 있어서,
    /// 원하시는 분이 직접 켜도록 두었습니다.
    @Published var edgeHoverSide: EdgeHoverSide {
        didSet {
            guard edgeHoverSide != oldValue else { return }
            UserDefaults.standard.set(edgeHoverSide.rawValue, forKey: Self.edgeHoverKey)
            onEdgeHoverSideChanged?(edgeHoverSide)
        }
    }

    @Published var panelAnimationStyle: PanelAnimationStyle {
        didSet {
            guard panelAnimationStyle != oldValue else { return }
            UserDefaults.standard.set(panelAnimationStyle.rawValue, forKey: Self.animationStyleKey)
        }
    }

    /// 설정이 바뀌었을 때 감시자를 켜거나 끄기 위해 앱 쪽에서 연결해 둡니다.
    var onEdgeHoverSideChanged: ((EdgeHoverSide) -> Void)?

    init() {
        let storedSide = UserDefaults.standard.string(forKey: Self.edgeHoverKey)
        edgeHoverSide = storedSide.flatMap(EdgeHoverSide.init(rawValue:)) ?? .off

        let storedStyle = UserDefaults.standard.string(forKey: Self.animationStyleKey)
        panelAnimationStyle = storedStyle.flatMap(PanelAnimationStyle.init(rawValue:)) ?? .droplet
    }
}
