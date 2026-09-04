import AppKit

/// 복사한 앱의 아이콘을 찾아서 기억해 둡니다.
///
/// 아이콘을 얻으려면 그 앱을 디스크에서 찾아야 하는데, 목록을 그릴 때마다 하면
/// 같은 일을 수십 번 되풀이하게 됩니다. 한 번 찾은 것은 담아 두고 다시 씁니다.
/// 찾지 못한 경우도 함께 기억해서, 없는 앱을 매번 다시 뒤지지 않게 합니다.
@MainActor
enum SourceAppIcon {

    private static var cache: [String: NSImage?] = [:]

    static func icon(forBundleIdentifier bundleIdentifier: String) -> NSImage? {
        if let cached = cache[bundleIdentifier] {
            return cached
        }

        let icon = NSWorkspace.shared
            .urlForApplication(withBundleIdentifier: bundleIdentifier)
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
        cache[bundleIdentifier] = icon
        return icon
    }
}
