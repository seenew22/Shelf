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

/// 언어를 제외한 앱 설정을 담습니다.
@MainActor
final class Preferences: ObservableObject {

    private static let edgeHoverKey = "edgeHoverSide"

    /// 기본값은 사용 안 함입니다. 화면 끝을 스치기만 해도 창이 뜨면 거슬릴 수 있어서,
    /// 원하시는 분이 직접 켜도록 두었습니다.
    @Published var edgeHoverSide: EdgeHoverSide {
        didSet {
            guard edgeHoverSide != oldValue else { return }
            UserDefaults.standard.set(edgeHoverSide.rawValue, forKey: Self.edgeHoverKey)
            onEdgeHoverSideChanged?(edgeHoverSide)
        }
    }

    /// 설정이 바뀌었을 때 감시자를 켜거나 끄기 위해 앱 쪽에서 연결해 둡니다.
    var onEdgeHoverSideChanged: ((EdgeHoverSide) -> Void)?

    init() {
        let stored = UserDefaults.standard.string(forKey: Self.edgeHoverKey)
        edgeHoverSide = stored.flatMap(EdgeHoverSide.init(rawValue:)) ?? .off
    }
}
