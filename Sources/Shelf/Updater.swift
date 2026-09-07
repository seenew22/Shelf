import AppKit
import Foundation

/// 앱이 스스로 새 버전을 받아 오도록 돕습니다.
///
/// 빌드할 때 소스가 어디 있었는지를 번들에 적어 두기 때문에, 앱은 자기 소스 자리를 압니다.
/// 새 버전 받기는 그 자리의 설치 스크립트를 그대로 실행하는 것이며, 스크립트가 알아서
/// 새 변경을 받고 다시 빌드해서 앱을 바꿔 끼운 뒤 다시 켭니다.
///
/// 배경에서 몰래 확인하거나 알려 오는 일은 하지 않습니다. 눌렀을 때만 움직입니다.
@MainActor
enum Updater {

    /// 소스가 사라졌을 때 다시 내려받을 자리입니다.
    static let repository = "https://github.com/seenew22/Shelf.git"

    /// 갱신 과정에서 무슨 일이 있었는지 남기는 자리입니다.
    ///
    /// 갱신은 앱이 꺼진 뒤에도 이어지므로, 잘못되어도 앱은 그 사실을 알 방법이 없습니다.
    /// 기록을 남겨 두면 나중에 무엇이 막혔는지 확인할 수 있습니다.
    static var logURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Shelf/update.log")
    }

    /// 지금 갱신을 어떤 방법으로 할 수 있는지입니다.
    enum Availability {
        /// 소스가 제자리에 있습니다. 그대로 받아서 다시 빌드하면 됩니다.
        case ready(script: URL)
        /// 소스를 찾을 수 없습니다. 지웠거나 옮긴 경우이며, 다시 내려받아야 합니다.
        case needsDownload(previousPath: String?)
    }

    static var availability: Availability {
        let recorded = Bundle.main.object(forInfoDictionaryKey: "ShelfSourceDirectory") as? String

        if let recorded {
            let script = URL(filePath: recorded).appending(path: "install.sh")
            if FileManager.default.isExecutableFile(atPath: script.path) {
                return .ready(script: script)
            }
        }

        return .needsDownload(previousPath: recorded)
    }

    /// 새 버전을 받아서 다시 설치합니다.
    ///
    /// 소스가 사라졌다면 기본 자리에 다시 내려받은 뒤 이어서 진행합니다.
    /// 앱을 지웠다 다시 깔 필요 없이, 이 버튼 하나로 돌아옵니다.
    static func update() {
        let command: String
        switch availability {
        case .ready(let script):
            command = shellQuoted(script.path)
        case .needsDownload:
            let fallback = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".shelf")
            command = """
            { [ -d \(shellQuoted(fallback.path))/.git ] \
            || git clone \(shellQuoted(repository)) \(shellQuoted(fallback.path)); } \
            && \(shellQuoted(fallback.appending(path: "install.sh").path))
            """
        }

        // 지금 이 앱이 놓여 있는 자리에 그대로 새것을 놓습니다.
        // 그러지 않으면 갱신할 때마다 응용 프로그램 폴더로 옮겨져서 두 벌이 남습니다.
        let installDirectory = Bundle.main.bundleURL.deletingLastPathComponent().path
        prepareLogFile()

        let process = Process()
        process.executableURL = URL(filePath: "/bin/bash")
        // 이 앱이 꺼져도 설치가 끝까지 가도록 떼어 놓고 띄웁니다.
        // 리눅스에서 흔히 쓰는 setsid 는 macOS 에 없어서, 있는 것처럼 쓰면 아무 일도
        // 일어나지 않고 오류도 보이지 않습니다. nohup 은 기본으로 들어 있습니다.
        process.arguments = [
            "-lc",
            "SHELF_APP_DIR=\(shellQuoted(installDirectory)) nohup bash -c \(shellQuoted(command)) "
                + ">> \(shellQuoted(logURL.path)) 2>&1 &",
        ]

        do {
            try process.run()
        } catch {
            NSLog("Shelf: 새 버전 받기를 시작하지 못했습니다 — \(error.localizedDescription)")
        }
    }

    /// 이번 시도가 언제 시작되었는지 기록해 둡니다. 지난 기록과 섞이지 않게 하려는 것입니다.
    private static func prepareLogFile() {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let header = "\n===== 새 버전 받기 \(stamp) =====\n"

        let manager = FileManager.default
        try? manager.createDirectory(
            at: logURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        guard let handle = try? FileHandle(forWritingTo: logURL) else {
            try? Data(header.utf8).write(to: logURL)
            return
        }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(header.utf8))
    }

    /// 경로에 빈칸이나 따옴표가 섞여 있어도 안전하도록 감쌉니다.
    private static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
