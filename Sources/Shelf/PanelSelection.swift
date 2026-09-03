import Foundation

/// 키보드로 목록을 훑을 때 지금 어느 항목에 가 있는지를 담습니다.
///
/// 마우스를 올려도 같은 값이 갱신되므로, 화면에는 강조 표시가 하나만 나타납니다.
@MainActor
final class PanelSelection: ObservableObject {

    @Published private(set) var index = 0

    /// 목록을 선택 항목까지 스크롤해 달라는 요청입니다. 값이 바뀌면 화면이 반응합니다.
    ///
    /// 마우스로 가리켜서 선택이 바뀐 경우에는 이 값을 올리지 않습니다. 그때도 스크롤하면
    /// 항목이 커서 밑에서 움직여 버려서, 고르려던 항목을 오히려 놓치게 되기 때문입니다.
    @Published private(set) var scrollRequestID = 0

    func reset() {
        index = 0
        scrollRequestID += 1
    }

    /// 마우스를 올려서 선택이 바뀐 경우입니다. 목록은 움직이지 않습니다.
    func selectByPointer(_ newIndex: Int) {
        index = max(0, newIndex)
    }

    /// 키보드로 위아래 한 칸씩 옮깁니다. 목록의 처음과 끝을 넘어가지는 않으며,
    /// 옮긴 항목이 화면 밖에 있으면 목록이 따라 움직입니다.
    func moveByKeyboard(by offset: Int, itemCount: Int) {
        guard itemCount > 0 else {
            index = 0
            return
        }
        index = min(max(index + offset, 0), itemCount - 1)
        scrollRequestID += 1
    }
}

extension Array {
    /// 범위를 벗어난 위치를 물어보면 nil을 돌려줍니다.
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
