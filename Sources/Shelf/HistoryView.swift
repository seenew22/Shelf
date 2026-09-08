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

    /// 골라 둔 여러 항목을 한꺼번에 클립보드에 올릴 때 호출됩니다.
    var onCopyMany: ([ClipboardItem]) -> Void

    /// 종료 메뉴를 눌렀을 때 호출됩니다.
    var onQuit: () -> Void

    /// 방금 클릭해서 클립보드에 올린 항목입니다. 창이 닫히기 직전에 잠깐 표시해 줍니다.
    @State private var copiedItemID: UUID?

    /// 창을 열면 곧바로 타이핑해서 찾을 수 있도록 검색란에 초점을 둡니다.
    @FocusState private var isSearchFocused: Bool

    /// 무언가를 끌어다 창 위에 올려 두고 있는 중인지 여부입니다.
    @State private var isDropTargeted = false

    /// 마우스를 올려 둔 항목의 전체 내용입니다. 보여 줄 것이 없으면 nil 입니다.
    @State private var hoveredDetail: String?

    /// 목록을 훑고 지나갈 때마다 뜨지 않도록 잠시 기다리는 작업입니다.
    @State private var detailTask: Task<Void, Never>?

    /// 선택 표시가 행 사이를 미끄러지도록 잇기 위한 이름표입니다.
    @Namespace private var highlightNamespace

    /// 여러 개를 고르기 시작하면서 창 열어 두기를 우리가 켰는지 여부입니다.
    /// 우리가 켠 것만 나중에 되돌립니다.
    @State private var didLockForChoosing = false

    var body: some View {
        VStack(spacing: 0) {
            header
            separator
            searchField
            separator

            if store.items.isEmpty {
                emptyState
            } else if store.visibleItems.isEmpty {
                noMatchesState
            } else {
                list
                    // 목록 아래에 끼워 넣으면 목록이 그만큼 줄어들고, 그 바람에 행이
                    // 커서 밑에서 빠져나가 호버가 풀립니다. 그러면 줄이 사라지고 목록이
                    // 다시 늘어나 행이 돌아오면서 깜빡임이 끝없이 되풀이됩니다.
                    // 위에 덮어씌우면 목록 크기가 그대로라 그 되먹임이 생기지 않습니다.
                    .overlay(alignment: .bottom) { detailBar }
            }

            separator
            footer
        }
        .frame(width: ShelfPanel.contentWidth, height: ShelfPanel.contentHeight)
        // 테두리가 없는 패널이므로 배경과 둥근 모서리를 여기서 직접 그립니다.
        // 모서리 둥글기는 펼쳐지는 동안 함께 변하므로 고정값이 아닙니다.
        .background(cardBackground)
        .clipShape(cardShape)
        .overlay {
            cardShape.strokeBorder(
                isDropTargeted ? ShelfPalette.accent(preferences.tint) : ShelfPalette.cardBorder,
                lineWidth: isDropTargeted ? 2 : 1
            )
        }
        .overlay { dropHint }
        .onDrop(of: Self.acceptedDropTypes, isTargeted: $isDropTargeted, perform: acceptDrop)
        .animation(.easeOut(duration: 0.12), value: isDropTargeted)
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
        // 그림자는 크기 변화와 투명도보다 **바깥쪽에** 그려야 합니다.
        //
        // SwiftUI 는 투명도를 적용할 때 그 안쪽 내용을 한 겹으로 구워내는데, 그 구워지는
        // 범위는 내용의 크기까지입니다. 그림자를 안쪽에 두면 범위 밖으로 번진 부분이
        // 통째로 잘려서, 나타나고 사라지는 동안 그림자가 네모나게 끊겨 보입니다.
        // 바깥에 두면 잘리지 않고, 카드가 커지고 작아지는 동안에도 그림자의 번짐 정도가
        // 일정하게 유지되어 오히려 더 자연스럽습니다.
        //
        // 진한 그림자 한 겹으로 넓게 번지게 하면, 잦아드는 자리가 한 줄로 도드라져서
        // 오려 붙인 것처럼 보입니다. 옅은 그림자를 번짐 거리만 달리해서 여러 겹 포개면
        // 가까운 쪽은 또렷하고 먼 쪽은 서서히 사라져서 경계가 드러나지 않습니다.
        .shadow(color: .black.opacity(0.20), radius: 3, y: 1)
        .shadow(color: .black.opacity(0.16), radius: 10, y: 4)
        .shadow(color: .black.opacity(0.22), radius: 28, y: 12)
        .shadow(color: .black.opacity(0.14), radius: 56, y: 20)
        // 자라날 자리와 그림자가 번질 자리를 창 안쪽에 확보해 둡니다.
        .padding(ShelfPanel.shadowMargin)
        .environment(\.locale, l10n.locale)
        // 창을 열 때마다 기준 시각이 갱신되므로, 그 시점에 지난번 복사 표시를 지웁니다.
        .onChange(of: store.referenceDate) {
            copiedItemID = nil
            isSearchFocused = true
            // 끌어다 놓는 도중에 창이 사라지면 SwiftUI 가 이 값을 되돌려 주지 못합니다.
            // 그대로 두면 다음에 열었을 때 안내 화면이 덮인 채로 나타나므로 여기서 지웁니다.
            isDropTargeted = false
        }
        .onChange(of: store.searchQuery) { selection.reset() }
        // 목록에서 사라진 항목이 고른 목록에 남아 있지 않도록 정리합니다.
        .onChange(of: store.items) {
            selection.pruneChoices(keeping: Set(store.items.map(\.id)))
        }
        // 여러 개를 고르는 동안에는 창이 닫히면 안 됩니다.
        // Finder 를 오가며 고르는 일이 흔하고, 그때마다 닫히면 고를 수가 없습니다.
        .onChange(of: selection.isChoosingMany) {
            if selection.isChoosingMany {
                if !preferences.keepsPanelOpen {
                    preferences.keepsPanelOpen = true
                    didLockForChoosing = true
                }
            } else if didLockForChoosing {
                preferences.keepsPanelOpen = false
                didLockForChoosing = false
            }
        }
    }

    /// 번들에 기록된 버전과, 빌드에 사용한 git 커밋 해시입니다.
    private static let appVersion: String = {
        let information = Bundle.main.infoDictionary
        let version = information?["CFBundleShortVersionString"] as? String ?? "?"
        let revision = information?["CFBundleVersion"] as? String ?? ""
        return revision.isEmpty ? version : "\(version) (\(revision))"
    }()

    /// 지금 골라 둔 항목들입니다. 목록에 보이는 순서를 그대로 따릅니다.
    private var chosenItems: [ClipboardItem] {
        store.visibleItems.filter { selection.chosenIDs.contains($0.id) }
    }

    /// 함께 끌어낼 파일들입니다. 글자 항목은 끌어낼 파일이 없으므로 빠집니다.
    private var chosenFileURLs: [URL] {
        chosenItems.compactMap { $0.isRevealableInFinder ? store.preferredFileURL(for: $0) : nil }
    }

    /// 목록이 차례로 차오를 때, 이 순서의 행이 얼마나 나타났는지를 돌려줍니다.
    ///
    /// 아래쪽 행일수록 늦게 시작하되, 너무 늦게 시작해서 끝내 다 나타나지 못하는 일이
    /// 없도록 시작 시점에 상한을 둡니다.
    private func revealProgress(for position: Int) -> Double {
        guard presentation.rowStagger > 0 else { return 1 }
        let start = min(Double(position) * presentation.rowStagger, 0.6)
        return min(max((presentation.contentPhase - start) / 0.2, 0), 1)
    }

    /// 카드의 바탕입니다. 단색을 고르지 않았으면 뒤가 비치는 시스템 재질을 씁니다.
    @ViewBuilder
    private var cardBackground: some View {
        if let fill = preferences.background.fill {
            fill
        } else {
            Rectangle().fill(.regularMaterial)
        }
    }

    /// 카드의 외곽 모양입니다. 펼쳐지는 동안 둥글기가 변합니다.
    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: presentation.cornerRadius, style: .continuous)
    }

    // MARK: - 구성 요소

    /// 마우스를 올려 둔 항목의 전체 내용을 바닥에 펼쳐 보여 줍니다.
    ///
    /// macOS 기본 도움말 풍선은 앱이 활성 상태일 때만 나타납니다. 이 앱은 일부러 포커스를
    /// 가져가지 않으므로 그 방식으로는 아무것도 뜨지 않습니다. 그래서 직접 그립니다.
    /// 창 안에 자리를 잡아 두면 화면 밖으로 넘칠 일도 없습니다.
    @ViewBuilder
    private var detailBar: some View {
        if let hoveredDetail {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(ShelfPalette.separator)
                    .frame(height: 1)

                Text(hoveredDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.regularMaterial)
            }
            // 덮고 있는 행에 마우스가 그대로 닿아야 호버가 유지됩니다.
            // 이 줄이 마우스를 가로채면 다시 깜빡임이 시작됩니다.
            .allowsHitTesting(false)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    /// 목록을 빠르게 훑고 지나갈 때마다 뜨지 않도록 잠시 기다렸다가 보여 줍니다.
    private func showDetail(_ detail: String?) {
        detailTask?.cancel()

        guard let detail else {
            withAnimation(.easeOut(duration: 0.12)) { hoveredDetail = nil }
            return
        }

        detailTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(320))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.16)) { hoveredDetail = detail }
        }
    }

    /// 머리글과 바닥글을 목록과 나누는 선입니다.
    /// 기본 구분선은 화면마다 두께와 색이 달라서, 직접 그려 두께를 고정합니다.
    private var separator: some View {
        Rectangle()
            .fill(ShelfPalette.separator)
            .frame(height: 1)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Shelf")
                .font(.headline)
            Spacer()
            Text("\(store.items.count) / \(HistoryStore.maximumItemCount)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            keepOpenButton
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
            .foregroundStyle(ShelfPalette.accent(preferences.tint))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(cardBackground)
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

    /// 창을 열어 둔 채로 둘지 정합니다. Finder 를 오가며 여러 개를 모을 때 씁니다.
    private var keepOpenButton: some View {
        Button {
            preferences.keepsPanelOpen.toggle()
        } label: {
            if preferences.keepsPanelOpen {
                Image(systemName: "lock.fill").foregroundStyle(ShelfPalette.accent(preferences.tint))
            } else {
                Image(systemName: "lock.open").foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .help(l10n[preferences.keepsPanelOpen ? .headerStopKeepingOpen : .headerKeepOpen])
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
                ForEach(PanelAnimationStyle.primaryCases) { style in
                    Text(l10n[style.stringKey]).tag(style)
                }
            }
            .pickerStyle(.inline)

            // 나머지는 하위 메뉴로 내려 둡니다. 고른 것이 이 안에 있으면 여기에 표시됩니다.
            Menu(l10n[.menuMoreAnimations]) {
                Picker(l10n[.menuAnimation], selection: $preferences.panelAnimationStyle) {
                    ForEach(PanelAnimationStyle.secondaryCases) { style in
                        Text(l10n[style.stringKey]).tag(style)
                    }
                }
                .pickerStyle(.inline)
            }

            Menu(l10n[.menuAppearance]) {
                Picker(l10n[.menuTint], selection: $preferences.tint) {
                    ForEach(PanelTint.allCases) { tint in
                        Text(l10n[tint.stringKey]).tag(tint)
                    }
                }
                .pickerStyle(.inline)

                Picker(l10n[.menuBackground], selection: $preferences.background) {
                    ForEach(PanelBackground.allCases) { background in
                        Text(l10n[background.stringKey]).tag(background)
                    }
                }
                .pickerStyle(.inline)
            }

            Picker(l10n[.menuLanguage], selection: $l10n.language) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.menuTitle ?? l10n[.languageSystem]).tag(language)
                }
            }
            .pickerStyle(.inline)

            Divider()
            // 어느 시점의 소스로 만든 앱인지 확인할 수 있게 버전과 커밋 해시를 적어 둡니다.
            Text(verbatim: "Shelf \(Self.appVersion)")

            // 소스가 사라졌더라도 감추지 않고, 다시 내려받는다는 것을 알려 줍니다.
            switch Updater.availability {
            case .ready:
                Button(l10n[.menuUpdate]) { Updater.update() }
            case .needsDownload:
                Button(l10n[.menuReinstall]) { Updater.update() }
            }
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


    /// 목록의 행 하나를 만듭니다.
    ///
    /// 목록 안에 그대로 쓰면 하나의 식이 너무 길어져서 컴파일러가 타입을 맞추지 못합니다.
    private func row(
        for item: ClipboardItem,
        at position: Int,
        referenceDate: Date,
        dragBundle: [URL]
    ) -> some View {
        HistoryRow(
            item: item,
            resolveThumbnailURL: { store.payloadURL(for: item) },
            resolveExportURL: { store.preferredFileURL(for: item) },
            referenceDate: referenceDate,
            revealProgress: revealProgress(for: position),
            l10n: l10n,
            tint: preferences.tint,
            isSelected: selection.index == position,
            isChosen: selection.chosenIDs.contains(item.id),
            isChoosingMany: selection.isChoosingMany,
            chosenURLs: dragBundle,
            highlightNamespace: highlightNamespace,
            isCopied: copiedItemID == item.id,
            onHover: { selection.selectByPointer(position) },
            onDetail: showDetail,
            onCopy: {
                guard selection.acceptsActivation else { return }
                copiedItemID = item.id
                onCopy(item)
            },
            onToggleChoice: { selection.toggleChoice(item.id) },
            onBeginChoosing: { selection.beginChoosing(item.id) },
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
    }

    private var list: some View {
        // 목록 전체를 하나의 시간 기준으로 묶어서, 행마다 타이머를 두지 않고도
        // "몇 분 전" 표시가 1분마다 함께 갱신되도록 합니다.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            // 창을 열 때 갱신되는 기준 시각과, 창이 열려 있는 동안의 주기적 갱신 중
            // 더 늦은 쪽을 사용합니다. 둘 중 하나만으로는 시간 표시가 멈춰 버립니다.
            let referenceDate = max(context.date, store.referenceDate)
            // 행마다 다시 구하면 고른 개수만큼 디스크를 반복해서 두드립니다.
            let dragBundle = chosenFileURLs
            ScrollViewReader { scrollProxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(store.visibleItems.enumerated()), id: \.element.id) { position, item in
                            row(for: item, at: position, referenceDate: referenceDate, dragBundle: dragBundle)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    // 화살표로 옮기거나 마우스를 옮길 때, 강조 표시가 행 사이를 미끄러집니다.
                    // 탄성을 주면 제자리를 지나쳤다 돌아오면서 들썩이는 것처럼 보입니다.
                    .animation(.spring(duration: 0.20, bounce: 0), value: selection.index)
                    // 항목을 지우거나 새로 복사했을 때 목록이 툭 끊기지 않고 이어지게 합니다.
                    // 항목 전체를 견주면 글자까지 하나하나 맞춰 봐야 하므로 차례만 견줍니다.
                    .animation(.spring(duration: 0.26, bounce: 0.3), value: store.visibleItems.map(\.id))
                }
                // 끌어내는 동작이 끝날 때까지 목록은 아무 반응도 하지 않습니다.
                //
                // 누름만 막는 것으로는 모자랍니다. 버튼을 누른 채로 커서가 움직이면 행이
                // 그것을 드래그로 받아들여, 손을 대지도 않은 항목을 끌어내기 시작합니다.
                // 눌림과 끌림과 마우스 올림을 한꺼번에 막으려면 반응 자체를 꺼야 합니다.
                .allowsHitTesting(selection.acceptsActivation)
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

    @ViewBuilder
    private var footer: some View {
        if selection.isChoosingMany {
            choosingBar
        } else {
            standardFooter
        }
    }

    /// 여러 개를 고르는 동안 바닥에 나타나는 줄입니다.
    private var choosingBar: some View {
        HStack(spacing: 12) {
            Text(l10n.format(.chooseCount, chosenItems.count))
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Spacer()

            Button(l10n[.chooseCopy]) {
                onCopyMany(chosenItems)
            }
            .disabled(chosenItems.isEmpty)

            Button(l10n[.chooseDelete]) {
                store.remove(chosenItems)
                selection.clearChoices()
            }
            .disabled(chosenItems.isEmpty)

            Button(l10n[.chooseClear]) {
                selection.clearChoices()
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var standardFooter: some View {
        HStack(spacing: 12) {
            Button(l10n[.footerClearAll]) {
                store.removeAll()
            }
            .disabled(store.items.isEmpty)

            Spacer()

            // 단축키를 따로 외우지 않아도 되도록 조작 방법을 적어 둡니다.
            Text(l10n[.footerKeyHints])
                .foregroundStyle(.tertiary)
                .help(l10n[.chooseHint])

            Spacer()

            Button(l10n[.footerQuit], action: onQuit)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

/// 히스토리 목록의 한 행입니다. 클릭하면 다시 복사되고, 끌어내면 다른 앱으로 드래그됩니다.
private struct HistoryRow: View {
    let item: ClipboardItem

    /// 미리보기 그림을 만들 때 쓰는 위치를 구합니다. 보관 사본을 가리킵니다.
    ///
    /// 미리 구해서 넘기지 않고 필요할 때 부릅니다. 위치를 구하려면 파일이 실제로 있는지
    /// 디스크에 물어봐야 하는데, 그것을 화면 그릴 때마다 모든 행에 대해 하면 목록을
    /// 훑는 것만으로도 수백 번 디스크를 두드리게 되어 눈에 띄게 버벅입니다.
    let resolveThumbnailURL: () -> URL?

    /// 다른 앱으로 끌어낼 때 넘길 위치를 구합니다. 파일은 원본을 가리킵니다.
    let resolveExportURL: () -> URL?

    /// "몇 분 전"을 계산할 기준 시각입니다. 목록 전체가 같은 기준을 공유합니다.
    let referenceDate: Date

    /// 목록이 차례로 차오를 때 이 행이 얼마나 나타났는지입니다. 1 이면 다 나타난 상태입니다.
    let revealProgress: Double

    @ObservedObject var l10n: LocalizationManager

    /// 알려야 하는 순간에 쓰는 색입니다.
    let tint: PanelTint

    /// 키보드 또는 마우스로 지금 가리키고 있는 항목인지 여부입니다.
    let isSelected: Bool

    /// 여러 개 고르기에서 골라 둔 항목인지 여부입니다.
    let isChosen: Bool

    /// 지금 여러 개를 고르는 중인지 여부입니다.
    let isChoosingMany: Bool

    /// 함께 끌어낼 파일들입니다. 여러 개를 고르는 중일 때만 씁니다.
    let chosenURLs: [URL]

    /// 강조 표시가 행 사이를 미끄러지도록 잇기 위한 이름표입니다.
    let highlightNamespace: Namespace.ID

    /// 방금 이 항목을 클릭해서 클립보드에 올렸는지 여부입니다.
    let isCopied: Bool

    let onHover: () -> Void

    /// 마우스를 올렸을 때 더 보여 줄 내용이 있으면 알려 줍니다. 없으면 nil 입니다.
    let onDetail: (String?) -> Void

    let onCopy: () -> Void
    let onToggleChoice: () -> Void
    let onBeginChoosing: () -> Void
    let onTogglePin: () -> Void
    let onReveal: () -> Void
    let onOpen: () -> Void
    let onDelete: () -> Void

    /// 목록 왼쪽 아이콘 칸의 한 변 길이입니다.
    static let iconSide: CGFloat = 34

    /// 오른쪽 버튼 자리의 너비입니다. 복사됨 표시까지 들어갈 만큼 잡아 둡니다.
    static let trailingWidth: CGFloat = 62

    @State private var isHovering = false
    @State private var thumbnail: NSImage?

    var body: some View {
        HStack(spacing: 10) {
            if isChoosingMany {
                if isChosen {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(ShelfPalette.accent(tint))
                } else {
                    Image(systemName: "circle").foregroundStyle(.tertiary)
                }
            }

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

            // 오른쪽 자리는 무엇이 놓이든 늘 같은 너비를 차지합니다.
            //
            // 마우스를 올릴 때 버튼이 새로 생겨나면 그만큼 글자 영역이 좁아지고, 줄바꿈이
            // 달라지면서 행 높이까지 바뀝니다. 그러면 행이 커서 밑에서 움직여 호버가 풀리고,
            // 버튼이 사라져 원래대로 돌아가고, 다시 호버가 붙는 일이 끝없이 되풀이됩니다.
            trailingControls
                .frame(width: Self.trailingWidth, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .opacity(revealProgress)
        .offset(x: (1 - revealProgress) * 16)
        .contentShape(Rectangle())
        // 화면 폭을 가득 채우는 띠보다, 안쪽으로 들어간 둥근 바탕이 훨씬 정돈되어 보입니다.
        .background { highlight }
        .animation(.spring(duration: 0.24, bounce: 0.45), value: isCopied)
        .onHover { hovering in
            isHovering = hovering
            // 마우스와 키보드가 서로 다른 곳을 가리키면 헷갈리므로 선택 위치를 맞춰 둡니다.
            if hovering { onHover() }
            onDetail(hovering ? extraDetail : nil)
        }
        .onTapGesture {
            // ⌘ 를 누른 채 클릭하면 고르기입니다. 그냥 클릭은 평소대로 복사입니다.
            if NSEvent.modifierFlags.contains(.command) {
                onToggleChoice()
            } else {
                onCopy()
            }
        }
        // 움직이지 않고 잠시 누르고 있으면 여러 개 고르기로 들어갑니다.
        // 움직이면 끌기로 넘어가므로, 끌어내려던 동작을 가로채지 않습니다.
        .onLongPressGesture(minimumDuration: 0.45, maximumDistance: 4) {
            guard !isChoosingMany else { return }
            onBeginChoosing()
        }
        .onDrag(makeItemProvider)
        // 여러 개를 고르는 중에는 누름과 끌기를 이 겹이 넘겨받습니다.
        .overlay {
            MultiDragLayer(
                isActive: isChoosingMany,
                urls: chosenURLs,
                onClick: onToggleChoice
            )
        }
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

    /// 행의 바탕입니다.
    ///
    /// 지금 가리키고 있는 표시는 행마다 따로 그리지 않고 **하나를 옮겨 다니게** 합니다.
    /// 그래야 화살표로 옮기거나 마우스를 옮길 때 표시가 툭툭 옮겨 붙지 않고 미끄러집니다.
    /// 복사되었거나 골라 둔 표시는 여러 행에 동시에 있을 수 있으므로 각자 그립니다.
    @ViewBuilder
    private var highlight: some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)

        if isCopied || isChosen {
            shape.fill(ShelfPalette.confirmationBackground(tint))
        } else if isSelected {
            shape
                .fill(ShelfPalette.selectionBackground)
                .matchedGeometryEffect(id: "hoveredRow", in: highlightNamespace)
        }
    }

    /// 행 오른쪽에 놓이는 것들입니다. 무엇이 놓이든 차지하는 너비는 같습니다.
    @ViewBuilder
    private var trailingControls: some View {
        if isCopied {
            Label(l10n[.rowCopied], systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(ShelfPalette.accent(tint))
                .labelStyle(.titleAndIcon)
                .transition(.opacity)
        } else {
            HStack(spacing: 6) {
                // 고정한 항목은 마우스를 올리지 않아도 표시가 남아 있어야 합니다.
                Button(action: onTogglePin) {
                    if item.isPinned {
                        Image(systemName: "pin.fill").foregroundStyle(ShelfPalette.accent(tint))
                    } else {
                        Image(systemName: "pin").foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
                .help(l10n[item.isPinned ? .rowUnpin : .rowPin])
                .opacity(item.isPinned || isHovering ? 1 : 0)
                .allowsHitTesting(item.isPinned || isHovering)

                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help(l10n[.rowDelete])
                .opacity(isHovering ? 1 : 0)
                .allowsHitTesting(isHovering)
            }
        }
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
                        .strokeBorder(ShelfPalette.thumbnailBorder, lineWidth: 0.5)
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

    /// 목록에서 두 줄 안에 들어가는 글이라면 마우스를 올려도 새로 보여 줄 것이 없다고 봅니다.
    /// 이 길이를 넘거나 줄바꿈이 섞여 있으면 뒤가 잘렸을 가능성이 높습니다.
    private static let likelyTruncatedLength = 60

    /// 마우스를 올렸을 때 너무 긴 글이 창을 뒤덮지 않도록 자릅니다.
    private static let hoverDetailLimit = 800

    /// 마우스를 올렸을 때 보여 줄 내용입니다.
    ///
    /// 목록에서는 두 줄까지만 보이므로 긴 글은 뒤가 잘립니다. 그 뒷부분을 보려고 따로
    /// 미리보기 화면을 띄우기보다, 이미 있는 자리에서 전체를 보여 주는 편이 가볍습니다.
    ///
    /// 더 알려 줄 것이 없을 때는 대신 다루는 방법을 알려 줍니다. 짧은 글을 그대로 한 번 더
    /// 보여 주는 것은 아무 쓸모가 없기 때문입니다. 파일은 이름이 같아도 어느 폴더에
    /// 있느냐로 갈리므로 언제나 전체 경로를 보여 줍니다.
    private var extraDetail: String? {
        switch item.kind {
        case .text:
            let full = (item.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let mayBeCutOff = full.count > Self.likelyTruncatedLength || full.contains(where: \.isNewline)
            guard mayBeCutOff else { return nil }
            return full.count > Self.hoverDetailLimit
                ? String(full.prefix(Self.hoverDetailLimit)) + "…"
                : full

        case .file:
            return item.originalPath

        case .image:
            return nil
        }
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
            guard let exportURL = resolveExportURL(), let provider = NSItemProvider(contentsOf: exportURL) else {
                return NSItemProvider()
            }
            // 확장자는 시스템이 자료형에 맞춰 다시 붙이므로, 여기서는 확장자를 뺀 이름만 넘깁니다.
            provider.suggestedName = exportURL.deletingPathExtension().lastPathComponent
            return provider
        }
    }

    /// 이미지 항목에 한해 작은 미리보기를 만들어 둡니다.
    ///
    /// 원본을 통째로 읽어서 줄이면 큰 스크린샷 하나에도 메모리를 크게 쓰므로,
    /// ImageIO에게 축소본만 만들어 달라고 요청합니다. 가로세로 비율도 그대로 유지됩니다.
    private func loadThumbnailIfNeeded() async {
        guard item.kind == .image, thumbnail == nil, let payloadURL = resolveThumbnailURL() else { return }
        // 레티나 화면에서도 또렷하도록 표시 크기의 세 배로 만듭니다.
        let maximumPixelSize = Int(HistoryRow.iconSide * 3)
        thumbnail = await Task.detached(priority: .utility) {
            makeThumbnail(from: payloadURL, maximumPixelSize: maximumPixelSize)
        }.value
    }
}
