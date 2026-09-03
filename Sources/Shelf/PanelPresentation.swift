import SwiftUI

/// 창이 나타나고 사라지는 움직임의 상태를 담습니다.
///
/// 창 자체(`NSWindow`)의 크기를 애니메이션하는 대신, 창 안의 내용물을 확대·축소합니다.
/// 창 프레임을 움직이면 화면 밖으로 밀려나거나 그림자가 따라오지 못하는 문제가 있는데,
/// 내용물 쪽에서 처리하면 원하는 지점에서 자라나는 모양을 그대로 만들 수 있습니다.
@MainActor
final class PanelPresentation: ObservableObject {

    /// 접힌 상태에서의 크기 비율입니다. 이 크기에서 시작해 제자리 크기로 자랍니다.
    static let collapsedScale: CGFloat = 0.82

    /// 사라지는 데 걸리는 시간입니다. 창을 실제로 감추는 시점을 맞추는 데도 씁니다.
    static let collapseDuration: TimeInterval = 0.14

    @Published private(set) var isExpanded = false

    /// 자라나기 시작하는 기준점입니다. 열린 방향 쪽 모서리를 잡아 두면
    /// 그 지점에서 튀어나오는 것처럼 보입니다.
    @Published private(set) var anchor: UnitPoint = .center

    func expand(from anchor: UnitPoint) {
        self.anchor = anchor
        // 살짝 지나쳤다가 제자리로 돌아오는 탄성을 주어 튀어나오는 느낌을 만듭니다.
        withAnimation(.spring(response: 0.30, dampingFraction: 0.68)) {
            isExpanded = true
        }
    }

    func collapse() {
        withAnimation(.easeIn(duration: Self.collapseDuration)) {
            isExpanded = false
        }
    }
}
