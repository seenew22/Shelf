import AppKit

/// 앱의 시작 지점입니다.
///
/// Dock에 아이콘을 두지 않고 메뉴 바에만 존재하는 보조 앱이므로 활성화 정책을
/// `.accessory`로 지정합니다. Info.plist의 `LSUIElement` 설정과 짝을 이루는 부분입니다.
@main
enum ShelfApp {

    /// `NSApplication.delegate`는 대상을 약하게 참조하기 때문에, 여기서 강한 참조를 따로 붙들어 둡니다.
    @MainActor
    private static var appDelegate: AppDelegate?

    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        appDelegate = delegate
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}
