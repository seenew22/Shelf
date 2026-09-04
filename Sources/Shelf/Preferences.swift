import Foundation

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
