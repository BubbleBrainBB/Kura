import SwiftUI

enum SidebarItem: Hashable {
    case all, uncategorized, untagged, recent, trash
    case folder(String)
    case tag(String)
}

enum KindFilter: String, CaseIterable, Identifiable {
    case all, image, video

    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "全部"
        case .image: "图片"
        case .video: "视频"
        }
    }
}

enum SortKey: String, CaseIterable, Identifiable {
    case added, modified, name, size, rating

    var id: String { rawValue }
    var title: String {
        switch self {
        case .added: "添加时间"
        case .modified: "修改时间"
        case .name: "名称"
        case .size: "文件大小"
        case .rating: "评分"
        }
    }
}

struct MainView: View {
    @ObservedObject var store: LibraryStore
    @State private var sidebar: SidebarItem? = .all
    @State private var selection: Set<String> = []
    @State private var search = ""
    @State private var kindFilter: KindFilter = .all
    @State private var previewID: String?
    @State private var pendingDeletion: [String]?
    @State private var showViewOptions = false
    /// 触控板捏合开始时的缩略图大小
    @State private var pinchStart: Double?
    @AppStorage("sortKey") private var sortKey: SortKey = .added
    @AppStorage("sortAscending") private var ascending = false
    @AppStorage("thumbnailSize") private var thumbnailSize = 200.0
    @AppStorage("showInspector") private var showInspector = true
    @AppStorage("showSidebar") private var showSidebar = true
    /// 界面上实际的显示状态。开关存在 UserDefaults 里，改动绕一圈回来会丢掉动画，
    /// 所以另存一份，开关一变就带着动画改它（按钮、菜单、快捷键都有过渡）
    @State private var sidebarShown = UserDefaults.standard.object(forKey: "showSidebar") as? Bool ?? true
    @State private var inspectorShown = UserDefaults.standard.object(forKey: "showInspector") as? Bool ?? true
    /// 信息面板是否在视图里。收起动画结束后才移除，移除后它的输入框不会再抢到焦点
    @State private var inspectorPresent = UserDefaults.standard.object(forKey: "showInspector") as? Bool ?? true

    private var scope: SidebarItem { sidebar ?? .all }
    static let inspectorWidth: CGFloat = 300
    // 固定时长、到点就停：弹簧曲线收尾会拖很久，每一帧都让网格重排
    private static let panelAnimation = Animation.easeInOut(duration: 0.25)

    var body: some View {
        let visible = visibleItems()
        NavigationSplitView(columnVisibility: Binding(
            get: { sidebarShown ? .all : .detailOnly },
            set: { visibility in
                // 拖动分隔条收起侧栏时，系统自己会做动画
                sidebarShown = visibility != .detailOnly
                showSidebar = sidebarShown
            }
        )) {
            SidebarView(store: store, selection: $sidebar, gridSelection: selection)
                .navigationSplitViewColumnWidth(min: 200, ideal: 236, max: 340)

                .toolbar(removing: .sidebarToggle)
                .toolbar {
                    ToolbarItem {
                        sidebarToggle
                    }
                }
        } detail: {
            // 不用系统 .inspector：在 macOS 27 上它的点击区域和绘制位置错开了一个工具栏的高度
            HStack(spacing: 0) {
                detail(visible)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if inspectorPresent {
                    HStack(spacing: 0) {
                        // 分隔线画到窗口顶部，信息面板和左侧栏一样是完整的一栏
                        Divider()
                            .ignoresSafeArea(.container, edges: .top)
                        InspectorView(
                            store: store,
                            selection: selection.intersection(visible.map(\.id)),
                            scope: scope,
                            scopeTitle: title,
                            visibleItems: visible,
                            searching: !search.trimmingCharacters(in: .whitespaces).isEmpty,
                            onSelectScope: { sidebar = $0 }
                        )
                            .frame(width: Self.inspectorWidth)
                            .frame(maxHeight: .infinity)
                    }
                    .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea(.container, edges: .top))
                    // 宽度从 0 动到面板宽度，网格每一帧跟着变窄，两边始终贴在一起，和左侧栏一样；
                    // 面板内容靠左，多出来的部分在窗口外面，看起来就是从右边滑进来
                    .modifier(ColumnReveal(width: inspectorShown ? Self.inspectorWidth + 1 : 0))
                    .allowsHitTesting(inspectorShown)
                    // 进出只靠宽度变化，不要默认的淡入淡出
                    .transition(.identity)
                }
            }
            // 工具栏和内容用同一块底色，不要白色横条和分隔线（与设计稿一致）
            .toolbarBackground(.hidden, for: .windowToolbar)
        }
        .onChange(of: sidebar) {
            selection = []
            previewID = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .kuraPaste)) { _ in pasteFromClipboard() }
        .onChange(of: showSidebar) { _, shown in
            guard shown != sidebarShown else { return }
            withAnimation(Self.panelAnimation) { sidebarShown = shown }
        }
        .onChange(of: showInspector) { _, shown in
            guard shown != inspectorShown else { return }
            if shown {
                // 先以 0 宽放进来，下一轮再展开，才有从 0 开始的动画。
                // 放进来这一步也要带着动画：和侧栏同时展开时，不带动画的改动会让侧栏的滑动被吞掉、直接跳出来
                withAnimation(Self.panelAnimation) { inspectorPresent = true }
                DispatchQueue.main.async {
                    withAnimation(Self.panelAnimation) { inspectorShown = true }
                }
            } else {
                withAnimation(Self.panelAnimation) {
                    inspectorShown = false
                } completion: {
                    if !inspectorShown { inspectorPresent = false }
                }
            }
        }
        .confirmationDialog(
            "永久删除 \(pendingDeletion?.count ?? 0) 个素材？",
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
            presenting: pendingDeletion
        ) { ids in
            Button("永久删除", role: .destructive) {
                store.deletePermanently(ids)
                selection.subtract(ids)
            }
        } message: { _ in
            Text("素材文件会被移到系统废纸篓。")
        }
        .alert(
            "出错了",
            isPresented: Binding(get: { store.lastError != nil }, set: { if !$0 { store.lastError = nil } }),
            presenting: store.lastError
        ) { _ in
            Button("好") {}
        } message: { message in
            Text(message)
        }
    }

    @ViewBuilder
    private func detail(_ visible: [Item]) -> some View {
        if let previewID, let item = store.item(previewID), visible.contains(where: { $0.id == previewID }) {
            PreviewView(
                store: store,
                scopeTitle: title,
                items: visible,
                item: item,
                onClose: { self.previewID = nil },
                onSelect: { id in
                    self.previewID = id
                    selection = [id]
                },
                trailingGap: inspectorShown ? Self.inspectorWidth : 0
            )
        } else {
            MasonryGrid(
                store: store,
                items: visible,
                scope: scope,
                thumbnailSize: thumbnailSize,
                selection: $selection,
                onOpen: open,
                onRequestDelete: { pendingDeletion = $0 }
            )
            .overlay {
                if visible.isEmpty {
                    EmptyStateView(scope: scope, searching: !search.isEmpty)
                }
            }
            .overlay(alignment: .bottom) {
                if let progress = store.importProgress {
                    ImportProgressView(progress: progress).padding(16)
                }
            }
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        let start = pinchStart ?? thumbnailSize
                        pinchStart = start
                        thumbnailSize = ThumbnailSize.clamped(start * value.magnification)
                    }
                    .onEnded { _ in pinchStart = nil }
            )
            // 网格自己的标题、工具栏和搜索；预览时换成预览自己的
            .navigationTitle(title)
            .modifier(CountedTitle(title: title, count: "\(visible.count)"))
            .toolbar { toolbar }
        }
    }

    private var panelsVisible: Bool { showSidebar || showInspector }

    /// 唯一的面板开关，同时管左侧栏和右侧信息面板：有一侧开着就一起收起，都收起时一起展开。
    /// 单独控制走“显示”菜单的快捷键。它挂在侧栏的工具栏上，侧栏收起后系统仍会把它留在窗口左上角。
    private var sidebarToggle: some View {
        Button {
            let show = !panelsVisible
            showSidebar = show
            showInspector = show
        } label: {
            Label {
                Text(panelsVisible ? "收起两侧面板" : "显示两侧面板")
            } icon: {
                GlyphIcon(.panels)
            }
        }
        .help(panelsVisible ? "收起两侧面板（单独控制：⌃⌘S 侧栏，⌥⌘I 信息面板）" : "显示两侧面板")
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        FlexibleToolbarSpace()

        PlainToolbarItem(placement: .primaryAction) {
            ToolbarSearchField(text: $search)
        }

        ToolbarItem(placement: .primaryAction) {
            viewOptionsButton
        }

        ToolbarItem(placement: .primaryAction) {
            if scope == .trash {
                Button {
                    pendingDeletion = store.items.filter { $0.deletedAt != nil }.map(\.id)
                } label: {
                    Label {
                        Text("清空废纸篓")
                    } icon: {
                        GlyphIcon(.trash)
                    }
                }
                .help("清空废纸篓")
                .disabled(!store.items.contains { $0.deletedAt != nil })
            } else {
                Button {
                    let urls = Panels.chooseFilesToImport()
                    if !urls.isEmpty { store.importFiles(urls, into: currentFolderID) }
                } label: {
                    Label {
                        Text("导入")
                    } icon: {
                        GlyphIcon(.importFile)
                    }
                }
                .help("导入文件或文件夹（也可以直接拖进窗口）")
            }
        }

        inspectorGap
    }

    /// 工具栏最右边留出信息面板的宽度，按钮就停在网格上方，不压在面板上
    @ToolbarContentBuilder
    var inspectorGap: some ToolbarContent {
        if inspectorShown {
            PlainToolbarItem(placement: .primaryAction) {
                Color.clear
                    .frame(width: Self.inspectorWidth, height: 1)
                    .accessibilityHidden(true)
            }
        }
    }

    /// 类型、排序、缩略图大小收在这里；筛选或排序不是默认时，按钮右上角有个小圆点
    private var viewOptionsButton: some View {
        Button {
            showViewOptions.toggle()
        } label: {
            Label {
                Text("视图")
            } icon: {
                GlyphIcon(.viewOptions)
                    .overlay(alignment: .topTrailing) {
                        if ViewOptionsPanel.isCustomized(kind: kindFilter, sortKey: sortKey, ascending: ascending) {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 5, height: 5)
                                .offset(x: 3, y: -2)
                        }
                    }
            }
        }
        .help("视图：类型、排序、缩略图大小")
        .popover(isPresented: $showViewOptions, arrowEdge: .bottom) {
            ViewOptionsPanel(kind: $kindFilter, sortKey: $sortKey, ascending: $ascending, thumbnailSize: $thumbnailSize)
        }
    }

    /// 粘贴进当前范围：在文件夹里就进这个文件夹，在标签下就打上这个标签；粘贴完选中新素材
    private func pasteFromClipboard() {
        var tag: String?
        if case .tag(let name) = scope { tag = name }
        guard let ids = store.pasteFromClipboard(into: currentFolderID, tag: tag) else {
            NSSound.beep()
            return
        }
        if scope == .trash { sidebar = .all }
        previewID = nil
        DispatchQueue.main.async { selection = Set(ids) }
    }

    private var currentFolderID: String? {
        if case .folder(let id) = scope { return id }
        return nil
    }

    private var title: String {
        switch scope {
        case .all: "全部素材"
        case .uncategorized: "未分类"
        case .untagged: "未加标签"
        case .recent: "最近使用"
        case .trash: "废纸篓"
        case .folder(let id): store.folder(id)?.name ?? "文件夹"
        case .tag(let tag): "#\(tag)"
        }
    }

    private func open(_ id: String) {
        previewID = id
        selection = [id]
    }

    private func visibleItems() -> [Item] {
        let query = search.trimmingCharacters(in: .whitespaces)
        let scope = scope
        // 父标签包含所有下级标签的素材；搜索父标签名也能搜到子标签的素材
        var scopeTags: Set<String> = []
        if case .tag(let tag) = scope { scopeTags = store.withDescendants(tag) }
        let queryTags = query.isEmpty ? [] : store.allTags
            .filter { $0.localizedCaseInsensitiveContains(query) }
            .reduce(into: Set<String>()) { $0.formUnion(store.withDescendants($1)) }
        var list = store.items.filter { item in
            if scope == .trash { if item.deletedAt == nil { return false } } else if item.deletedAt != nil { return false }
            switch scope {
            case .all, .trash: break
            case .uncategorized: if !item.folderIDs.isEmpty { return false }
            case .untagged: if !item.tags.isEmpty { return false }
            case .recent: if item.viewedAt == nil { return false }
            case .folder(let id): if !item.folderIDs.contains(id) { return false }
            case .tag: if !item.tags.contains(where: scopeTags.contains) { return false }
            }
            switch kindFilter {
            case .all: break
            case .image: if item.kind != .image { return false }
            case .video: if item.kind != .video { return false }
            }
            guard !query.isEmpty else { return true }
            return item.name.localizedCaseInsensitiveContains(query)
                || item.tags.contains(where: queryTags.contains)
                || item.note.localizedCaseInsensitiveContains(query)
                || item.url.localizedCaseInsensitiveContains(query)
                || item.ext.caseInsensitiveCompare(query) == .orderedSame
        }
        if scope == .recent {
            list.sort { ($0.viewedAt ?? .distantPast) > ($1.viewedAt ?? .distantPast) }
            return list
        }
        list.sort { a, b in
            let ordered: Bool
            switch sortKey {
            case .added: ordered = a.addedAt < b.addedAt
            case .modified: ordered = a.modifiedAt < b.modifiedAt
            case .name: ordered = a.name.localizedStandardCompare(b.name) == .orderedAscending
            case .size: ordered = a.size < b.size
            case .rating: ordered = a.rating < b.rating
            }
            return ascending ? ordered : !ordered
        }
        return list
    }
}

struct ImportProgressView: View {
    let progress: ImportProgress

    var body: some View {
        let finished = progress.done >= progress.total
        HStack(spacing: 12) {
            if finished {
                GlyphIcon(.checkCircle).foregroundStyle(.green)
            } else {
                ProgressView().controlSize(.small)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(finished ? "导入完成" : "正在导入 \(progress.done) / \(progress.total)")
                    .font(.system(size: 12, weight: .medium))
                ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                    .frame(width: 220)
                if progress.failed > 0 {
                    Text("\(progress.failed) 个文件导入失败").font(.caption).foregroundStyle(.red)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }
}

struct EmptyStateView: View {
    let scope: SidebarItem
    let searching: Bool

    var body: some View {
        if searching {
            ContentUnavailableView {
                Label {
                    Text("没有找到素材")
                } icon: {
                    GlyphIcon(.search, size: 40, lineWidth: 1.25)
                }
            } description: {
                Text("换个关键词，或者检查左侧选中的范围。")
            }
        } else if scope == .trash {
            ContentUnavailableView {
                Label {
                    Text("废纸篓是空的")
                } icon: {
                    GlyphIcon(.trash, size: 40, lineWidth: 1.25)
                }
            }
        } else {
            ContentUnavailableView {
                Label {
                    Text("还没有素材")
                } icon: {
                    GlyphIcon(.importFile, size: 40, lineWidth: 1.25)
                }
            } description: {
                Text("把图片、视频或整个文件夹拖进窗口，或者点工具栏的 ＋ 导入。")
            }
        }
    }
}

/// 信息面板这一栏的宽度。做成可动画的，每一帧重新布局，旁边的网格跟着一起变宽变窄
private struct ColumnReveal: ViewModifier, Animatable {
    var width: CGFloat

    var animatableData: CGFloat {
        get { width }
        set { width = newValue }
    }

    func body(content: Content) -> some View {
        content.frame(width: max(width, 0), alignment: .leading)
    }
}
