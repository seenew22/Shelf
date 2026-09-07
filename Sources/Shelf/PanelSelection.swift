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

    /// 목록의 항목을 눌러서 실행하는 것을 받아들일 준비가 되었는지 여부입니다.
    ///
    /// 가장자리에서 누른 채로 선반을 끌어내면, 선반이 커서 밑으로 따라 들어옵니다.
    /// 이때 버튼을 떼면 그 자리에 있던 항목을 누른 것으로 처리되는데, 사용자는 그 항목을
    /// 누른 적이 없습니다. 끌어내는 동작이 끝날 때까지는 받지 않도록 잠가 둡니다.
    @Published private(set) var acceptsActivation = true

    func suspendActivation() {
        acceptsActivation = false
    }

    func resumeActivation() {
        acceptsActivation = true
    }

    /// 여러 개를 골라 둔 항목들입니다. 비어 있으면 한 개씩 다루는 평소 상태입니다.
    @Published private(set) var chosenIDs: Set<UUID> = []

    /// 지금 여러 개를 고르는 중인지 여부입니다.
    var isChoosingMany: Bool { !chosenIDs.isEmpty }

    /// 여러 개 고르기를 시작합니다.
    func beginChoosing(_ id: UUID) {
        chosenIDs = [id]
    }

    /// 하나를 골랐다 풀었다 합니다. 마지막 하나를 풀면 평소 상태로 돌아갑니다.
    func toggleChoice(_ id: UUID) {
        if chosenIDs.contains(id) {
            chosenIDs.remove(id)
        } else {
            chosenIDs.insert(id)
        }
    }

    func clearChoices() {
        chosenIDs.removeAll()
    }

    /// 목록에서 사라진 항목이 고른 목록에 남아 있지 않도록 정리합니다.
    func pruneChoices(keeping existing: Set<UUID>) {
        let remaining = chosenIDs.intersection(existing)
        guard remaining != chosenIDs else { return }
        chosenIDs = remaining
    }

    func reset() {
        index = 0
        scrollRequestID += 1
        chosenIDs.removeAll()
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
