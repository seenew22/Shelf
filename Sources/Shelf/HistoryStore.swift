import AppKit
import CryptoKit
import Foundation

/// 클립보드 히스토리를 보관하고 디스크에 저장하는 저장소입니다.
///
/// SwiftUI 화면이 이 객체를 관찰하기 때문에 `ObservableObject`를 따르며,
/// 모든 변경은 메인 스레드에서만 일어나도록 `@MainActor`로 제한해 두었습니다.
@MainActor
final class HistoryStore: ObservableObject {

    /// 히스토리에 보관할 최대 항목 수입니다. 나중에 설정으로 빼기 쉽도록 상수로 두었습니다.
    static let maximumItemCount = 50

    /// 이 크기를 넘는 파일은 복사본을 만들지 않고 원본 위치만 기억합니다.
    /// 동영상처럼 큰 파일을 복사했을 때 저장 공간이 급격히 늘어나는 상황을 막기 위한 장치입니다.
    static let maximumBlobByteCount = 50 * 1024 * 1024

    /// 최신 항목이 앞에 오도록 정렬된 히스토리입니다.
    @Published private(set) var items: [ClipboardItem] = []

    /// "몇 분 전" 표시를 계산할 때 쓰는 기준 시각입니다.
    /// 창을 열 때마다 갱신해서, 창이 닫혀 있던 동안 흐른 시간이 반영되도록 합니다.
    @Published private(set) var referenceDate = Date()

    /// `~/Library/Application Support/Shelf/`
    let storageDirectory: URL

    /// 이미지와 파일의 복사본을 모아두는 폴더입니다.
    let blobsDirectory: URL

    private var historyFileURL: URL {
        storageDirectory.appending(path: "history.json")
    }

    init(storageDirectory: URL? = nil) {
        let base = storageDirectory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Shelf")
        self.storageDirectory = base
        self.blobsDirectory = base.appending(path: "blobs")
        createDirectoriesIfNeeded()
        load()
    }

    /// 시간 표시의 기준 시각을 현재로 맞춥니다.
    func refreshReferenceDate() {
        referenceDate = Date()
    }

    // MARK: - 항목 추가

    /// 클립보드에서 읽어온 원재료를 히스토리에 넣습니다.
    ///
    /// 같은 내용이 이미 들어 있으면 새로 추가하지 않고 맨 위로 끌어올립니다.
    func insert(_ capture: ClipboardCapture) {
        let fingerprint = Self.fingerprint(for: capture)

        if let existingIndex = items.firstIndex(where: { $0.fingerprint == fingerprint }) {
            var existing = items.remove(at: existingIndex)
            existing.timestamp = Date()
            items.insert(existing, at: 0)
            save()
            return
        }

        guard let item = makeItem(from: capture, fingerprint: fingerprint) else { return }
        items.insert(item, at: 0)
        enforceCapacityLimit()
        save()
    }

    /// 원재료를 실제 저장 형태로 바꿉니다. 이미지와 파일은 이 과정에서 디스크에 기록됩니다.
    private func makeItem(from capture: ClipboardCapture, fingerprint: String) -> ClipboardItem? {
        let id = UUID()

        switch capture {
        case .text(let string):
            return ClipboardItem(
                id: id,
                kind: .text,
                timestamp: Date(),
                text: string,
                blobPath: nil,
                originalPath: nil,
                preview: Self.preview(forText: string),
                byteCount: nil,
                fingerprint: fingerprint
            )

        case .image(let data, let fileExtension):
            let name = "Shelf-\(Self.timestampSlug()).\(fileExtension)"
            guard let relativePath = writeBlob(data: data, id: id, fileName: name) else { return nil }
            return ClipboardItem(
                id: id,
                kind: .image,
                timestamp: Date(),
                text: nil,
                blobPath: relativePath,
                originalPath: nil,
                preview: "",
                byteCount: data.count,
                fingerprint: fingerprint
            )

        case .file(let url):
            let fileName = url.lastPathComponent
            let byteCount = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            var relativePath: String?

            // 너무 큰 파일은 복사하지 않고 원본 위치만 기억합니다.
            if byteCount <= Self.maximumBlobByteCount {
                relativePath = copyBlob(from: url, id: id, fileName: fileName)
            }

            return ClipboardItem(
                id: id,
                kind: .file,
                timestamp: Date(),
                text: nil,
                blobPath: relativePath,
                originalPath: url.path,
                preview: fileName,
                byteCount: byteCount,
                fingerprint: fingerprint
            )
        }
    }

    // MARK: - 항목 사용

    /// 항목을 시스템 클립보드에 다시 올립니다.
    /// - Returns: 쓰기 직후의 `changeCount`. 감시자가 자기 자신이 만든 변경을 무시하는 데 사용합니다.
    @discardableResult
    func copyToPasteboard(_ item: ClipboardItem) -> Int {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch item.kind {
        case .text:
            pasteboard.setString(item.text ?? "", forType: .string)

        case .image:
            if let url = item.payloadURL(blobsDirectory: blobsDirectory),
               let data = try? Data(contentsOf: url) {
                // 이미지 자체와 파일 위치를 **하나의 항목 안에** 두 가지 표현으로 담습니다.
                // 둘을 따로 쓰면 클립보드에 항목이 두 개 올라가기 때문에, 여러 항목을 받는
                // 앱에서는 같은 이미지가 두 번 붙습니다. 먼저 적은 표현이 우선 선택되므로,
                // 원래 복사했을 때와 같이 이미지로 붙도록 이미지 데이터를 앞에 둡니다.
                let entry = NSPasteboardItem()
                entry.setData(data, forType: .png)
                entry.setString(url.absoluteString, forType: .fileURL)
                pasteboard.writeObjects([entry])
            }

        case .file:
            if let url = item.payloadURL(blobsDirectory: blobsDirectory) {
                pasteboard.writeObjects([url as NSURL])
            }
        }

        return pasteboard.changeCount
    }

    /// 드래그와 다시 복사에 사용할 실제 파일 위치입니다.
    func payloadURL(for item: ClipboardItem) -> URL? {
        item.payloadURL(blobsDirectory: blobsDirectory)
    }

    // MARK: - 항목 삭제

    func remove(_ item: ClipboardItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let removed = items.remove(at: index)
        deleteBlobDirectory(for: removed)
        save()
    }

    func removeAll() {
        for item in items {
            deleteBlobDirectory(for: item)
        }
        items.removeAll()
        save()
    }

    /// 상한을 넘긴 만큼 오래된 항목부터 지우고, 딸린 복사본 파일도 함께 정리합니다.
    private func enforceCapacityLimit() {
        while items.count > Self.maximumItemCount {
            let dropped = items.removeLast()
            deleteBlobDirectory(for: dropped)
        }
    }

    // MARK: - 디스크 입출력

    private func createDirectoriesIfNeeded() {
        try? FileManager.default.createDirectory(at: blobsDirectory, withIntermediateDirectories: true)
    }

    /// 이미지 데이터를 `blobs/<uuid>/<파일 이름>`에 기록하고 상대 경로를 돌려줍니다.
    private func writeBlob(data: Data, id: UUID, fileName: String) -> String? {
        let directory = blobsDirectory.appending(path: id.uuidString)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: directory.appending(path: fileName))
            return "\(id.uuidString)/\(fileName)"
        } catch {
            NSLog("Shelf: 이미지 저장에 실패했습니다 — \(error.localizedDescription)")
            return nil
        }
    }

    /// 원본 파일을 `blobs/<uuid>/<파일 이름>`으로 복사하고 상대 경로를 돌려줍니다.
    /// 원본 이름을 그대로 유지하기 때문에, 나중에 드래그해서 꺼낼 때도 같은 이름으로 떨어집니다.
    private func copyBlob(from source: URL, id: UUID, fileName: String) -> String? {
        let directory = blobsDirectory.appending(path: id.uuidString)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: source, to: directory.appending(path: fileName))
            return "\(id.uuidString)/\(fileName)"
        } catch {
            NSLog("Shelf: 파일 복사에 실패했습니다 — \(error.localizedDescription)")
            return nil
        }
    }

    private func deleteBlobDirectory(for item: ClipboardItem) {
        guard item.blobPath != nil else { return }
        let directory = blobsDirectory.appending(path: item.id.uuidString)
        try? FileManager.default.removeItem(at: directory)
    }

    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(items).write(to: historyFileURL, options: .atomic)
        } catch {
            NSLog("Shelf: 히스토리 저장에 실패했습니다 — \(error.localizedDescription)")
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: historyFileURL) else { return }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            items = try decoder.decode([ClipboardItem].self, from: data)
            enforceCapacityLimit()
        } catch {
            NSLog("Shelf: 히스토리를 읽지 못했습니다 — \(error.localizedDescription)")
        }
    }

    // MARK: - 보조 함수

    /// 같은 내용인지 판정하기 위한 지문을 계산합니다.
    /// 문자열과 이미지는 내용 자체를 해싱하고, 파일은 경로를 기준으로 삼습니다.
    private static func fingerprint(for capture: ClipboardCapture) -> String {
        switch capture {
        case .text(let string):
            return "text:" + sha256(Data(string.utf8))
        case .image(let data, _):
            return "image:" + sha256(data)
        case .file(let url):
            return "file:" + url.standardizedFileURL.path
        }
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// 목록에 보여줄 한 줄짜리 요약을 만듭니다. 줄바꿈과 앞뒤 공백은 정리합니다.
    private static func preview(forText text: String) -> String {
        let collapsed = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return String(collapsed.prefix(200))
    }

    private static func timestampSlug() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}
