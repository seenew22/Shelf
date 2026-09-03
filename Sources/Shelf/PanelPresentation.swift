import SwiftUI

/// 창이 나타나고 사라지는 움직임의 상태를 담습니다.
///
/// 창 자체(`NSWindow`)의 크기를 애니메이션하는 대신, 창 안의 내용물을 확대·축소합니다.
/// 창 프레임을 움직이면 화면 밖으로 밀려나거나 그림자가 따라오지 못하는 문제가 있는데,
/// 내용물 쪽에서 처리하면 원하는 지점에서 자라나는 모양을 그대로 만들 수 있습니다.
///
/// 물방울이 부풀어 오르듯 보이도록 네 가지를 함께 움직입니다.
/// 작은 크기에서 시작해 커지고, 그동안 둥글던 모서리가 펴지며, 흐릿하던 상이 또렷해지고,
/// 투명하던 것이 채워집니다. 넷을 같은 속도로 묶으면 그냥 커지기만 하는 것처럼 보이므로
/// 각각 다른 속도로 움직입니다. 가로와 세로의 탄성을 살짝 다르게 준 것도 같은 이유로,
/// 방울이 출렁이는 듯한 인상을 만듭니다.
@MainActor
final class PanelPresentation: ObservableObject {

    /// 사라지는 데 걸리는 시간입니다. 창을 실제로 감추는 시점을 맞추는 데도 씁니다.
    static let collapseDuration: TimeInterval = 0.17

    /// 다 펼쳐졌을 때의 모서리 둥글기입니다.
    static let expandedCornerRadius: CGFloat = 12

    /// 접혀 있을 때의 모서리 둥글기입니다.
    /// 카드 폭의 절반을 넘도록 크게 잡으면 작게 줄어든 카드가 동그란 방울처럼 보입니다.
    static let collapsedCornerRadius: CGFloat = 180

    @Published private(set) var scaleX: CGFloat = 0.2
    @Published private(set) var scaleY: CGFloat = 0.2
    @Published private(set) var opacity: Double = 0
    @Published private(set) var cornerRadius: CGFloat = collapsedCornerRadius
    @Published private(set) var blurRadius: CGFloat = 8

    /// 자라나기 시작하는 기준점입니다. 열린 방향 쪽 모서리를 잡아 두면
    /// 그 지점에서 부풀어 오르는 것처럼 보입니다.
    @Published private(set) var anchor: UnitPoint = .center

    private var collapsedScale = CGSize(width: 0.2, height: 0.2)

    func expand(from origin: ShelfPanel.SlideOrigin) {
        anchor = origin.anchor
        collapsedScale = Self.collapsedScale(for: origin)
        applyCollapsedState()

        // 접힌 모습이 한 번 그려진 다음에 펼쳐야 움직임이 보입니다.
        // 같은 차례에 이어서 값을 바꾸면 SwiftUI 가 중간 상태를 건너뛰고
        // 곧바로 완성된 모습을 그려서, 깜빡하고 나타난 것처럼 보입니다.
        Task { @MainActor [weak self] in
            self?.animateToExpandedState()
        }
    }

    func collapse() {
        withAnimation(.easeIn(duration: Self.collapseDuration)) {
            scaleX = collapsedScale.width
            scaleY = collapsedScale.height
            opacity = 0
            cornerRadius = Self.collapsedCornerRadius
            blurRadius = 8
        }
    }

    private func applyCollapsedState() {
        scaleX = collapsedScale.width
        scaleY = collapsedScale.height
        opacity = 0
        cornerRadius = Self.collapsedCornerRadius
        blurRadius = 8
    }

    private func animateToExpandedState() {
        // 가로와 세로에 서로 다른 탄성을 주면 한쪽이 먼저 도착했다가 다른 쪽이 따라오면서
        // 방울이 출렁이는 듯한 인상이 생깁니다.
        withAnimation(.spring(duration: 0.46, bounce: 0.46)) {
            scaleX = 1
        }
        withAnimation(.spring(duration: 0.54, bounce: 0.36)) {
            scaleY = 1
        }
        // 모서리는 크기보다 조금 늦게 펴져서, 다 커진 뒤에 형태가 잡히는 것처럼 보입니다.
        withAnimation(.spring(duration: 0.52, bounce: 0.2)) {
            cornerRadius = Self.expandedCornerRadius
        }
        withAnimation(.easeOut(duration: 0.24)) {
            opacity = 1
            blurRadius = 0
        }
    }

    /// 열린 방향에 따라 어떤 모양으로 접혀 있다가 펼쳐질지 정합니다.
    ///
    /// 화면 가장자리에서는 서랍을 옆으로 빼내듯 가로로 더 크게 자라나고,
    /// 메뉴 바에서는 차양이 내려오듯 세로로 더 크게 자라납니다.
    private static func collapsedScale(for origin: ShelfPanel.SlideOrigin) -> CGSize {
        switch origin {
        case .leadingEdge, .trailingEdge: CGSize(width: 0.10, height: 0.30)
        case .above: CGSize(width: 0.34, height: 0.10)
        case .cursor: CGSize(width: 0.16, height: 0.16)
        }
    }
}
