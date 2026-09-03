import AppKit
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
    private var toggleHotkey: GlobalHotkey?

    /// 복사 표시를 잠깐 보여 준 뒤 창을 닫기 위해 예약해 둔 작업입니다.
    private var pendingCloseTask: Task<Void, Never>?

    /// 창 바깥을 클릭했을 때 창을 닫기 위한 감시자입니다.
    private var outsideClickMonitor: Any?

    /// 창이 떠 있는 동안 키 입력을 처리하기 위한 감시자입니다.
    private var keyMonitor: Any?

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
        guard let panel else { return }
        if panel.isVisible {
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

        switch anchor {
        case .statusItem:
            guard let button = statusItem?.button else { return }
            panel.position(below: button)
        case .mouseCursor:
            panel.position(near: NSEvent.mouseLocation)
        }
        // 앱을 활성 상태로 만들지 않고 창만 앞으로 내보냅니다.
        panel.orderFrontRegardless()
        panel.makeKey()
        statusItem?.button?.highlight(true)
        startEventMonitors()
    }

    private func closePanel() {
        pendingCloseTask?.cancel()
        pendingCloseTask = nil
        panel?.orderOut(nil)
        statusItem?.button?.highlight(false)
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

        pendingCloseTask?.cancel()
        pendingCloseTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
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
            outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown]
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, !self.isPointOverOwnWindow(NSEvent.mouseLocation) else { return }
                    self.closePanel()
                }
            }
        }

        if keyMonitor == nil {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                // NSEvent 자체를 격리 경계 너머로 넘기지 않도록 키 코드만 꺼내서 전달합니다.
                let keyCode = event.keyCode
                let handled = MainActor.assumeIsolated { self?.handleKeyDown(keyCode) ?? false }
                return handled ? nil : event
            }
        }
    }

    /// 클릭 지점이 이 앱이 소유한 창 위인지 확인합니다.
    ///
    /// 언어 선택 메뉴처럼 메뉴가 열려 있는 동안의 클릭은 메뉴가 자체적으로 처리하기 때문에,
    /// 전역 감시자에게는 앱 바깥에서 일어난 일처럼 전달됩니다. 메뉴는 별개의 창이라
    /// 일반적인 방법으로는 구분되지 않으므로, 화면에 떠 있는 창 중에서 이 프로세스가
    /// 소유한 것이 있는지 직접 확인해서 걸러 냅니다.
    private func isPointOverOwnWindow(_ location: NSPoint) -> Bool {
        guard let mainScreen = NSScreen.screens.first else { return false }

        // 마우스 위치는 주 화면 왼쪽 아래가 원점이고 위로 갈수록 y가 커지는 반면,
        // 창 목록은 주 화면 왼쪽 위가 원점이고 아래로 갈수록 y가 커지므로 변환이 필요합니다.
        let point = CGPoint(x: location.x, y: mainScreen.frame.height - location.y)
        let ownProcessIdentifier = ProcessInfo.processInfo.processIdentifier
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []

        return windows.contains { window in
            guard
                window[kCGWindowOwnerPID as String] as? pid_t == ownProcessIdentifier,
                let boundsDictionary = window[kCGWindowBounds as String] as? [String: CGFloat],
                let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary)
            else {
                return false
            }
            return bounds.contains(point)
        }
    }

    /// 창이 떠 있는 동안의 키 입력을 처리합니다.
    /// - Returns: 우리가 처리했으면 true. 이때 해당 입력은 다른 곳으로 전달되지 않습니다.
    private func handleKeyDown(_ keyCode: UInt16) -> Bool {
        let itemCount = store?.items.count ?? 0

        switch keyCode {
        case 53: // Esc
            closePanel()
            return true

        case 126: // 위쪽 화살표
            selection.move(by: -1, itemCount: itemCount)
            return true

        case 125: // 아래쪽 화살표
            selection.move(by: 1, itemCount: itemCount)
            return true

        case 36, 76: // Return, 숫자판 Enter
            guard let item = store?.items[safe: selection.index] else { return true }
            copyAndClose(item)
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
