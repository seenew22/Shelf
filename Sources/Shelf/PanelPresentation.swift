import SwiftUI

/// 다 펼쳐졌을 때의 모서리 둥글기입니다.
let panelExpandedCornerRadius: CGFloat = 12

/// 창이 나타나고 사라지는 움직임의 상태를 담습니다.
///
/// 창 자체(`NSWindow`)의 크기를 애니메이션하는 대신, 창 안의 내용물을 확대·축소합니다.
/// 창 프레임을 움직이면 화면 밖으로 밀려나거나 그림자가 따라오지 못하는 문제가 있는데,
/// 내용물 쪽에서 처리하면 원하는 지점에서 자라나는 모양을 그대로 만들 수 있습니다.
///
/// 움직이는 값은 크기·모서리 둥글기·흐림·투명도 네 가지이며, 각각 다른 속도로 움직입니다.
/// 넷을 같은 속도로 묶으면 어떤 방식을 고르든 "그냥 커진다"로 수렴해 버립니다.
@MainActor
final class PanelPresentation: ObservableObject {

    /// 다 펼쳐졌을 때의 모서리 둥글기입니다.
    static var expandedCornerRadius: CGFloat { panelExpandedCornerRadius }

    @Published private(set) var scaleX: CGFloat = 1
    @Published private(set) var scaleY: CGFloat = 1
    @Published private(set) var opacity: Double = 0
    @Published private(set) var cornerRadius: CGFloat = panelExpandedCornerRadius
    @Published private(set) var blurRadius: CGFloat = 0

    /// 자라나기 시작하는 기준점입니다. 열린 방향 쪽 모서리를 잡아 두면
    /// 그 지점에서 부풀어 오르는 것처럼 보입니다.
    @Published private(set) var anchor: UnitPoint = .center

    /// 도착 직전의 기울기입니다. 바로 서면서 0 이 됩니다.
    @Published private(set) var rotation: Angle = .zero

    /// 경첩을 축으로 접혀 있는 각도입니다. 활짝 열리면서 0 이 됩니다.
    @Published private(set) var openAngle: Angle = .zero

    /// 목록이 얼마나 차올랐는지를 0에서 1 사이로 나타냅니다.
    /// 각 행은 자기 순서에 맞춰 이 값에서 자기 몫을 계산합니다.
    @Published private(set) var contentPhase: Double = 1

    /// 행이 하나씩 차오르는 간격입니다. 0 이면 한꺼번에 나타납니다.
    private(set) var rowStagger: TimeInterval = 0

    /// 지금 고른 방식으로 창을 감추는 데 걸리는 시간입니다.
    /// 창을 실제로 화면에서 내리는 시점을 맞추는 데 씁니다.
    private(set) var collapseDuration: TimeInterval = 0.17

    private var collapsedState = CollapsedState.neutral

    func expand(from origin: ShelfPanel.SlideOrigin, style: PanelAnimationStyle) {
        let recipe = Recipe.forStyle(style)
        let flourish = style.flourish
        anchor = origin.anchor
        collapsedState = recipe.collapsedState(for: origin)
        collapseDuration = recipe.collapseDuration
        rowStagger = flourish.rowStagger
        applyCollapsedState()
        rotation = .degrees(flourish.tiltDegrees)
        openAngle = .degrees(flourish.openDegrees)
        contentPhase = flourish.rowStagger > 0 ? 0 : 1

        // 접힌 모습이 한 번 그려진 다음에 펼쳐야 움직임이 보입니다.
        // 같은 차례에 이어서 값을 바꾸면 SwiftUI 가 중간 상태를 건너뛰고
        // 곧바로 완성된 모습을 그려서, 깜빡하고 나타난 것처럼 보입니다.
        Task { @MainActor [weak self] in
            self?.animateToExpandedState(with: recipe, settle: style.settle)
        }
    }

    /// 가장자리에서 잡아 뺀 선반이 제자리에 닿는 순간의 몸짓입니다.
    ///
    /// 잡아당기는 동안에는 창 자체가 손을 따라 움직이므로 내용물을 건드리지 않습니다.
    /// 대신 다 꺼내진 그 순간에만 기울기와 눌림을 주어서, 방식마다 착지가 다르게 느껴지게 합니다.
    func land(with style: PanelAnimationStyle, hingedAt hinge: UnitPoint) {
        let flourish = style.flourish
        // 문이 열리듯 펼쳐지는 방식에서는 경첩이 화면 끝 쪽에 있어야 자연스럽습니다.
        anchor = flourish.openDegrees == 0 ? .center : hinge
        rowStagger = flourish.rowStagger

        opacity = 1
        blurRadius = 0
        cornerRadius = panelExpandedCornerRadius
        rotation = .degrees(flourish.tiltDegrees)
        openAngle = .degrees(flourish.openDegrees)
        scaleX = flourish.squash.width
        scaleY = flourish.squash.height
        contentPhase = flourish.rowStagger > 0 ? 0 : 1

        collapsedState = CollapsedState(
            scale: CGSize(width: 1, height: 1),
            cornerRadius: panelExpandedCornerRadius,
            blurRadius: 0
        )
        collapseDuration = 0.12

        Task { @MainActor [weak self] in
            self?.settle(with: style.settle, stagger: flourish.rowStagger)
        }
    }

    private func settle(with animation: Animation, stagger: TimeInterval) {
        withAnimation(animation) {
            rotation = .zero
            openAngle = .zero
            scaleX = 1
            scaleY = 1
        }
        guard stagger > 0 else { return }
        withAnimation(.easeOut(duration: 0.5)) {
            contentPhase = 1
        }
    }

    /// 움직임 없이 곧바로 온전한 모습으로 둡니다.
    ///
    /// 가장자리에서 잡아 빼는 동안에는 창 자체가 움직이면서 드러나므로,
    /// 내용물까지 따로 커지면 두 움직임이 겹쳐서 어지러워집니다.
    func showImmediately() {
        scaleX = 1
        scaleY = 1
        rotation = .zero
        openAngle = .zero
        contentPhase = 1
        opacity = 1
        cornerRadius = panelExpandedCornerRadius
        blurRadius = 0
        collapsedState = CollapsedState(
            scale: CGSize(width: 1, height: 1),
            cornerRadius: panelExpandedCornerRadius,
            blurRadius: 0
        )
        collapseDuration = 0.12
    }

    /// 고른 방식에 맞는 몸짓으로 물러납니다.
    func collapse(with style: PanelAnimationStyle) {
        let departure = style.departure
        let flourish = style.flourish
        let departureSquash = style.departureSquash

        // 투명해지는 것을 조금 늦추기 때문에, 창을 실제로 내리는 시점도 그만큼 미뤄야 합니다.
        let fadeDelay = departure.duration * 0.35
        collapseDuration = departure.duration + fadeDelay

        withAnimation(departure.animation) {
            // 들어올 때와 반대로 눌립니다. 옆으로 퍼지며 들어왔다면 좁아지며 나가고,
            // 세로로 늘어나며 들어왔다면 납작해지며 나갑니다.
            scaleX = collapsedState.scale.width * departureSquash.width
            scaleY = collapsedState.scale.height * departureSquash.height
            cornerRadius = collapsedState.cornerRadius
            blurRadius = collapsedState.blurRadius
            rotation = .degrees(departure.tiltDegrees)
            openAngle = .degrees(flourish.openDegrees)
        }
        // 크기와 같은 속도로 투명해지면 몸짓이 보이기 전에 사라져 버립니다.
        withAnimation(.easeIn(duration: departure.duration).delay(fadeDelay)) {
            opacity = 0
        }
    }

    private func applyCollapsedState() {
        rotation = .zero
        openAngle = .zero
        scaleX = collapsedState.scale.width
        scaleY = collapsedState.scale.height
        cornerRadius = collapsedState.cornerRadius
        blurRadius = collapsedState.blurRadius
        opacity = 0
    }

    private func animateToExpandedState(with recipe: Recipe, settle animation: Animation) {
        withAnimation(recipe.horizontalGrowth) { scaleX = 1 }
        withAnimation(recipe.verticalGrowth) { scaleY = 1 }
        withAnimation(recipe.cornerUnwind) { cornerRadius = panelExpandedCornerRadius }
        withAnimation(recipe.fadeIn) {
            opacity = 1
            blurRadius = 0
        }
        withAnimation(animation) {
            rotation = .zero
            openAngle = .zero
        }
        if rowStagger > 0 {
            withAnimation(.easeOut(duration: 0.5)) { contentPhase = 1 }
        }
    }

    // MARK: - 방식별 설정

    /// 펼쳐지기 직전의 모습입니다.
    private struct CollapsedState {
        var scale: CGSize
        var cornerRadius: CGFloat
        var blurRadius: CGFloat

        static let neutral = CollapsedState(scale: CGSize(width: 1, height: 1), cornerRadius: 12, blurRadius: 0)
    }

    /// 한 가지 나타나는 방식을 이루는 값들의 묶음입니다.
    private struct Recipe {
        /// 접혀 있을 때의 크기입니다. 여는 위치에 따라 다르게 잡습니다.
        var collapsedScaleAtEdge: CGSize
        var collapsedScaleFromAbove: CGSize
        var collapsedScaleAtCursor: CGSize

        var collapsedCornerRadius: CGFloat
        var collapsedBlurRadius: CGFloat

        var horizontalGrowth: Animation
        var verticalGrowth: Animation
        var cornerUnwind: Animation
        var fadeIn: Animation
        var collapseDuration: TimeInterval

        func collapsedState(for origin: ShelfPanel.SlideOrigin) -> CollapsedState {
            let scale = switch origin {
            case .leadingEdge, .trailingEdge: collapsedScaleAtEdge
            case .above: collapsedScaleFromAbove
            case .cursor: collapsedScaleAtCursor
            }
            return CollapsedState(
                scale: scale,
                cornerRadius: collapsedCornerRadius,
                blurRadius: collapsedBlurRadius
            )
        }

        static func forStyle(_ style: PanelAnimationStyle) -> Recipe {
            switch style {
            case .droplet: droplet
            case .drawer: drawer
            case .pop: pop
            case .calm: calm
            case .door: door
            case .spin: spin
            }
        }

        /// 작은 방울이 부풀어 오르는 방식입니다.
        ///
        /// 모서리 둥글기를 카드 폭의 절반보다 크게 잡아 두면 작게 줄어든 카드가 동그란
        /// 방울처럼 보이고, 커지면서 그 둥글기가 펴집니다. 가로와 세로의 탄성을 다르게 주어
        /// 한 축이 먼저 도착하고 다른 축이 따라오면서 출렁이는 인상을 만듭니다.
        static let droplet = Recipe(
            collapsedScaleAtEdge: CGSize(width: 0.05, height: 0.20),
            collapsedScaleFromAbove: CGSize(width: 0.22, height: 0.05),
            collapsedScaleAtCursor: CGSize(width: 0.10, height: 0.10),
            collapsedCornerRadius: 180,
            collapsedBlurRadius: 10,
            horizontalGrowth: .spring(duration: 0.36, bounce: 0.58),
            verticalGrowth: .spring(duration: 0.44, bounce: 0.46),
            cornerUnwind: .spring(duration: 0.38, bounce: 0.28),
            fadeIn: .easeOut(duration: 0.14),
            collapseDuration: 0.13
        )

        /// 서랍을 빼내듯 한 방향으로만 곧게 펼쳐지는 방식입니다. 튕김이 없습니다.
        static let drawer = Recipe(
            collapsedScaleAtEdge: CGSize(width: 0.04, height: 1),
            collapsedScaleFromAbove: CGSize(width: 1, height: 0.04),
            collapsedScaleAtCursor: CGSize(width: 0.04, height: 0.92),
            collapsedCornerRadius: panelExpandedCornerRadius,
            collapsedBlurRadius: 0,
            horizontalGrowth: .spring(duration: 0.30, bounce: 0.18),
            verticalGrowth: .spring(duration: 0.30, bounce: 0.18),
            cornerUnwind: .easeOut(duration: 0.22),
            fadeIn: .easeOut(duration: 0.12),
            collapseDuration: 0.14
        )

        /// 작은 크기에서 힘차게 튀어나오는 방식입니다. 가장 빠르고 활기찹니다.
        static let pop = Recipe(
            collapsedScaleAtEdge: CGSize(width: 0.32, height: 0.32),
            collapsedScaleFromAbove: CGSize(width: 0.32, height: 0.32),
            collapsedScaleAtCursor: CGSize(width: 0.32, height: 0.32),
            collapsedCornerRadius: 60,
            collapsedBlurRadius: 0,
            horizontalGrowth: .spring(duration: 0.26, bounce: 0.66),
            verticalGrowth: .spring(duration: 0.30, bounce: 0.58),
            cornerUnwind: .spring(duration: 0.26, bounce: 0.35),
            fadeIn: .easeOut(duration: 0.09),
            collapseDuration: 0.10
        )

        /// 경첩을 축으로 활짝 열리는 방식입니다. 크기는 거의 그대로 두고 열림 각도로만 움직입니다.
        static let door = Recipe(
            collapsedScaleAtEdge: CGSize(width: 1.0, height: 0.96),
            collapsedScaleFromAbove: CGSize(width: 1.0, height: 0.96),
            collapsedScaleAtCursor: CGSize(width: 1.0, height: 0.96),
            collapsedCornerRadius: panelExpandedCornerRadius,
            collapsedBlurRadius: 0,
            horizontalGrowth: .spring(duration: 0.42, bounce: 0.28),
            verticalGrowth: .spring(duration: 0.42, bounce: 0.28),
            cornerUnwind: .easeOut(duration: 0.30),
            fadeIn: .easeOut(duration: 0.16),
            collapseDuration: 0.22
        )

        /// 비스듬히 누운 채로 작게 나타나 돌면서 서는 방식입니다.
        static let spin = Recipe(
            collapsedScaleAtEdge: CGSize(width: 0.40, height: 0.40),
            collapsedScaleFromAbove: CGSize(width: 0.40, height: 0.40),
            collapsedScaleAtCursor: CGSize(width: 0.40, height: 0.40),
            collapsedCornerRadius: 90,
            collapsedBlurRadius: 4,
            horizontalGrowth: .spring(duration: 0.50, bounce: 0.50),
            verticalGrowth: .spring(duration: 0.50, bounce: 0.50),
            cornerUnwind: .spring(duration: 0.46, bounce: 0.25),
            fadeIn: .easeOut(duration: 0.16),
            collapseDuration: 0.26
        )

        /// 거의 움직이지 않고 조용히 나타나는 방식입니다.
        static let calm = Recipe(
            collapsedScaleAtEdge: CGSize(width: 0.97, height: 0.97),
            collapsedScaleFromAbove: CGSize(width: 0.97, height: 0.97),
            collapsedScaleAtCursor: CGSize(width: 0.97, height: 0.97),
            collapsedCornerRadius: panelExpandedCornerRadius,
            collapsedBlurRadius: 0,
            horizontalGrowth: .easeOut(duration: 0.15),
            verticalGrowth: .easeOut(duration: 0.15),
            cornerUnwind: .easeOut(duration: 0.15),
            fadeIn: .easeOut(duration: 0.15),
            collapseDuration: 0.10
        )
    }
}
