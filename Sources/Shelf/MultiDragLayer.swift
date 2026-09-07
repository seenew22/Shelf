import AppKit
import SwiftUI

/// 여러 개를 골라 둔 동안, 그 전부를 한꺼번에 끌 수 있게 해 주는 겹입니다.
///
/// SwiftUI 의 `onDrag` 는 한 번에 하나만 넘길 수 있습니다. 파일 두 개를 함께 끌어다
/// 놓으려면 AppKit 의 끌기 기능을 직접 불러야 해서, 각 행 위에 보이지 않는 겹을 얹습니다.
///
/// 여러 개를 고르지 않은 동안에는 이 겹이 마우스를 그대로 통과시킵니다.
/// 그래서 평소의 클릭과 한 개 끌기는 아무 영향도 받지 않습니다.
struct MultiDragLayer: NSViewRepresentable {

    /// 지금 여러 개를 고르는 중인지 여부입니다. 거짓이면 마우스를 통과시킵니다.
    var isActive: Bool

    /// 함께 끌어낼 파일들입니다.
    var urls: [URL]

    /// 끌지 않고 그냥 눌렀을 때 알려 줍니다. 골랐다 풀었다 하는 데 씁니다.
    var onClick: () -> Void

    func makeNSView(context: Context) -> DragCatcher {
        DragCatcher()
    }

    func updateNSView(_ view: DragCatcher, context: Context) {
        view.isActive = isActive
        view.urls = urls
        view.onClick = onClick
    }

    /// 누름과 끌기를 직접 받아서, 누르면 알리고 끌면 여러 개를 함께 내보냅니다.
    final class DragCatcher: NSView {
        var isActive = false
        var urls: [URL] = []
        var onClick: () -> Void = {}

        private var didDrag = false

        /// 여러 개를 고르는 중이 아닐 때는 없는 셈 칩니다.
        override func hitTest(_ point: NSPoint) -> NSView? {
            isActive ? super.hitTest(point) : nil
        }

        override func mouseDown(with event: NSEvent) {
            didDrag = false
        }

        override func mouseUp(with event: NSEvent) {
            guard !didDrag else { return }
            onClick()
        }

        override func mouseDragged(with event: NSEvent) {
            guard !didDrag, !urls.isEmpty else { return }
            didDrag = true

            let origin = convert(event.locationInWindow, from: nil)
            let side: CGFloat = 40

            // 여러 장이 겹쳐 있는 것처럼 조금씩 어긋나게 놓아, 몇 개를 끌고 있는지 보이게 합니다.
            let draggingItems = urls.enumerated().map { offset, url -> NSDraggingItem in
                let item = NSDraggingItem(pasteboardWriter: url as NSURL)
                let shift = CGFloat(offset) * 6
                item.setDraggingFrame(
                    NSRect(
                        x: origin.x - side / 2 + shift,
                        y: origin.y - side / 2 - shift,
                        width: side,
                        height: side
                    ),
                    contents: NSWorkspace.shared.icon(forFile: url.path)
                )
                return item
            }

            beginDraggingSession(with: draggingItems, event: event, source: self)
        }
    }
}

extension MultiDragLayer.DragCatcher: NSDraggingSource {
    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }
}
