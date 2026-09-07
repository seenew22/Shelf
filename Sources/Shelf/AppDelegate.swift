import AppKit
import QuartzCore
import SwiftUI

/// 앱 전체의 수명을 관리합니다.
///
/// Dock에 아이콘을 두지 않는 메뉴 바 상주 앱이므로 일반적인 창은 만들지 않고,
/// 메뉴 바의 `NSStatusItem`과 거기에 딸린 떠 있는 패널 하나만 다룹니다.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    private var panel: ShelfPanel?
    private var store: HistoryStore?
    private var clipboardMonitor: ClipboardMonitor?
    private var localization: LocalizationManager?
    private let selection = PanelSelection()
    private let preferences = Preferences()
    private let presentation = PanelPresentation()
    private let edgeHoverMonitor = EdgeHoverMonitor()
    private var toggleHotkey: GlobalHotkey?

    /// 창이 지금 열려 있는지 여부입니다.
    /// 사라지는 동안에도 창 자체는 잠시 화면에 남으므로 `isVisible` 로는 판단할 수 없습니다.
    private var isPanelPresented = false

    /// 복사 표시를 잠깐 보여 준 뒤 창을 닫기 위해 예약해 둔 작업입니다.
    private var pendingCloseTask: Task<Void, Never>?

    /// 사라지는 움직임이 끝난 뒤 창을 실제로 감추기 위해 예약해 둔 작업입니다.
    private var hideTask: Task<Void, Never>?

    /// 끌어내던 손을 떼기를 기다리는 작업입니다.
    private var activationUnlockTask: Task<Void, Never>?

    /// 창 바깥을 클릭했을 때 창을 닫기 위한 감시자입니다.
    private var outsideClickMonitor: Any?

    /// 창이 떠 있는 동안 키 입력을 처리하기 위한 감시자입니다.
    private var keyMonitor: Any?

    /// 화면 밖의 선반을 잡아 빼는 중일 때의 상태입니다.
    private var edgeDrag: EdgeDrag?

    /// 가장자리에서 꺼낸 창이라면 그 자리를 기억해 둡니다.
    /// 닫을 때 같은 자리로 되돌아가게 하기 위한 것입니다.
    private var edgeOrigin: EdgeDrag?

    /// 지금 떠 있는 창이 어떤 방식으로 나타났는지입니다.
    /// 설정에서 방식을 바꾸면 같은 자리에서 그 움직임을 다시 보여 주는 데 씁니다.
    private var lastEntrance: Entrance?

    /// 창이 나타난 경위입니다.
    private enum Entrance {
        /// 단축키나 메뉴 바 아이콘으로 펼쳐졌습니다.
        case unfolded(ShelfPanel.SlideOrigin)
        /// 화면 가장자리에서 끌려 나왔습니다.
        case pulledFromEdge(hinge: UnitPoint)
    }

    /// 화면 밖에서 잡아 빼고 있는 선반의 위치 정보입니다.
    private struct EdgeDrag {
        var edge: EdgeHoverMonitor.HorizontalEdge
        var screen: NSScreen
        var cursorHeight: CGFloat
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let store = HistoryStore()
        let clipboardMonitor = ClipboardMonitor(store: store)
        self.store = store
        self.clipboardMonitor = clipboardMonitor

        let localization = LocalizationManager()
        self.localization = localization

        setUpStatusItem()
        setUpPanel(store: store, localization: localization)
        setUpGlobalShortcut()
        setUpEdgeHover()

        clipboardMonitor.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        clipboardMonitor?.stop()
        removeEventMonitors()
    }

    // MARK: - 초기 구성

    private func setUpStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "tray.full",
            accessibilityDescription: "Shelf 클립보드 히스토리"
        )
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked)
        self.statusItem = statusItem
    }

    private func setUpPanel(store: HistoryStore, localization: LocalizationManager) {
        panel = ShelfPanel(
            rootView: HistoryView(
                store: store,
                l10n: localization,
                selection: selection,
                preferences: preferences,
                presentation: presentation,
                onCopy: { [weak self] item in self?.copyAndClose(item) },
                onQuit: { NSApp.terminate(nil) }
            )
        )
    }

    private func setUpGlobalShortcut() {
        toggleHotkey = GlobalHotkey(
            keyCode: GlobalHotkey.toggleShelfKeyCode,
            modifiers: GlobalHotkey.toggleShelfModifiers
        ) { [weak self] in
            self?.togglePanel(anchoredTo: .mouseCursor)
        }
    }

    private func setUpEdgeHover() {
        edgeHoverMonitor.onPeekBegan = { [weak self] edge, screen, height in
            self?.beginEdgeDrag(edge: edge, screen: screen, cursorHeight: height)
        }
        edgeHoverMonitor.onPullChanged = { [weak self] distance in
            self?.updateEdgeDrag(pullDistance: distance)
        }
        edgeHoverMonitor.onPeekCancelled = { [weak self] in
            self?.cancelEdgeDrag()
        }
        edgeHoverMonitor.onCommit = { [weak self] edge, screen, height in
            self?.commitEdgeDrag(edge: edge, screen: screen, cursorHeight: height)
        }
        edgeHoverMonitor.onPointerLeft = { [weak self] in
            guard let self else { return }
            // 열어 두기를 켠 동안에는 마우스가 아무리 멀어져도 닫지 않습니다.
            guard !self.preferences.keepsPanelOpen else { return }
            // 설정 메뉴를 펼쳐 둔 채로 마우스를 옮기는 일은 흔합니다. 이때 창만 닫아 버리면
            // 메뉴가 홀로 남아 떠다니게 되므로, 메뉴가 닫힐 때까지 기다립니다.
            guard !self.hasOpenMenu() else { return }
            self.closePanel()
        }
        preferences.onEdgeHoverSideChanged = { [weak self] side in
            self?.edgeHoverMonitor.update(side: side)
        }
        preferences.onEdgeOpenModeChanged = { [weak self] mode in
            self?.edgeHoverMonitor.update(mode: mode)
        }
        preferences.onPanelAnimationStyleChanged = { [weak self] style in
            self?.replayEntrance(with: style)
        }
        edgeHoverMonitor.update(mode: preferences.edgeOpenMode)
        edgeHoverMonitor.update(side: preferences.edgeHoverSide)
    }

    // MARK: - 창 열고 닫기

    /// 창을 어디에 붙여서 띄울지를 나타냅니다.
    private enum PanelAnchor {
        /// 메뉴 바 아이콘 바로 아래에 띄웁니다.
        case statusItem
        /// 마우스 커서 옆에 띄웁니다.
        case mouseCursor
    }

    @objc private func statusItemClicked() {
        togglePanel(anchoredTo: .statusItem)
    }

    private func togglePanel(anchoredTo anchor: PanelAnchor) {
        if isPanelPresented {
            closePanel()
        } else {
            openPanel(anchoredTo: anchor)
        }
    }

    private func openPanel(anchoredTo anchor: PanelAnchor) {
        guard let panel else { return }

        pendingCloseTask?.cancel()
        pendingCloseTask = nil

        store?.refreshReferenceDate()
        selection.reset()

        // 창이 어디에 놓이고, 어느 방향에서 밀려 나올지를 함께 정합니다.
        let slideOrigin: ShelfPanel.SlideOrigin
        switch anchor {
        case .statusItem:
            guard let button = statusItem?.button else { return }
            panel.position(below: button)
            slideOrigin = .above
        case .mouseCursor:
            panel.position(near: NSEvent.mouseLocation)
            slideOrigin = .cursor
        }

        // 앱을 활성 상태로 만들지 않고 창만 앞으로 내보냅니다.
        hideTask?.cancel()
        hideTask = nil
        edgeDrag = nil
        edgeOrigin = nil
        panel.orderFrontRegardless()
        panel.makeKey()
        isPanelPresented = true

        // 접힌 모습이 한 번 그려진 다음에 펼쳐져야 움직임이 보입니다.
        // 곧바로 펼치면 이미 펼쳐진 상태로 처음 그려져서 아무 움직임도 나타나지 않습니다.
        lastEntrance = .unfolded(slideOrigin)
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.presentation.expand(from: slideOrigin, style: self.preferences.panelAnimationStyle)
        }
        statusItem?.button?.highlight(true)

        // 단축키나 아이콘으로 연 창은 마우스가 멀어져도 그대로 둡니다.
        edgeHoverMonitor.panelDidChangeVisibility(isVisible: true, autoCloseFrame: nil)

        startEventMonitors()
    }

    // MARK: - 가장자리에서 잡아 빼기

    /// 화면 밖에 세워 둔 선반의 끝을 화면 안으로 조금 내밉니다.
    ///
    /// 별도의 손잡이를 그리는 대신 선반 자체의 가장자리를 내밀어 두면, 잡아당기는 대상과
    /// 나오는 물건이 처음부터 같은 것이 됩니다. 그래야 당기는 동작과 열리는 결과가
    /// 하나로 이어져 보입니다.
    private func beginEdgeDrag(edge: EdgeHoverMonitor.HorizontalEdge, screen: NSScreen, cursorHeight: CGFloat) {
        guard let panel, !isPanelPresented else { return }

        edgeDrag = EdgeDrag(edge: edge, screen: screen, cursorHeight: cursorHeight)
        hideTask?.cancel()
        hideTask = nil

        store?.refreshReferenceDate()
        selection.reset()
        // 끌어내는 내내 선반이 커서 밑에 있습니다. 다 나온 뒤가 아니라 나오기 시작하는
        // 순간부터 잠가야, 끌려 나오는 동안 항목이 눌리거나 딸려 나오지 않습니다.
        selection.suspendActivation()
        // 창 자체가 밀려 나오면서 드러나므로, 내용물까지 커지면 두 움직임이 겹칩니다.
        presentation.showImmediately()

        // 완전히 화면 밖에 있는 창은 시스템이 화면 안으로 끌어다 놓을 수 있으므로,
        // 눈에 띄지 않을 만큼만 걸쳐 둔 자리에서 시작합니다.
        panel.position(atEdge: edge, on: screen, cursorHeight: cursorHeight, revealedWidth: 1)
        panel.orderFrontRegardless()
        let reveal = preferences.panelAnimationStyle.edgeReveal
        panel.animate(
            toRevealedWidth: preferences.panelAnimationStyle.edgeGripWidth,
            atEdge: edge,
            on: screen,
            cursorHeight: cursorHeight,
            duration: reveal.duration,
            timing: CAMediaTimingFunction(
                controlPoints: reveal.controlPoints.0, reveal.controlPoints.1,
                reveal.controlPoints.2, reveal.controlPoints.3
            )
        )
    }

    /// 당긴 거리만큼 선반을 따라 나오게 합니다.
    ///
    /// 마우스 위치는 일정 주기로만 확인하므로 값이 띄엄띄엄 들어옵니다.
    /// 아주 짧은 움직임으로 그 사이를 메워서 끊겨 보이지 않게 합니다.
    private func updateEdgeDrag(pullDistance: CGFloat) {
        guard let panel, let drag = edgeDrag else { return }

        let style = preferences.panelAnimationStyle
        let revealed = min(
            style.edgeGripWidth + max(0, pullDistance) * style.edgePullGain,
            ShelfPanel.fullyRevealedWidth
        )
        panel.animate(
            toRevealedWidth: revealed,
            atEdge: drag.edge,
            on: drag.screen,
            cursorHeight: drag.cursorHeight,
            duration: 0.05,
            timing: CAMediaTimingFunction(name: .linear)
        )
    }

    /// 잡아당기기를 그만두었을 때, 선반을 화면 밖으로 도로 밀어 넣습니다.
    private func cancelEdgeDrag() {
        guard let panel, let drag = edgeDrag else { return }
        edgeDrag = nil
        activationUnlockTask?.cancel()
        selection.resumeActivation()

        panel.animate(
            toRevealedWidth: 1,
            atEdge: drag.edge,
            on: drag.screen,
            cursorHeight: drag.cursorHeight,
            duration: 0.20,
            timing: CAMediaTimingFunction(name: .easeIn)
        )

        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.22))
            guard !Task.isCancelled else { return }
            self?.panel?.orderOut(nil)
        }
    }

    /// 선반을 끝까지 꺼내서 제자리에 세웁니다.
    private func commitEdgeDrag(edge: EdgeHoverMonitor.HorizontalEdge, screen: NSScreen, cursorHeight: CGFloat) {
        guard let panel else { return }

        edgeDrag = nil
        edgeOrigin = EdgeDrag(edge: edge, screen: screen, cursorHeight: cursorHeight)
        hideTask?.cancel()
        hideTask = nil
        pendingCloseTask?.cancel()
        pendingCloseTask = nil

        // 제자리를 살짝 지나쳤다가 되돌아오게 해서, 툭 하고 자리 잡는 느낌을 만듭니다.
        let snap = preferences.panelAnimationStyle.edgeSnap
        panel.animate(
            toRevealedWidth: ShelfPanel.fullyRevealedWidth,
            atEdge: edge,
            on: screen,
            cursorHeight: cursorHeight,
            duration: snap.duration,
            timing: CAMediaTimingFunction(
                controlPoints: snap.controlPoints.0, snap.controlPoints.1,
                snap.controlPoints.2, snap.controlPoints.3
            )
        )

        // 다 꺼내진 순간에만 방식에 맞는 착지 몸짓을 줍니다.
        let hinge: UnitPoint = edge == .left ? .leading : .trailing
        lastEntrance = .pulledFromEdge(hinge: hinge)
        presentation.land(with: preferences.panelAnimationStyle, hingedAt: hinge)

        panel.makeKey()
        isPanelPresented = true
        statusItem?.button?.highlight(true)
        resumeRowActivationWhenMouseReleased()

        // 가장자리에서 꺼낸 창만, 마우스가 한참 멀어져 있으면 스스로 치워집니다.
        let restingFrame = panel.restingCardFrame(
            atEdge: edge,
            on: screen,
            cursorHeight: cursorHeight,
            revealedWidth: ShelfPanel.fullyRevealedWidth
        )
        edgeHoverMonitor.panelDidChangeVisibility(isVisible: true, autoCloseFrame: restingFrame)

        startEventMonitors()
    }

    private func closePanel() {
        lastEntrance = nil
        activationUnlockTask?.cancel()
        activationUnlockTask = nil
        selection.resumeActivation()

        // 아직 다 꺼내지 않은 상태라면 도로 밀어 넣는 것으로 충분합니다.
        if edgeDrag != nil {
            cancelEdgeDrag()
            return
        }
        guard isPanelPresented else { return }
        isPanelPresented = false
        pendingCloseTask?.cancel()
        pendingCloseTask = nil

        // 먼저 물러나는 움직임을 시작하고, 다 물러난 다음에 창을 실제로 감춥니다.
        let style = preferences.panelAnimationStyle
        presentation.collapse(with: style)
        var waitDuration = presentation.collapseDuration

        // 가장자리에서 꺼낸 창은 왔던 자리로 되돌아가면서 사라집니다.
        // 제자리에서 작아지기만 하면, 어디서 나왔던 것인지가 사라지는 순간에 지워집니다.
        if let edgeOrigin, let panel {
            let departure = style.edgeDeparture
            panel.animate(
                toRevealedWidth: 1,
                atEdge: edgeOrigin.edge,
                on: edgeOrigin.screen,
                cursorHeight: edgeOrigin.cursorHeight,
                duration: departure.duration,
                timing: CAMediaTimingFunction(
                    controlPoints: departure.controlPoints.0, departure.controlPoints.1,
                    departure.controlPoints.2, departure.controlPoints.3
                )
            )
            waitDuration = max(waitDuration, departure.duration)
        }
        edgeOrigin = nil

        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(waitDuration + 0.02))
            guard !Task.isCancelled else { return }
            self?.panel?.orderOut(nil)
        }

        statusItem?.button?.highlight(false)
        edgeHoverMonitor.panelDidChangeVisibility(isVisible: false, autoCloseFrame: nil)
        removeEventMonitors()
    }

    /// 항목을 클립보드에 다시 올린 뒤 창을 닫습니다.
    ///
    /// 복사 자체는 즉시 이루어지지만, 창을 곧바로 닫아 버리면 정말 복사가 되었는지
    /// 알 수 없으므로 확인 표시를 볼 수 있을 만큼만 기다렸다가 닫습니다.
    private func copyAndClose(_ item: ClipboardItem) {
        guard let store else { return }
        let changeCount = store.copyToPasteboard(item)
        // 방금 우리가 만든 변경이므로, 감시자가 이를 새 복사로 오인하지 않도록 알려 둡니다.
        clipboardMonitor?.acknowledgeSelfWrite(changeCount: changeCount)

        // 열어 두기를 켠 동안에는 복사한 뒤에도 창을 닫지 않습니다.
        // 여러 개를 잇달아 꺼내려고 켜 둔 것이기 때문입니다.
        guard !preferences.keepsPanelOpen else { return }

        pendingCloseTask?.cancel()
        pendingCloseTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(320))
            guard !Task.isCancelled else { return }
            self?.closePanel()
        }
    }

    // MARK: - 창을 닫아야 하는 상황 감지

    /// 다른 앱이나 바탕화면을 클릭하면 창을 닫고, Esc 키에도 반응합니다.
    ///
    /// 전역 감시자는 우리 앱 바깥에서 발생한 사건만 받기 때문에, 창 안에서 시작하는
    /// 드래그 동작은 여기에 걸리지 않습니다. 덕분에 항목을 끌어내는 동안 창이 유지됩니다.
    private func startEventMonitors() {
        if outsideClickMonitor == nil {
            // 누르는 순간이 아니라 떼는 순간을 봅니다.
            // 다른 앱에서 파일을 집어 이 창으로 끌어오는 동작도 바깥을 누르는 것으로 시작하는데,
            // 누르자마자 닫아 버리면 끌어다 놓을 창이 사라져 버립니다.
            // 떼는 순간을 보면, 창 위에서 놓은 경우와 바깥에서 놓은 경우를 구별할 수 있습니다.
            outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseUp, .rightMouseUp]
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, !self.shouldKeepPanelOpen(forClickAt: NSEvent.mouseLocation) else { return }
                    self.closePanel()
                }
            }
        }

        if keyMonitor == nil {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                // NSEvent 자체를 격리 경계 너머로 넘기지 않도록 키 코드만 꺼내서 전달합니다.
                let keyCode = event.keyCode
                let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue
                let handled = MainActor.assumeIsolated {
                    self?.handleKeyDown(keyCode, modifiers: modifiers) ?? false
                }
                return handled ? nil : event
            }
        }
    }

    /// 방식을 바꾸면 창이 떠 있는 자리에서 그 움직임을 곧바로 다시 보여 줍니다.
    ///
    /// 이름만 보고 고르라고 하면 아홉 가지를 하나씩 열어 보며 확인해야 합니다.
    /// 고르는 순간 그 자리에서 다시 나타나면, 그것이 곧 미리보기가 됩니다.
    private func replayEntrance(with style: PanelAnimationStyle) {
        guard isPanelPresented, let lastEntrance else { return }

        switch lastEntrance {
        case .unfolded(let origin):
            presentation.expand(from: origin, style: style)
        case .pulledFromEdge(let hinge):
            presentation.land(with: style, hingedAt: hinge)
        }
    }

    /// 손을 뗀 것을 확인한 뒤에 목록이 다시 반응하도록 풉니다.
    ///
    /// 누른 채로 끌어내는 동안 선반이 커서 밑으로 들어오기 때문에, 그대로 두면 손을 떼는
    /// 순간 그 자리의 항목이 눌린 것으로 처리되거나, 움직이는 도중에 항목이 딸려 나옵니다.
    /// 둘 다 사용자가 의도한 적 없는 일입니다.
    private func resumeRowActivationWhenMouseReleased() {
        activationUnlockTask?.cancel()

        // 누르지 않고 밀어서 연 경우에는 기다릴 것이 없습니다.
        guard NSEvent.pressedMouseButtons != 0 else {
            selection.resumeActivation()
            return
        }

        activationUnlockTask = Task { [weak self] in
            // 어떤 이유로든 놓는 것을 놓치더라도 영영 잠겨 있지는 않도록 한계를 둡니다.
            let deadline = Date().addingTimeInterval(3)
            while NSEvent.pressedMouseButtons != 0, Date() < deadline {
                try? await Task.sleep(for: .milliseconds(25))
                if Task.isCancelled { return }
            }
            // 놓는 순간에 일어나는 처리가 끝난 뒤에 풀어야 합니다.
            try? await Task.sleep(for: .milliseconds(60))
            guard !Task.isCancelled else { return }
            self?.selection.resumeActivation()
        }
    }

    /// 이 클릭 때문에 창을 닫지 말아야 하는지 판단합니다.
    private func shouldKeepPanelOpen(forClickAt location: NSPoint) -> Bool {
        // 열어 두기를 켠 동안에는 어디를 눌러도 닫지 않습니다.
        // Finder 에서 파일을 고르는 것도 바깥을 누르는 일이기 때문입니다.
        if preferences.keepsPanelOpen {
            return true
        }

        // 눈에 보이는 카드 위를 눌렀다면 그대로 둡니다. 카드 바깥의 여백도 창의 일부이긴 하지만
        // 투명해서 보이지 않으므로, 그쪽을 누른 것은 바깥을 누른 것으로 봅니다.
        if let panel, panel.cardFrame.contains(location) {
            return true
        }
        return isPointOverOwnMenu(location)
    }

    /// 이 앱이 띄운 메뉴가 지금 화면에 떠 있는지 확인합니다.
    ///
    /// 메뉴는 SwiftUI 가 알아서 만들고 없애기 때문에 우리가 직접 붙들고 있는 대상이 아닙니다.
    /// 그래서 화면에 떠 있는 창 중에 이 프로세스가 가진 것이 패널과 손잡이 말고 또 있는지를
    /// 보고 판단합니다.
    private func hasOpenMenu() -> Bool {
        let panelWindowNumber = panel?.windowNumber
        return ownWindows().contains { number, _ in number != panelWindowNumber }
    }

    /// 화면에 떠 있는 창 중에서 이 프로세스가 가진 것들의 번호와 위치입니다.
    private func ownWindows() -> [(Int, CGRect)] {
        let ownProcessIdentifier = ProcessInfo.processInfo.processIdentifier
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []

        return windows.compactMap { window in
            guard
                window[kCGWindowOwnerPID as String] as? pid_t == ownProcessIdentifier,
                let number = window[kCGWindowNumber as String] as? Int,
                let boundsDictionary = window[kCGWindowBounds as String] as? [String: CGFloat],
                let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary)
            else {
                return nil
            }
            return (number, bounds)
        }
    }

    /// 클릭 지점이 이 앱이 띄운 메뉴 위인지 확인합니다.
    ///
    /// 설정 메뉴가 열려 있는 동안의 클릭은 메뉴가 자체적으로 처리하기 때문에,
    /// 전역 감시자에게는 앱 바깥에서 일어난 일처럼 전달됩니다. 메뉴는 별개의 창이라
    /// 일반적인 방법으로는 구분되지 않으므로, 화면에 떠 있는 창 중에서 이 프로세스가
    /// 소유한 것이 있는지 직접 확인해서 걸러 냅니다.
    private func isPointOverOwnMenu(_ location: NSPoint) -> Bool {
        guard let mainScreen = NSScreen.screens.first else { return false }

        // 마우스 위치는 주 화면 왼쪽 아래가 원점이고 위로 갈수록 y가 커지는 반면,
        // 창 목록은 주 화면 왼쪽 위가 원점이고 아래로 갈수록 y가 커지므로 변환이 필요합니다.
        let point = CGPoint(x: location.x, y: mainScreen.frame.height - location.y)
        let panelWindowNumber = panel?.windowNumber

        return ownWindows().contains { number, bounds in
            number != panelWindowNumber && bounds.contains(point)
        }
    }

    /// 창이 떠 있는 동안의 키 입력을 처리합니다.
    /// - Returns: 우리가 처리했으면 true. 이때 해당 입력은 다른 곳으로 전달되지 않습니다.
    private func handleKeyDown(_ keyCode: UInt16, modifiers rawModifiers: UInt) -> Bool {
        let itemCount = store?.visibleItems.count ?? 0
        let modifiers = NSEvent.ModifierFlags(rawValue: rawModifiers)

        switch keyCode {
        case 53: // Esc
            // 검색 중이라면 먼저 검색어만 비웁니다. 한 번 더 누르면 창이 닫힙니다.
            if let store, !store.searchQuery.isEmpty {
                store.searchQuery = ""
                selection.reset()
                return true
            }
            closePanel()
            return true

        case 126: // 위쪽 화살표
            selection.moveByKeyboard(by: -1, itemCount: itemCount)
            return true

        case 125: // 아래쪽 화살표
            selection.moveByKeyboard(by: 1, itemCount: itemCount)
            return true

        case 36, 76: // Return, 숫자판 Enter
            guard let store, let item = store.visibleItems[safe: selection.index] else { return true }
            // Command 를 함께 누르면 복사 대신 Finder 에서 위치를 보여 줍니다.
            if modifiers.contains(.command) {
                guard item.isRevealableInFinder else { return true }
                store.revealInFinder(item)
                closePanel()
            } else {
                copyAndClose(item)
            }
            return true

        default:
            return false
        }
    }

    private func removeEventMonitors() {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
        }
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        outsideClickMonitor = nil
        keyMonitor = nil
    }
}
