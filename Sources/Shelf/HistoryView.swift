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
    @ObservedObject var presentation: PanelPresentation

    /// 항목을 클릭해서 클립보드에 다시 올린 뒤 화면을 닫을 때 호출됩니다.
    var onCopy: (ClipboardItem) -> Void

    /// 종료 메뉴를 눌렀을 때 호출됩니다.
    var onQuit: () -> Void

    /// 방금 클릭해서 클립보드에 올린 항목입니다. 창이 닫히기 직전에 잠깐 표시해 줍니다.
    @State private var copiedItemID: UUID?

    /// 창을 열면 곧바로 타이핑해서 찾을 수 있도록 검색란에 초점을 둡니다.
    @FocusState private var isSearchFocused: Bool

    /// 무언가를 끌어다 창 위에 올려 두고 있는 중인지 여부입니다.
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            searchField
            Divider()

            if store.items.isEmpty {
                emptyState
            } else if store.visibleItems.isEmpty {
                noMatchesState
            } else {
                list
            }

            Divider()
            footer
        }
        .frame(width: ShelfPanel.contentWidth, height: ShelfPanel.contentHeight)
        // 테두리가 없는 패널이므로 배경과 둥근 모서리를 여기서 직접 그립니다.
        // 모서리 둥글기는 펼쳐지는 동안 함께 변하므로 고정값이 아닙니다.
        .background(.regularMaterial)
        .clipShape(cardShape)
        .overlay {
            cardShape.strokeBorder(
                isDropTargeted ? Color.accentColor : Color.primary.opacity(0.18),
                lineWidth: isDropTargeted ? 2 : 1
            )
        }
        .overlay { dropHint }
        .onDrop(of: Self.acceptedDropTypes, isTargeted: $isDropTargeted, perform: acceptDrop)
        .animation(.easeOut(duration: 0.12), value: isDropTargeted)
        // 그림자도 카드와 함께 자라야 하므로 창이 아니라 여기서 그립니다.
        // 넓게 번지는 그림자만으로는 윤곽이 흐려서, 가까이 붙는 그림자를 한 겹 더 둡니다.
        .shadow(color: .black.opacity(0.45), radius: 22, y: 10)
        .shadow(color: .black.opacity(0.28), radius: 4, y: 1)
        // 열린 방향 쪽 모서리를 기준으로 부풀어 오르면서 나타납니다.
        .blur(radius: presentation.blurRadius)
        .rotationEffect(presentation.rotation, anchor: presentation.anchor)
        // 경첩을 축으로 열리는 방식에서만 각도가 0 이 아닙니다.
        .rotation3DEffect(
            presentation.openAngle,
            axis: presentation.opensAroundHorizontalAxis ? (x: 1, y: 0, z: 0) : (x: 0, y: 1, z: 0),
            anchor: presentation.opensAroundHorizontalAxis ? .top : presentation.anchor,
            perspective: 0.55
        )
        // 제자리에 닿은 뒤 여러 번 출렁이는 방식에서만 움직입니다.
        .wobble(presentation.wobble, phase: presentation.wobblePhase, anchor: .center)
        .scaleEffect(
            x: presentation.scaleX,
            y: presentation.scaleY,
            anchor: presentation.anchor
        )
        .opacity(presentation.opacity)
        // 자라날 자리와 그림자가 잘릴 자리를 창 안쪽에 확보해 둡니다.
        .padding(ShelfPanel.shadowMargin)
        .environment(\.locale, l10n.locale)
        // 창을 열 때마다 기준 시각이 갱신되므로, 그 시점에 지난번 복사 표시를 지웁니다.
        .onChange(of: store.referenceDate) {
            copiedItemID = nil
            isSearchFocused = true
        }
        .onChange(of: store.searchQuery) { selection.reset() }
    }

    /// 번들에 기록된 버전과, 빌드에 사용한 git 커밋 해시입니다.
    private static let appVersion: String = {
        let information = Bundle.main.infoDictionary
        let version = information?["CFBundleShortVersionString"] as? String ?? "?"
        let revision = information?["CFBundleVersion"] as? String ?? ""
        return revision.isEmpty ? version : "\(version) (\(revision))"
    }()

    /// 목록이 차례로 차오를 때, 이 순서의 행이 얼마나 나타났는지를 돌려줍니다.
    ///
    /// 아래쪽 행일수록 늦게 시작하되, 너무 늦게 시작해서 끝내 다 나타나지 못하는 일이
    /// 없도록 시작 시점에 상한을 둡니다.
    private func revealProgress(for position: Int) -> Double {
        guard presentation.rowStagger > 0 else { return 1 }
        let start = min(Double(position) * presentation.rowStagger, 0.6)
        return min(max((presentation.contentPhase - start) / 0.2, 0), 1)
    }

    /// 카드의 외곽 모양입니다. 펼쳐지는 동안 둥글기가 변합니다.
    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: presentation.cornerRadius, style: .continuous)
    }

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
            finderButton
            settingsMenu
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(.tertiary)

            TextField(l10n[.searchPlaceholder], text: $store.searchQuery)
                .textFieldStyle(.plain)
                .font(.callout)
                .focused($isSearchFocused)

            if !store.searchQuery.isEmpty {
                Button {
                    store.searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    /// 무언가를 끌어와 올려 두었을 때 보여 주는 안내입니다.
    @ViewBuilder
    private var dropHint: some View {
        if isDropTargeted {
            VStack(spacing: 8) {
                Image(systemName: "tray.and.arrow.down.fill")
                    .font(.system(size: 30))
                Text(l10n[.dropHint])
                    .font(.callout)
            }
            .foregroundStyle(Color.accentColor)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.regularMaterial)
            .transition(.opacity)
        }
    }

    // 복사해서 들어오는 것과 같은 종류를 받습니다.
    private static let acceptedDropTypes: [UTType] = [.fileURL, .png, .tiff, .utf8PlainText]

    /// 끌어다 놓은 것을 히스토리에 담습니다.
    ///
    /// 하나의 꾸러미가 여러 형태를 함께 담고 있는 경우가 많으므로, 가장 구체적인 것부터
    /// 확인해서 하나만 받아들입니다. 그러지 않으면 같은 것이 파일과 글자로 두 번 들어옵니다.
    private func acceptDrop(_ providers: [NSItemProvider]) -> Bool {
        var accepted = false

        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self) {
                accepted = true
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url, url.isFileURL else { return }
                    Task { @MainActor in store.insert(.file(url)) }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.png.identifier) {
                accepted = true
                loadImage(from: provider, typeIdentifier: UTType.png.identifier, convert: false)
            } else if provider.hasItemConformingToTypeIdentifier(UTType.tiff.identifier) {
                accepted = true
                loadImage(from: provider, typeIdentifier: UTType.tiff.identifier, convert: true)
            } else if provider.hasItemConformingToTypeIdentifier(UTType.utf8PlainText.identifier) {
                accepted = true
                provider.loadDataRepresentation(forTypeIdentifier: UTType.utf8PlainText.identifier) { data, _ in
                    guard let data, let text = String(data: data, encoding: .utf8),
                          !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    else {
                        return
                    }
                    Task { @MainActor in store.insert(.text(text)) }
                }
            }
        }

        return accepted
    }

    /// 이미지를 받아서 PNG 로 통일해 담습니다.
    /// 저장과 드래그를 모두 같은 방식으로 처리하기 위한 것입니다.
    private func loadImage(from provider: NSItemProvider, typeIdentifier: String, convert: Bool) {
        provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, _ in
            guard let data else { return }

            let pngData: Data?
            if convert {
                pngData = NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:])
            } else {
                pngData = data
            }

            guard let pngData else { return }
            Task { @MainActor in store.insert(.image(data: pngData, fileExtension: "png")) }
        }
    }

    private var noMatchesState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 24))
                .foregroundStyle(.tertiary)
            Text(l10n[.searchEmpty])
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Finder 를 앞으로 불러옵니다. 항목과 상관없이 그냥 파일 탐색으로 넘어가고 싶을 때 씁니다.
    private var finderButton: some View {
        Button {
            store.activateFinder()
        } label: {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help(l10n[.headerOpenFinder])
    }

    private var settingsMenu: some View {
        Menu {
            Picker(l10n[.menuEdgeHover], selection: $preferences.edgeHoverSide) {
                ForEach(EdgeHoverSide.allCases) { side in
                    Text(l10n[side.stringKey]).tag(side)
                }
            }
            .pickerStyle(.inline)

            Picker(l10n[.menuEdgeOpenMode], selection: $preferences.edgeOpenMode) {
                ForEach(EdgeOpenMode.allCases) { mode in
                    Text(l10n[mode.stringKey]).tag(mode)
                }
            }
            .pickerStyle(.inline)
            .disabled(preferences.edgeHoverSide == .off)

            Picker(l10n[.menuAnimation], selection: $preferences.panelAnimationStyle) {
                ForEach(PanelAnimationStyle.allCases) { style in
                    Text(l10n[style.stringKey]).tag(style)
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
            Text(l10n[.dropHint])
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
                        ForEach(Array(store.visibleItems.enumerated()), id: \.element.id) { position, item in
                            HistoryRow(
                                item: item,
                                payloadURL: store.payloadURL(for: item),
                                referenceDate: referenceDate,
                                revealProgress: revealProgress(for: position),
                                l10n: l10n,
                                isSelected: selection.index == position,
                                isCopied: copiedItemID == item.id,
                                onHover: { selection.selectByPointer(position) },
                                onCopy: {
                                    guard selection.acceptsActivation else { return }
                                    copiedItemID = item.id
                                    onCopy(item)
                                },
                                onTogglePin: {
                                    guard selection.acceptsActivation else { return }
                                    store.togglePin(item)
                                },
                                onReveal: { store.revealInFinder(item) },
                                onOpen: { store.openWithDefaultApplication(item) },
                                onDelete: {
                                    guard selection.acceptsActivation else { return }
                                    store.remove(item)
                                }
                            )
                            .id(item.id)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                            Divider().padding(.leading, HistoryRow.iconSide + 22)
                        }
                    }
                    // 항목을 지우거나 새로 복사했을 때 목록이 툭 끊기지 않고 이어지게 합니다.
                    .animation(.spring(duration: 0.26, bounce: 0.3), value: store.visibleItems)
                }
                // 키보드로 옮겼을 때만 목록이 따라 움직입니다.
                // 마우스로 가리켰을 때도 움직이면 항목이 커서 밑에서 빠져나가 버립니다.
                // 또한 화면 가운데로 끌어오지 않고, 보이게 되는 데 필요한 만큼만 움직입니다.
                .onChange(of: selection.scrollRequestID) {
                    let visible = store.visibleItems
                    guard visible.indices.contains(selection.index) else { return }
                    withAnimation(.easeOut(duration: 0.12)) {
                        scrollProxy.scrollTo(visible[selection.index].id)
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

    /// 목록이 차례로 차오를 때 이 행이 얼마나 나타났는지입니다. 1 이면 다 나타난 상태입니다.
    let revealProgress: Double

    @ObservedObject var l10n: LocalizationManager

    /// 키보드 또는 마우스로 지금 가리키고 있는 항목인지 여부입니다.
    let isSelected: Bool

    /// 방금 이 항목을 클릭해서 클립보드에 올렸는지 여부입니다.
    let isCopied: Bool

    let onHover: () -> Void
    let onCopy: () -> Void
    let onTogglePin: () -> Void
    let onReveal: () -> Void
    let onOpen: () -> Void
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
                HStack(spacing: 4) {
                    // 어디서 복사했는지는 내용 못지않게 강한 단서라서, 시각과 나란히 둡니다.
                    if let bundleIdentifier = item.sourceBundleIdentifier,
                       let icon = SourceAppIcon.icon(forBundleIdentifier: bundleIdentifier) {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 12, height: 12)
                            .help(item.sourceAppName ?? bundleIdentifier)
                    }
                    Text(timestampText)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isCopied {
                Label(l10n[.rowCopied], systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                    .labelStyle(.titleAndIcon)
                    .transition(.opacity)
            } else {
                // 고정한 항목은 마우스를 올리지 않아도 표시가 남아 있어야 합니다.
                if item.isPinned || isHovering {
                    Button(action: onTogglePin) {
                        if item.isPinned {
                            Image(systemName: "pin.fill").foregroundStyle(Color.accentColor)
                        } else {
                            Image(systemName: "pin").foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .help(l10n[item.isPinned ? .rowUnpin : .rowPin])
                }

                if isHovering {
                    Button(action: onDelete) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help(l10n[.rowDelete])
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .opacity(revealProgress)
        .offset(x: (1 - revealProgress) * 16)
        .contentShape(Rectangle())
        .background(rowBackground)
        .animation(.spring(duration: 0.24, bounce: 0.45), value: isCopied)
        .onHover { hovering in
            isHovering = hovering
            // 마우스와 키보드가 서로 다른 곳을 가리키면 헷갈리므로 선택 위치를 맞춰 둡니다.
            if hovering { onHover() }
        }
        .onTapGesture(perform: onCopy)
        .onDrag(makeItemProvider)
        .contextMenu { contextMenu }
        .task(id: item.id) { await loadThumbnailIfNeeded() }
        .help(dragHint)
    }

    @ViewBuilder
    private var contextMenu: some View {
        Button(l10n[item.isPinned ? .rowUnpin : .rowPin], action: onTogglePin)

        // 파일과 이미지만 Finder 에서 다룰 수 있습니다. 텍스트에는 딸린 파일이 없습니다.
        if item.isRevealableInFinder {
            Divider()
            Button(l10n[.rowRevealInFinder], action: onReveal)
                .keyboardShortcut(.return, modifiers: .command)
            Button(l10n[.rowOpen], action: onOpen)
        }

        Divider()
        Button(l10n[.rowDelete], role: .destructive, action: onDelete)
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
