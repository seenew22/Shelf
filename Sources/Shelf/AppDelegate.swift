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
    private var toggleHotkey: GlobalHotkey?

    /// 창 바깥을 클릭했을 때 창을 닫기 위한 감시자입니다.
    private var outsideClickMonitor: Any?

    /// 창이 떠 있는 동안 Esc 키를 처리하기 위한 감시자입니다.
    private var escapeKeyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let store = HistoryStore()
        let clipboardMonitor = ClipboardMonitor(store: store)
        self.store = store
        self.clipboardMonitor = clipboardMonitor

        setUpStatusItem()
        setUpPanel(store: store)
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

    private func setUpPanel(store: HistoryStore) {
        panel = ShelfPanel(
            rootView: HistoryView(
                store: store,
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
            self?.togglePanel()
        }
    }

    // MARK: - 창 열고 닫기

    @objc private func statusItemClicked() {
        togglePanel()
    }

    private func togglePanel() {
        guard let panel else { return }
        if panel.isVisible {
            closePanel()
        } else {
            openPanel()
        }
    }

    private func openPanel() {
        guard let panel, let button = statusItem?.button else { return }

        store?.refreshReferenceDate()
        panel.position(below: button)
        // 앱을 활성 상태로 만들지 않고 창만 앞으로 내보냅니다.
        panel.orderFrontRegardless()
        panel.makeKey()
        statusItem?.button?.highlight(true)
        startEventMonitors()
    }

    private func closePanel() {
        panel?.orderOut(nil)
        statusItem?.button?.highlight(false)
        removeEventMonitors()
    }

    /// 항목을 클립보드에 다시 올린 뒤 창을 닫습니다.
    private func copyAndClose(_ item: ClipboardItem) {
        guard let store else { return }
        let changeCount = store.copyToPasteboard(item)
        // 방금 우리가 만든 변경이므로, 감시자가 이를 새 복사로 오인하지 않도록 알려 둡니다.
        clipboardMonitor?.acknowledgeSelfWrite(changeCount: changeCount)
        closePanel()
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
                    self?.closePanel()
                }
            }
        }

        if escapeKeyMonitor == nil {
            escapeKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard event.keyCode == 53 else { return event } // 53 = Esc
                MainActor.assumeIsolated { self?.closePanel() }
                return nil
            }
        }
    }

    private func removeEventMonitors() {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
        }
        if let escapeKeyMonitor {
            NSEvent.removeMonitor(escapeKeyMonitor)
        }
        outsideClickMonitor = nil
        escapeKeyMonitor = nil
    }
}
