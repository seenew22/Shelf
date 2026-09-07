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

    /// 빌드에 쓰인 소스가 있던 자리입니다. 그 자리에 설치 스크립트가 있어야 씁니다.
    static var installScriptURL: URL? {
        guard let path = Bundle.main.object(forInfoDictionaryKey: "ShelfSourceDirectory") as? String else {
            return nil
        }
        let script = URL(filePath: path).appending(path: "install.sh")
        guard FileManager.default.isExecutableFile(atPath: script.path) else { return nil }
        return script
    }

    static var canUpdate: Bool { installScriptURL != nil }

    /// 새 버전을 받아서 다시 설치합니다.
    ///
    /// 스크립트는 도중에 이 앱을 끄고 새로 켭니다. 그래서 이 앱의 자식이 아니라 따로 떨어져
    /// 돌도록 띄웁니다. 그러지 않으면 앱이 꺼질 때 스크립트도 함께 끊겨서, 앱이 사라진 채로
    /// 끝나 버립니다.
    static func update() {
        guard let script = installScriptURL else { return }

        // 지금 이 앱이 놓여 있는 자리에 그대로 새것을 놓습니다.
        // 그러지 않으면 갱신할 때마다 응용 프로그램 폴더로 옮겨져서 두 벌이 남습니다.
        let installDirectory = Bundle.main.bundleURL.deletingLastPathComponent().path

        let process = Process()
        process.executableURL = URL(filePath: "/bin/bash")
        // 이 앱이 꺼져도 설치가 끝까지 가도록 떼어 놓고 띄웁니다.
        // 리눅스에서 흔히 쓰는 setsid 는 macOS 에 없어서, 있는 것처럼 쓰면 아무 일도
        // 일어나지 않고 오류도 보이지 않습니다. nohup 은 기본으로 들어 있습니다.
        process.arguments = [
            "-lc",
            "SHELF_APP_DIR=\(shellQuoted(installDirectory)) nohup \(shellQuoted(script.path)) >/dev/null 2>&1 &",
        ]

        do {
            try process.run()
        } catch {
            NSLog("Shelf: 새 버전 받기를 시작하지 못했습니다 — \(error.localizedDescription)")
        }
    }

    /// 경로에 빈칸이나 따옴표가 섞여 있어도 안전하도록 감쌉니다.
    private static func shellQuoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
