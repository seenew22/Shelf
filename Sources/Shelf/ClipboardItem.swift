import Foundation

/// 히스토리에 보관하는 항목의 종류입니다.
enum ClipboardKind: String, Codable {
    case text
    case image
    case file
}

/// 복사가 일어난 시점에 앞에 있던 앱입니다.
///
/// 나중에 목록을 훑을 때 "어디서 복사한 것인지"가 내용 못지않게 강한 단서가 됩니다.
struct SourceApplication: Equatable, Sendable {
    var bundleIdentifier: String
    var name: String
}

/// 클립보드를 읽어서 만들어낸, 아직 히스토리에 들어가기 전의 원재료입니다.
///
/// `ClipboardMonitor`가 이 값을 만들어서 `HistoryStore`에 넘기면,
/// 스토어가 지문을 계산하고 디스크에 저장한 뒤 `ClipboardItem`으로 변환합니다.
enum ClipboardCapture {
    case text(String)
    case image(data: Data, fileExtension: String)
    case file(URL)
}

/// 클립보드 히스토리 한 건을 나타내는 모델입니다.
///
/// 문자열은 이 구조체가 직접 들고 있지만, 이미지와 파일은 용량이 크기 때문에
/// `blobs/` 폴더에 따로 저장해 두고 여기서는 경로만 참조합니다.
struct ClipboardItem: Identifiable, Codable, Equatable {
    let id: UUID
    let kind: ClipboardKind

    /// 가장 최근에 복사된 시각입니다. 같은 내용을 다시 복사하면 이 값만 갱신됩니다.
    var timestamp: Date

    /// `.text` 항목의 본문입니다. 나머지 종류에서는 nil입니다.
    let text: String?

    /// `blobs/` 폴더를 기준으로 한 상대 경로이며 `<uuid>/<파일 이름>` 형태입니다.
    /// 파일이 지나치게 커서 복사본을 만들지 않은 경우에는 nil이 됩니다.
    let blobPath: String?

    /// `.file` 항목을 복사한 시점의 원본 위치입니다. 복사본을 만들지 못했을 때의 대비책입니다.
    let originalPath: String?

    /// 목록에 표시할 짧은 요약 문자열입니다.
    /// 텍스트는 본문 앞부분, 파일은 파일 이름이며, 이미지는 언어에 따라 표기가 달라지므로 비어 있습니다.
    let preview: String

    /// 이미지와 파일의 크기입니다. 표시 문구를 선택된 언어로 그때그때 만들기 위해 숫자로 보관합니다.
    let byteCount: Int?

    /// 같은 내용을 다시 복사했는지 판정하기 위한 지문입니다.
    let fingerprint: String

    /// 목록 맨 위에 붙박아 두었는지 여부입니다.
    /// 고정한 항목은 개수 제한에 걸려 밀려나지 않습니다.
    var isPinned: Bool = false

    /// 이 내용을 복사할 때 앞에 있던 앱입니다. 알아내지 못했으면 nil 입니다.
    let sourceBundleIdentifier: String?
    let sourceAppName: String?

    // 항목을 저장한 뒤에 `isPinned` 를 새로 넣었기 때문에, 예전에 저장해 둔 파일에는
    // 이 값이 없습니다. 자동으로 만들어지는 해독기는 없는 값을 오류로 보기 때문에
    // 직접 작성해서, 값이 없으면 고정되지 않은 것으로 읽도록 합니다.
    private enum CodingKeys: String, CodingKey {
        case id, kind, timestamp, text, blobPath, originalPath, preview, byteCount, fingerprint, isPinned
        case sourceBundleIdentifier, sourceAppName
    }

    init(
        id: UUID,
        kind: ClipboardKind,
        timestamp: Date,
        text: String?,
        blobPath: String?,
        originalPath: String?,
        preview: String,
        byteCount: Int?,
        fingerprint: String,
        isPinned: Bool = false,
        source: SourceApplication? = nil
    ) {
        self.id = id
        self.kind = kind
        self.timestamp = timestamp
        self.text = text
        self.blobPath = blobPath
        self.originalPath = originalPath
        self.preview = preview
        self.byteCount = byteCount
        self.fingerprint = fingerprint
        self.isPinned = isPinned
        self.sourceBundleIdentifier = source?.bundleIdentifier
        self.sourceAppName = source?.name
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decode(ClipboardKind.self, forKey: .kind)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        blobPath = try container.decodeIfPresent(String.self, forKey: .blobPath)
        originalPath = try container.decodeIfPresent(String.self, forKey: .originalPath)
        preview = try container.decode(String.self, forKey: .preview)
        byteCount = try container.decodeIfPresent(Int.self, forKey: .byteCount)
        fingerprint = try container.decode(String.self, forKey: .fingerprint)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        sourceBundleIdentifier = try container.decodeIfPresent(String.self, forKey: .sourceBundleIdentifier)
        sourceAppName = try container.decodeIfPresent(String.self, forKey: .sourceAppName)
    }

    /// 드래그하거나 다시 복사할 때 사용할 실제 파일 위치를 돌려줍니다.
    /// - Parameter blobsDirectory: `blobs/` 폴더의 절대 경로입니다.
    func payloadURL(blobsDirectory: URL) -> URL? {
        if let blobPath {
            let url = blobsDirectory.appending(path: blobPath)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        if let originalPath {
            let url = URL(filePath: originalPath)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    /// 파일이나 폴더를 Finder 에서 다룰 수 있는 항목인지 여부입니다.
    var isRevealableInFinder: Bool {
        kind == .file || kind == .image
    }

    /// 목록의 각 행에 표시할 SF Symbols 아이콘 이름입니다.
    var symbolName: String {
        switch kind {
        case .text: "text.alignleft"
        case .image: "photo"
        case .file: "doc"
        }
    }
}
