import Foundation

/// 앱에서 지원하는 표시 언어입니다.
///
/// 언어를 추가하려면 이 열거형에 항목을 하나 넣고, 같은 이름의 `<코드>.lproj` 폴더에
/// `Localizable.strings` 를 만든 뒤 Info.plist 의 `CFBundleLocalizations` 에 코드를
/// 추가하면 됩니다. 나머지 코드는 손댈 필요가 없습니다.
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {

    /// 시스템의 언어 설정을 그대로 따릅니다.
    case system

    case korean = "ko"
    case english = "en"

    var id: String { rawValue }

    /// 언어 선택 메뉴에 표시할 이름입니다.
    ///
    /// 각 언어의 이름은 그 언어 자체로 적습니다. 어떤 언어를 쓰고 있든 자기 언어를
    /// 찾을 수 있어야 하기 때문이며, 이는 언어 선택 화면의 일반적인 관례이기도 합니다.
    /// 다만 "시스템 설정 따름"은 언어 이름이 아니므로 번역 대상입니다.
    var menuTitle: String? {
        switch self {
        case .system: nil
        case .korean: "한국어"
        case .english: "English"
        }
    }
}

/// 화면에 표시하는 문자열의 키 목록입니다.
///
/// 원시 문자열을 여기저기 흩어 놓는 대신 이 열거형을 거치게 해서,
/// 키를 잘못 적으면 컴파일 단계에서 걸리도록 했습니다.
enum StringKey: String {
    case emptyTitle = "empty.title"
    case emptySubtitle = "empty.subtitle"
    case footerClearAll = "footer.clearAll"
    case footerQuit = "footer.quit"
    case rowDelete = "row.delete"
    case rowJustNow = "row.justNow"
    case rowCopied = "row.copied"
    case rowImage = "row.image"
    case hintText = "hint.text"
    case hintImage = "hint.image"
    case hintFile = "hint.file"
    case footerKeyHints = "footer.keyHints"
    case menuLanguage = "menu.language"
    case menuEdgeHover = "menu.edgeHover"
    case menuSettings = "menu.settings"
    case edgeOff = "edge.off"
    case edgeLeft = "edge.left"
    case edgeRight = "edge.right"
    case edgeBoth = "edge.both"
    case languageSystem = "language.system"
}

/// 선택된 언어에 맞는 문자열과 지역 설정을 제공합니다.
///
/// 화면이 이 객체를 관찰하고 있으므로, 언어를 바꾸면 목록 전체가 곧바로 다시 그려집니다.
@MainActor
final class LocalizationManager: ObservableObject {

    private static let preferenceKey = "displayLanguage"

    @Published var language: AppLanguage {
        didSet {
            guard language != oldValue else { return }
            UserDefaults.standard.set(language.rawValue, forKey: Self.preferenceKey)
        }
    }

    init() {
        let stored = UserDefaults.standard.string(forKey: Self.preferenceKey)
        language = stored.flatMap(AppLanguage.init(rawValue:)) ?? .system
    }

    /// 선택된 언어의 문자열 묶음입니다.
    /// 시스템 설정을 따르는 경우에는 앱 기본 묶음이 시스템 언어에 맞춰 알아서 골라 줍니다.
    private var bundle: Bundle {
        guard
            language != .system,
            let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj"),
            let localized = Bundle(path: path)
        else {
            return .main
        }
        return localized
    }

    /// 날짜와 용량 표기에 사용할 지역 설정입니다.
    var locale: Locale {
        language == .system ? .autoupdatingCurrent : Locale(identifier: language.rawValue)
    }

    /// 키에 해당하는 문자열을 돌려줍니다.
    subscript(key: StringKey) -> String {
        bundle.localizedString(forKey: key.rawValue, value: key.rawValue, table: nil)
    }

    /// 자리 표시자가 들어 있는 문자열을 완성해서 돌려줍니다.
    func format(_ key: StringKey, _ arguments: CVarArg...) -> String {
        String(format: self[key], locale: locale, arguments: arguments)
    }

    /// "몇 분 전"을 계산할 때 쓰는 형식기입니다. 언어가 바뀌면 새로 만들어집니다.
    var relativeTimeFormatter: RelativeDateTimeFormatter {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        formatter.locale = locale
        return formatter
    }
}
