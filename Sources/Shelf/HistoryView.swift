import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// 이미지 파일에서 축소본을 만듭니다. 원본 전체를 메모리에 올리지 않습니다.
private func makeThumbnail(from url: URL, maximumPixelSize: Int) -> NSImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
    return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
}

/// 메뉴 바 아이콘을 눌렀을 때 나타나는 히스토리 목록 화면입니다.
struct HistoryView: View {
    @ObservedObject var store: HistoryStore
    @ObservedObject var l10n: LocalizationManager
    @ObservedObject var selection: PanelSelection
    @ObservedObject var preferences: Preferences

    /// 항목을 클릭해서 클립보드에 다시 올린 뒤 화면을 닫을 때 호출됩니다.
    var onCopy: (ClipboardItem) -> Void

    /// 종료 메뉴를 눌렀을 때 호출됩니다.
    var onQuit: () -> Void

    /// 방금 클릭해서 클립보드에 올린 항목입니다. 창이 닫히기 직전에 잠깐 표시해 줍니다.
    @State private var copiedItemID: UUID?

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
        .environment(\.locale, l10n.locale)
        // 창을 열 때마다 기준 시각이 갱신되므로, 그 시점에 지난번 복사 표시를 지웁니다.
        .onChange(of: store.referenceDate) { copiedItemID = nil }
    }

    /// 번들에 기록된 버전과, 빌드에 사용한 git 커밋 해시입니다.
    private static let appVersion: String = {
        let information = Bundle.main.infoDictionary
        let version = information?["CFBundleShortVersionString"] as? String ?? "?"
        let revision = information?["CFBundleVersion"] as? String ?? ""
        return revision.isEmpty ? version : "\(version) (\(revision))"
    }()

    // MARK: - 구성 요소

    private var header: some View {
        HStack(spacing: 8) {
            Text("Shelf")
                .font(.headline)
            Spacer()
            Text("\(store.items.count) / \(HistoryStore.maximumItemCount)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            settingsMenu
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var settingsMenu: some View {
        Menu {
            Picker(l10n[.menuEdgeHover], selection: $preferences.edgeHoverSide) {
                ForEach(EdgeHoverSide.allCases) { side in
                    Text(l10n[side.stringKey]).tag(side)
                }
            }
            .pickerStyle(.inline)

            Picker(l10n[.menuLanguage], selection: $l10n.language) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.menuTitle ?? l10n[.languageSystem]).tag(language)
                }
            }
            .pickerStyle(.inline)

            Divider()
            // 어느 시점의 소스로 만든 앱인지 확인할 수 있게 버전과 커밋 해시를 적어 둡니다.
            Text(verbatim: "Shelf \(Self.appVersion)")
        } label: {
            Image(systemName: "gearshape")
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(l10n[.menuSettings])
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text(l10n[.emptyTitle])
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(l10n[.emptySubtitle])
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
            ScrollViewReader { scrollProxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(store.items.enumerated()), id: \.element.id) { position, item in
                            HistoryRow(
                                item: item,
                                payloadURL: store.payloadURL(for: item),
                                referenceDate: referenceDate,
                                l10n: l10n,
                                isSelected: selection.index == position,
                                isCopied: copiedItemID == item.id,
                                onHover: { selection.select(position) },
                                onCopy: {
                                    copiedItemID = item.id
                                    onCopy(item)
                                },
                                onDelete: { store.remove(item) }
                            )
                            .id(item.id)
                            Divider().padding(.leading, HistoryRow.iconSide + 22)
                        }
                    }
                }
                // 키보드로 옮긴 항목이 화면 밖에 있으면 따라 내려가도록 합니다.
                .onChange(of: selection.index) {
                    guard store.items.indices.contains(selection.index) else { return }
                    withAnimation(.easeOut(duration: 0.12)) {
                        scrollProxy.scrollTo(store.items[selection.index].id, anchor: .center)
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button(l10n[.footerClearAll]) {
                store.removeAll()
            }
            .disabled(store.items.isEmpty)

            Spacer()

            // 단축키를 따로 외우지 않아도 되도록 조작 방법을 적어 둡니다.
            Text(l10n[.footerKeyHints])
                .foregroundStyle(.tertiary)

            Spacer()

            Button(l10n[.footerQuit], action: onQuit)
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

    @ObservedObject var l10n: LocalizationManager

    /// 키보드 또는 마우스로 지금 가리키고 있는 항목인지 여부입니다.
    let isSelected: Bool

    /// 방금 이 항목을 클릭해서 클립보드에 올렸는지 여부입니다.
    let isCopied: Bool

    let onHover: () -> Void
    let onCopy: () -> Void
    let onDelete: () -> Void

    /// 목록 왼쪽 아이콘 칸의 한 변 길이입니다.
    static let iconSide: CGFloat = 34

    @State private var isHovering = false
    @State private var thumbnail: NSImage?

    var body: some View {
        HStack(spacing: 10) {
            icon
                .frame(width: HistoryRow.iconSide, height: HistoryRow.iconSide)

            VStack(alignment: .leading, spacing: 2) {
                Text(previewText)
                    .font(.callout)
                    .lineLimit(2)
                    .truncationMode(.tail)
                Text(timestampText)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isCopied {
                Label(l10n[.rowCopied], systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                    .labelStyle(.titleAndIcon)
                    .transition(.opacity)
            } else if isHovering {
                Button {
                    onDelete()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help(l10n[.rowDelete])
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .background(rowBackground)
        .animation(.easeOut(duration: 0.12), value: isCopied)
        .onHover { hovering in
            isHovering = hovering
            // 마우스와 키보드가 서로 다른 곳을 가리키면 헷갈리므로 선택 위치를 맞춰 둡니다.
            if hovering { onHover() }
        }
        .onTapGesture(perform: onCopy)
        .onDrag(makeItemProvider)
        .task(id: item.id) { await loadThumbnailIfNeeded() }
        .help(dragHint)
    }

    private var rowBackground: Color {
        if isCopied { return Color.accentColor.opacity(0.22) }
        return isSelected ? Color.primary.opacity(0.08) : Color.clear
    }

    @ViewBuilder
    private var icon: some View {
        if let thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                // 흰 바탕에 가까운 이미지도 배경과 구분되도록 옅은 테두리를 둡니다.
                .overlay {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5)
                }
        } else {
            Image(systemName: item.symbolName)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
        }
    }

    /// 목록에 표시할 문구입니다.
    ///
    /// 텍스트와 파일은 내용 자체가 문구이므로 번역 대상이 아니지만,
    /// 이미지는 "이미지 · 4KB"처럼 언어에 따라 달라지므로 여기서 그때그때 만듭니다.
    private var previewText: String {
        guard item.kind == .image else { return item.preview }
        guard let byteCount = item.byteCount else { return item.preview }
        let size = Int64(byteCount).formatted(.byteCount(style: .file).locale(l10n.locale))
        return l10n.format(.rowImage, size)
    }

    /// 복사한 지 얼마나 지났는지를 표시합니다.
    ///
    /// 방금 복사한 항목은 기준 시각과의 차이가 거의 없어서 표준 형식기가 "0초 후"처럼
    /// 어색하게 표현하므로, 짧은 구간은 따로 문구를 지정합니다.
    private var timestampText: String {
        let elapsed = referenceDate.timeIntervalSince(item.timestamp)
        guard elapsed >= 5 else { return l10n[.rowJustNow] }
        return l10n.relativeTimeFormatter.localizedString(for: item.timestamp, relativeTo: referenceDate)
    }

    private var dragHint: String {
        switch item.kind {
        case .text: l10n[.hintText]
        case .image: l10n[.hintImage]
        case .file: l10n[.hintFile]
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
    ///
    /// 원본을 통째로 읽어서 줄이면 큰 스크린샷 하나에도 메모리를 크게 쓰므로,
    /// ImageIO에게 축소본만 만들어 달라고 요청합니다. 가로세로 비율도 그대로 유지됩니다.
    private func loadThumbnailIfNeeded() async {
        guard item.kind == .image, thumbnail == nil, let payloadURL else { return }
        // 레티나 화면에서도 또렷하도록 표시 크기의 세 배로 만듭니다.
        let maximumPixelSize = Int(HistoryRow.iconSide * 3)
        thumbnail = await Task.detached(priority: .utility) {
            makeThumbnail(from: payloadURL, maximumPixelSize: maximumPixelSize)
        }.value
    }
}
