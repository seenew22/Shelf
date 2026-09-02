import Foundation

/// 히스토리에 보관하는 항목의 종류입니다.
enum ClipboardKind: String, Codable {
    case text
    case image
    case file
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

    /// 목록의 각 행에 표시할 SF Symbols 아이콘 이름입니다.
    var symbolName: String {
        switch kind {
        case .text: "text.alignleft"
        case .image: "photo"
        case .file: "doc"
        }
    }
}
