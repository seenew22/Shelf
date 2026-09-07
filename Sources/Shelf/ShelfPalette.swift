import AppKit
import SwiftUI

/// 화면에 쓰는 색을 한곳에 모아 둡니다.
///
/// 시스템 기본 강조색을 여기저기 쓰면 어느 앱에서나 보는 파란색이 화면을 채워서,
/// 손대지 않은 기본값처럼 보입니다. 그래서 두 가지 원칙을 두었습니다.
///
/// 첫째, 구조를 이루는 것(선택 표시, 경계선, 구분)은 **색을 쓰지 않고** 명도만 다르게 합니다.
/// 배경이 무엇이든 튀지 않고, 바탕화면 색과 싸우지 않습니다.
/// 둘째, 색은 정말 알려야 하는 순간에만 씁니다. 복사되었다는 확인, 고정해 둔 표시,
/// 받을 준비가 되었다는 표시 세 가지뿐이며, 모두 같은 한 가지 색을 씁니다.
enum ShelfPalette {

    /// 밝은 화면과 어두운 화면에서 각각 다른 색을 쓰도록 묶어 줍니다.
    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }

    /// 알려야 하는 순간에만 쓰는 색입니다.
    ///
    /// 기본 강조색인 파랑 대신 차분한 청록을 골랐습니다. 파랑은 어느 앱에서나 쓰여서
    /// 눈에 걸리지 않고, 링크나 선택처럼 다른 뜻으로도 읽히기 때문입니다.
    static let accent = adaptive(
        light: NSColor(srgbRed: 0.14, green: 0.47, blue: 0.42, alpha: 1),
        dark: NSColor(srgbRed: 0.38, green: 0.78, blue: 0.69, alpha: 1)
    )

    /// 지금 가리키고 있는 항목의 바탕입니다.
    static let selectionBackground = adaptive(
        light: NSColor(white: 0, alpha: 0.06),
        dark: NSColor(white: 1, alpha: 0.09)
    )

    /// 방금 복사한 항목의 바탕입니다. 강조색을 아주 옅게 깔아 둡니다.
    static let confirmationBackground = adaptive(
        light: NSColor(srgbRed: 0.14, green: 0.47, blue: 0.42, alpha: 0.12),
        dark: NSColor(srgbRed: 0.38, green: 0.78, blue: 0.69, alpha: 0.16)
    )

    /// 카드의 테두리입니다.
    static let cardBorder = adaptive(
        light: NSColor(white: 0, alpha: 0.12),
        dark: NSColor(white: 1, alpha: 0.14)
    )

    /// 머리글과 바닥글을 목록과 나누는 선입니다.
    static let separator = adaptive(
        light: NSColor(white: 0, alpha: 0.08),
        dark: NSColor(white: 1, alpha: 0.10)
    )

    /// 미리보기 그림 둘레의 옅은 테두리입니다.
    static let thumbnailBorder = adaptive(
        light: NSColor(white: 0, alpha: 0.14),
        dark: NSColor(white: 1, alpha: 0.16)
    )
}
