import AppKit
import Carbon.HIToolbox

// MARK: - Carbon 콜백과 Swift 객체를 이어주는 표
//
// Carbon이 요구하는 콜백은 문맥을 담을 수 없는 순수한 C 함수여야 합니다.
// 그래서 등록된 단축키의 식별자와 실행할 동작을 파일 범위의 표에 담아 두고,
// 콜백이 식별자를 받아 해당 동작을 찾아 실행하는 구조로 만들었습니다.
// 이 표는 메인 스레드에서만 읽고 쓰기 때문에 별도의 잠금 장치를 두지 않았습니다.

private var hotkeyHandlers: [UInt32: () -> Void] = [:]
private var nextHotkeyIdentifier: UInt32 = 1
private var sharedEventHandler: EventHandlerRef?
private let hotkeySignature: OSType = 0x53686C66 // 'Shlf'

/// 앱이 활성 상태가 아닐 때에도 반응하는 전역 단축키 하나를 등록합니다.
///
/// macOS에서 전역 단축키를 등록하는 방법은 크게 두 가지입니다.
/// 하나는 모든 키 입력을 가로채는 `CGEventTap`인데, 이 방식은 손쉬운 사용 권한을 요구합니다.
/// 다른 하나가 여기서 사용하는 Carbon의 `RegisterEventHotKey`이며,
/// 지정한 조합이 눌렸을 때만 시스템이 알려주기 때문에 별도의 권한 없이 동작합니다.
@MainActor
final class GlobalHotkey {

    private let identifier: UInt32
    private var hotKeyRef: EventHotKeyRef?

    /// - Parameters:
    ///   - keyCode: `kVK_ANSI_V`처럼 Carbon이 정의한 가상 키 코드입니다.
    ///   - modifiers: `cmdKey`, `shiftKey` 등을 더한 조합 키 값입니다.
    init?(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        Self.installSharedEventHandlerIfNeeded()

        identifier = nextHotkeyIdentifier
        nextHotkeyIdentifier += 1

        let hotKeyID = EventHotKeyID(signature: hotkeySignature, id: identifier)
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &reference
        )

        guard status == noErr, let reference else {
            NSLog("Shelf: 전역 단축키를 등록하지 못했습니다 (상태 코드 \(status)). 다른 앱이 같은 조합을 쓰고 있을 수 있습니다.")
            return nil
        }

        hotKeyRef = reference
        hotkeyHandlers[identifier] = handler
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotkeyHandlers[identifier] = nil
    }

    /// 단축키가 눌렸다는 사건을 받아줄 처리기를 앱 전체에 한 번만 설치합니다.
    private static func installSharedEventHandlerIfNeeded() {
        guard sharedEventHandler == nil else { return }

        var eventSpecification = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, _ -> OSStatus in
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr else { return status }

                let identifier = hotKeyID.id
                DispatchQueue.main.async {
                    hotkeyHandlers[identifier]?()
                }
                return noErr
            },
            1,
            &eventSpecification,
            nil,
            &sharedEventHandler
        )
    }
}

extension GlobalHotkey {
    /// 히스토리 창을 여닫는 기본 단축키인 ⌘⇧V입니다.
    /// 조합을 바꾸고 싶다면 이 두 값만 고치면 됩니다.
    static let toggleShelfKeyCode = UInt32(kVK_ANSI_V)
    static let toggleShelfModifiers = UInt32(cmdKey | shiftKey)
}
