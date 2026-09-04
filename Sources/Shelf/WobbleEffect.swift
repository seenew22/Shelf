import SwiftUI

/// 제자리에 닿은 뒤 여러 번 출렁이는 움직임을 만듭니다.
///
/// SwiftUI 는 값을 애니메이션할 때 시작과 끝 사이를 곧게 이어서 그립니다. 그래서 크기
/// 자체를 애니메이션 대상으로 삼으면, 아무리 곡선을 바꿔도 한 번 지나쳤다가 돌아오는
/// 것까지가 한계입니다. 여러 번 튀게 하려면 크기가 아니라 **진행도**를 애니메이션 대상으로
/// 두고, 그 진행도에서 매 순간의 크기를 직접 계산해야 합니다. 이 변형이 그 역할을 합니다.
///
/// 쓰는 식은 감쇠 진동입니다. 시간이 지날수록 잦아드는 물결이며,
/// `cycles` 는 몇 번 출렁일지를, `damping` 은 얼마나 빨리 잦아들지를 정합니다.
struct WobbleEffect: GeometryEffect {

    /// 0에서 1까지 흐르는 진행도입니다. 이 값만 애니메이션됩니다.
    var phase: Double

    /// 가로와 세로로 각각 얼마나 크게 출렁일지입니다. 0.2 면 최대 20%까지 늘고 줄어듭니다.
    var amplitude: CGSize

    /// 잦아들 때까지 몇 번 출렁일지입니다.
    var cycles: Double

    /// 얼마나 빨리 잦아들지입니다. 클수록 금방 멎습니다.
    var damping: Double

    /// 어느 지점을 붙잡은 채로 출렁일지입니다.
    var anchor: UnitPoint

    var animatableData: Double {
        get { phase }
        set { phase = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let wave = exp(-damping * phase) * cos(cycles * 2 * .pi * phase)
        let scaleX = 1 + amplitude.width * wave
        let scaleY = 1 + amplitude.height * wave

        let pivotX = size.width * anchor.x
        let pivotY = size.height * anchor.y

        let transform = CGAffineTransform(translationX: pivotX, y: pivotY)
            .scaledBy(x: scaleX, y: scaleY)
            .translatedBy(x: -pivotX, y: -pivotY)

        return ProjectionTransform(transform)
    }
}

extension View {
    /// 출렁이는 움직임을 얹습니다. 진폭이 0이면 아무 일도 하지 않습니다.
    @ViewBuilder
    func wobble(_ wobble: Wobble?, phase: Double, anchor: UnitPoint) -> some View {
        if let wobble {
            modifier(
                WobbleEffect(
                    phase: phase,
                    amplitude: wobble.amplitude,
                    cycles: wobble.cycles,
                    damping: wobble.damping,
                    anchor: anchor
                )
            )
        } else {
            self
        }
    }
}

/// 출렁임 한 가지를 이루는 값들입니다.
struct Wobble: Equatable, Sendable {
    var amplitude: CGSize
    var cycles: Double
    var damping: Double
    var duration: TimeInterval
}
