import SwiftUI

/// 창이 나타나고 사라지는 움직임의 상태를 담습니다.
///
/// 창 자체(`NSWindow`)의 크기를 애니메이션하는 대신, 창 안의 내용물을 확대·축소합니다.
/// 창 프레임을 움직이면 화면 밖으로 밀려나거나 그림자가 따라오지 못하는 문제가 있는데,
/// 내용물 쪽에서 처리하면 원하는 지점에서 자라나는 모양을 그대로 만들 수 있습니다.
///
/// 크기와 투명도는 서로 다른 속도로 움직입니다. 같은 스프링에 묶어 두면 투명도가
/// 순식간에 채워져서, 자라나는 과정은 보이지 않고 깜빡하고 나타난 것처럼 보입니다.
@MainActor
final class PanelPresentation: ObservableObject {

    /// 사라지는 데 걸리는 시간입니다. 창을 실제로 감추는 시점을 맞추는 데도 씁니다.
    static let collapseDuration: TimeInterval = 0.16

    @Published private(set) var scaleX: CGFloat = 0.7
    @Published private(set) var scaleY: CGFloat = 0.7
    @Published private(set) var opacity: Double = 0

    /// 자라나기 시작하는 기준점입니다. 열린 방향 쪽 모서리를 잡아 두면
    /// 그 지점에서 펼쳐지는 것처럼 보입니다.
    @Published private(set) var anchor: UnitPoint = .center

    private var collapsedScale = CGSize(width: 0.7, height: 0.7)

    func expand(from origin: ShelfPanel.SlideOrigin) {
        anchor = origin.anchor
        collapsedScale = Self.collapsedScale(for: origin)

        // 접힌 모습에서 시작합니다.
        scaleX = collapsedScale.width
        scaleY = collapsedScale.height
        opacity = 0

        // 접힌 모습이 한 번 그려진 다음에 펼쳐야 움직임이 보입니다.
        // 같은 차례에 이어서 값을 바꾸면 SwiftUI 가 중간 상태를 건너뛰고
        // 곧바로 완성된 모습을 그려서, 깜빡하고 나타난 것처럼 보입니다.
        Task { @MainActor [weak self] in
            guard let self else { return }
            // 제자리를 한 번 지나쳤다가 되돌아오는 탄성으로 펼쳐집니다.
            withAnimation(.spring(duration: 0.44, bounce: 0.34)) {
                self.scaleX = 1
                self.scaleY = 1
            }
            // 투명도는 따로, 더 차분하게 채웁니다.
            withAnimation(.easeOut(duration: 0.26)) {
                self.opacity = 1
            }
        }
    }

    func collapse() {
        withAnimation(.easeIn(duration: Self.collapseDuration)) {
            scaleX = collapsedScale.width
            scaleY = collapsedScale.height
            opacity = 0
        }
    }

    /// 열린 방향에 따라 어떤 모양으로 접혀 있다가 펼쳐질지 정합니다.
    ///
    /// 화면 가장자리에서는 서랍을 옆으로 빼내듯 가로로 펼쳐지는 편이 자연스럽고,
    /// 메뉴 바에서는 차양이 내려오듯 세로로 펼쳐지는 편이 자연스럽습니다.
    private static func collapsedScale(for origin: ShelfPanel.SlideOrigin) -> CGSize {
        switch origin {
        case .leadingEdge, .trailingEdge: CGSize(width: 0.28, height: 0.88)
        case .above: CGSize(width: 0.88, height: 0.30)
        case .cursor: CGSize(width: 0.72, height: 0.72)
        }
    }
}
