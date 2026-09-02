import AppKit
import SwiftUI

/// 메뉴 바 아이콘을 눌렀을 때 나타나는 히스토리 목록 화면입니다.
struct HistoryView: View {
    @ObservedObject var store: HistoryStore

    /// 항목을 클릭해서 클립보드에 다시 올린 뒤 화면을 닫을 때 호출됩니다.
    var onCopy: (ClipboardItem) -> Void

    /// 종료 메뉴를 눌렀을 때 호출됩니다.
    var onQuit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if store.items.isEmpty {
                emptyState
            } else {
                list
            }

            Divider()
            footer
        }
        .frame(width: ShelfPanel.contentWidth, height: ShelfPanel.contentHeight)
        // 테두리가 없는 패널이므로 배경과 둥근 모서리를 여기서 직접 그립니다.
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - 구성 요소

    private var header: some View {
        HStack {
            Text("Shelf")
                .font(.headline)
            Spacer()
            Text("\(store.items.count) / \(HistoryStore.maximumItemCount)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text("아직 복사한 항목이 없습니다")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("무언가를 복사하면 여기에 쌓입니다")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        // 목록 전체를 하나의 시간 기준으로 묶어서, 행마다 타이머를 두지 않고도
        // "몇 분 전" 표시가 1분마다 함께 갱신되도록 합니다.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            // 창을 열 때 갱신되는 기준 시각과, 창이 열려 있는 동안의 주기적 갱신 중
            // 더 늦은 쪽을 사용합니다. 둘 중 하나만으로는 시간 표시가 멈춰 버립니다.
            let referenceDate = max(context.date, store.referenceDate)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(store.items) { item in
                        HistoryRow(
                            item: item,
                            payloadURL: store.payloadURL(for: item),
                            referenceDate: referenceDate,
                            onCopy: { onCopy(item) },
                            onDelete: { store.remove(item) }
                        )
                        Divider().padding(.leading, 44)
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button("모두 지우기") {
                store.removeAll()
            }
            .disabled(store.items.isEmpty)

            Spacer()

            Button("종료", action: onQuit)
        }
        .buttonStyle(.link)
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

/// 히스토리 목록의 한 행입니다. 클릭하면 다시 복사되고, 끌어내면 다른 앱으로 드래그됩니다.
private struct HistoryRow: View {
    let item: ClipboardItem
    let payloadURL: URL?

    /// "몇 분 전"을 계산할 기준 시각입니다. 목록 전체가 같은 기준을 공유합니다.
    let referenceDate: Date

    let onCopy: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false
    @State private var thumbnail: NSImage?

    private static let relativeTimeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    var body: some View {
        HStack(spacing: 10) {
            icon
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.preview)
                    .font(.callout)
                    .lineLimit(2)
                    .truncationMode(.tail)
                Text(timestampText)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isHovering {
                Button {
                    onDelete()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("이 항목을 삭제합니다")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .background(isHovering ? Color.primary.opacity(0.06) : Color.clear)
        .onHover { isHovering = $0 }
        .onTapGesture(perform: onCopy)
        .onDrag(makeItemProvider)
        .task(id: item.id) { await loadThumbnailIfNeeded() }
        .help(dragHint)
    }

    @ViewBuilder
    private var icon: some View {
        if let thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 3))
        } else {
            Image(systemName: item.symbolName)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
        }
    }

    /// 복사한 지 얼마나 지났는지를 표시합니다.
    ///
    /// 방금 복사한 항목은 기준 시각과의 차이가 거의 없어서 표준 형식기가 "0초 후"처럼
    /// 어색하게 표현하므로, 짧은 구간은 따로 문구를 지정합니다.
    private var timestampText: String {
        let elapsed = referenceDate.timeIntervalSince(item.timestamp)
        guard elapsed >= 5 else { return "방금" }
        return Self.relativeTimeFormatter.localizedString(for: item.timestamp, relativeTo: referenceDate)
    }

    private var dragHint: String {
        switch item.kind {
        case .text: "클릭하면 복사되고, 끌어내면 텍스트로 떨어집니다"
        case .image: "클릭하면 복사되고, 끌어내면 이미지 파일로 떨어집니다"
        case .file: "클릭하면 복사되고, 끌어내면 파일로 떨어집니다"
        }
    }

    /// 다른 앱으로 끌어낼 때 넘겨줄 내용물을 만듭니다.
    ///
    /// 이미지와 파일은 디스크에 실제 파일로 저장해 두었기 때문에, 그 위치를 그대로 넘기면
    /// Finder를 비롯한 다른 앱이 진짜 파일로 받아들입니다.
    private func makeItemProvider() -> NSItemProvider {
        switch item.kind {
        case .text:
            return NSItemProvider(object: (item.text ?? "") as NSString)
        case .image, .file:
            guard let payloadURL, let provider = NSItemProvider(contentsOf: payloadURL) else {
                return NSItemProvider()
            }
            // 확장자는 시스템이 자료형에 맞춰 다시 붙이므로, 여기서는 확장자를 뺀 이름만 넘깁니다.
            provider.suggestedName = payloadURL.deletingPathExtension().lastPathComponent
            return provider
        }
    }

    /// 이미지 항목에 한해 작은 미리보기를 만들어 둡니다.
    private func loadThumbnailIfNeeded() async {
        guard item.kind == .image, thumbnail == nil, let payloadURL else { return }
        let image = await Task.detached(priority: .utility) {
            NSImage(contentsOf: payloadURL)
        }.value
        image?.size = NSSize(width: 24, height: 24)
        thumbnail = image
    }
}
