import Foundation

/// 키보드로 목록을 훑을 때 지금 어느 항목에 가 있는지를 담습니다.
///
/// 마우스를 올려도 같은 값이 갱신되므로, 화면에는 강조 표시가 하나만 나타납니다.
@MainActor
final class PanelSelection: ObservableObject {

    @Published private(set) var index = 0

    func reset() {
        index = 0
    }

    func select(_ newIndex: Int) {
        index = max(0, newIndex)
    }

    /// 위아래로 한 칸씩 옮깁니다. 목록의 처음과 끝을 넘어가지는 않습니다.
    func move(by offset: Int, itemCount: Int) {
        guard itemCount > 0 else {
            index = 0
            return
        }
        index = min(max(index + offset, 0), itemCount - 1)
    }
}

extension Array {
    /// 범위를 벗어난 위치를 물어보면 nil을 돌려줍니다.
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
