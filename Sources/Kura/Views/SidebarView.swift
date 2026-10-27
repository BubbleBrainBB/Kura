import SwiftUI
import UniformTypeIdentifiers

struct SidebarView: View {
    @ObservedObject var store: LibraryStore
    @Binding var selection: SidebarItem?
    /// 网格里选中的素材，用于“用选中的素材作为标签图标”
    var gridSelection: Set<String> = []
    @State private var expanded: Set<String> = []
    /// 标签默认展开，记住收起的
    @State private var collapsedTags: Set<String> = []
    @State private var nameDraft = ""
    @State private var prompt: NamePrompt?
    @State private var folderToDelete: Folder?
    @State private var tagToDelete: String?
    @State private var tagHeaderTargeted = false
    @State private var reclick = ReclickTracker()

    enum NamePrompt {
        case newFolder(parentID: String?)
        case renameFolder(Folder)
        case newTag(parent: String?)
        case renameTag(String)

        var title: String {
            switch self {
            case .newFolder: "新建文件夹"
            case .renameFolder: "重命名文件夹"
            case .newTag(let parent): parent.map { "在“\($0)”下新建子标签" } ?? "新建标签"
            case .renameTag: "重命名标签"
            }
        }
    }

    var body: some View {
        let counts = store.counts
        let tagChildren = store.tagChildren
        List(selection: $selection) {
            Section {
                row("全部素材", .all, .all, counts.all)
                row("未分类", .uncategorized, .uncategorized, counts.uncategorized)
                row("未加标签", .untagged, .untagged, counts.untagged)
                row("最近使用", .recent, .recent, counts.recent)
                row("废纸篓", .trash, .trash, counts.trash)
            }

            Section {
                FolderTree(
                    store: store,
                    parentID: nil,
                    counts: counts.folders,
                    selection: selection,
                    expanded: $expanded,
                    actions: FolderActions(
                        create: { ask(.newFolder(parentID: $0), prefill: "") },
                        rename: { ask(.renameFolder($0), prefill: $0.name) },
                        delete: { folderToDelete = $0 },
                        reclick: reclick
                    )
                )
            } header: {
                HStack {
                    Text("文件夹")
                    Spacer()
                    Button {
                        ask(.newFolder(parentID: nil), prefill: "")
                    } label: {
                        GlyphIcon(.plus, size: 14)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("新建文件夹")
                }
            }

            Section {
                TagTree(
                    store: store,
                    parent: nil,
                    children: tagChildren,
                    counts: counts.tags,
                    selection: selection,
                    collapsed: $collapsedTags,
                    actions: TagActions(
                        selectedImage: selectedImage,
                        create: { ask(.newTag(parent: $0), prefill: "") },
                        rename: { ask(.renameTag($0), prefill: $0) },
                        delete: { tagToDelete = $0 },
                        moved: { collapsedTags.remove($0) },
                        reclick: reclick
                    )
                )
                // 层级一变就整段重建：标签挪进别的分组后，列表会把它旧的选中高亮留在新位置上，
                // 之后怎么点别的标签它都还是选中的样子
                .id(Self.treeSignature(tagChildren))
            } header: {
                // 把标签拖到这个标题上就回到顶层
                HStack {
                    Text("标签")
                    Spacer()
                    Button {
                        ask(.newTag(parent: nil), prefill: "")
                    } label: {
                        GlyphIcon(.plus, size: 14)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("新建标签")
                }
                .padding(.vertical, 2)
                .background(tagHeaderTargeted ? Color.accentColor.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 5))
                .onDrop(of: [.kuraTag], isTargeted: $tagHeaderTargeted) { providers in
                    TagDrag.load(from: providers) { store.setParent($0, nil) }
                }
            }
        }
        .listStyle(.sidebar)
        .background { reclick.listMarker }
        .onAppear {
            reclick.start(selection: { selection }, toggle: toggleExpansion)
        }
        .onDisappear { reclick.stop() }
        // 选中有子级的标签或文件夹时顺手展开，不用再去点箭头；再点一下已选中的就收起
        .onChange(of: selection) { _, item in
            withAnimation(.easeInOut(duration: 0.2)) {
                switch item {
                case .tag(let tag):
                    collapsedTags.subtract([tag] + store.ancestors(of: tag))
                case .folder(let id):
                    expanded.insert(id)
                default:
                    break
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            LibrarySwitcher(store: store)
        }
        .alert(prompt?.title ?? "", isPresented: Binding(get: { prompt != nil }, set: { if !$0 { prompt = nil } }), presenting: prompt) { prompt in
            TextField("名称", text: $nameDraft)
            Button("好") { commit(prompt) }
            Button("取消", role: .cancel) {}
        }
        .confirmationDialog(
            "删除文件夹“\(folderToDelete?.name ?? "")”？",
            isPresented: Binding(get: { folderToDelete != nil }, set: { if !$0 { folderToDelete = nil } }),
            presenting: folderToDelete
        ) { folder in
            Button("删除文件夹", role: .destructive) {
                if selection == .folder(folder.id) { selection = .all }
                store.deleteFolder(folder.id)
            }
        } message: { _ in
            Text("子文件夹也会一起删除。里面的素材不会删除，仍然可以在“全部素材”里找到。")
        }
        .confirmationDialog(
            "删除标签“\(tagToDelete ?? "")”？",
            isPresented: Binding(get: { tagToDelete != nil }, set: { if !$0 { tagToDelete = nil } }),
            presenting: tagToDelete
        ) { tag in
            Button("删除标签", role: .destructive) {
                if selection == .tag(tag) { selection = .all }
                store.deleteTag(tag)
            }
        } message: { tag in
            Text(deleteMessage(tag))
        }
    }

    /// 写清楚会影响哪些子标签和素材
    private func deleteMessage(_ tag: String) -> String {
        let children = store.tagChildren[tag] ?? []
        let direct = store.items.filter { $0.deletedAt == nil && $0.tags.contains(tag) }.count
        var lines: [String] = []
        if !children.isEmpty {
            let names = children.prefix(3).map { "“\($0)”" }.joined(separator: "、")
            let more = children.count > 3 ? " 等 \(children.count) 个子标签" : ""
            let target = store.parent(of: tag).map { "“\($0)”下" } ?? "顶层"
            lines.append("\(names)\(more)会移到\(target)，它们的素材不受影响。")
        }
        lines.append("直接标记了这个标签的 \(direct) 个素材会去掉它，素材本身不会删除。")
        return lines.joined(separator: "\n")
    }

    private static func treeSignature(_ children: [String?: [String]]) -> String {
        children.map { "\($0.key ?? "")>\($0.value.joined(separator: "\u{1F}"))" }
            .sorted()
            .joined(separator: "\u{1E}")
    }

    /// 图标默认灰色，选中时变深；不再染成系统强调色
    /// 网格里正好选中一张能当图标的图片
    private var selectedImage: Item? {
        guard gridSelection.count == 1, let id = gridSelection.first, let item = store.item(id),
              item.kind == .image, LibraryStore.tagIconExtensions.contains(item.ext) else { return nil }
        return item
    }

    private func row(_ title: String, _ glyph: Glyph, _ item: SidebarItem, _ count: Int) -> some View {
        Label {
            Text(title)
        } icon: {
            // 用明确的系统文字色：侧栏选中行会把 .primary 换成强调色
            GlyphIcon(glyph)
                .foregroundStyle(Color(nsColor: selection == item ? .labelColor : .secondaryLabelColor))
        }
        .badge(count)
        .tag(item)
    }

    /// 再点一下已选中的标签或文件夹：展开就收起，收起就展开
    private func toggleExpansion(_ item: SidebarItem) {
        withAnimation(.easeInOut(duration: 0.2)) {
            switch item {
            case .tag(let tag) where store.tagChildren[tag]?.isEmpty == false:
                if collapsedTags.contains(tag) { collapsedTags.remove(tag) } else { collapsedTags.insert(tag) }
            case .folder(let id) where store.hasChildren(id):
                if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
            default:
                break
            }
        }
    }

    private func ask(_ prompt: NamePrompt, prefill: String) {
        nameDraft = prefill
        self.prompt = prompt
    }

    private func commit(_ prompt: NamePrompt) {
        let name = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        switch prompt {
        case .newFolder(let parentID):
            let folder = store.createFolder(named: name, parentID: parentID)
            if let parentID { expanded.insert(parentID) }
            selection = .folder(folder.id)
        case .renameFolder(let folder):
            store.renameFolder(folder.id, to: name)
        case .newTag(let parent):
            store.createTag(name, parent: parent)
            if let parent { collapsedTags.remove(parent) }
            selection = .tag(name)
        case .renameTag(let tag):
            store.renameTag(tag, to: name)
            if selection == .tag(tag) { selection = .tag(name) }
        }
    }
}

struct TagActions {
    /// 网格里正好选中一张能当图标的图片
    var selectedImage: Item?
    var create: (String?) -> Void
    var rename: (String) -> Void
    var delete: (String) -> Void
    /// 有标签移进来了，展开它
    var moved: (String) -> Void
    let reclick: ReclickTracker
}

struct TagTree: View {
    let store: LibraryStore
    let parent: String?
    let children: [String?: [String]]
    let counts: [String: Int]
    let selection: SidebarItem?
    @Binding var collapsed: Set<String>
    let actions: TagActions

    var body: some View {
        ForEach(children[parent] ?? [], id: \.self) { tag in
            if children[tag]?.isEmpty == false {
                DisclosureGroup(isExpanded: isExpanded(tag)) {
                    TagTree(store: store, parent: tag, children: children, counts: counts, selection: selection, collapsed: $collapsed, actions: actions)
                } label: {
                    row(tag)
                }
            } else {
                row(tag)
            }
        }
    }

    private func row(_ tag: String) -> some View {
        TagRow(store: store, tag: tag, count: counts[tag] ?? 0, selected: selection == .tag(tag), actions: actions)
    }

    private func isExpanded(_ tag: String) -> Binding<Bool> {
        Binding(
            get: { !collapsed.contains(tag) },
            set: { if $0 { collapsed.remove(tag) } else { collapsed.insert(tag) } }
        )
    }
}

struct TagRow: View {
    let store: LibraryStore
    let tag: String
    let count: Int
    let selected: Bool
    let actions: TagActions
    @State private var dropTargeted = false

    var body: some View {
        Label {
            Text(tag)
        } icon: {
            TagMark(store: store, tag: tag)
                .foregroundStyle(Color(nsColor: selected ? .labelColor : .secondaryLabelColor))
        }
        .badge(count)
        .tag(SidebarItem.tag(tag))
        .help(store.tagPath(tag))
        .listRowBackground(
            dropTargeted ? RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.25)).padding(.horizontal, 8) : nil
        )
        // 用列表自己的拖动，不用 .onDrag：后者的手势会和行的点选抢鼠标，点了常常没反应
        .itemProvider { TagDrag.provider(for: tag) }
        .onDrop(of: [.kuraTag, .fileURL], isTargeted: $dropTargeted) { providers in
            if providers.contains(where: { $0.hasItemConformingToTypeIdentifier(UTType.kuraTag.identifier) }) {
                return TagDrag.load(from: providers) { dragged in
                    guard dragged != tag, store.canMove(dragged, under: tag) else { return }
                    store.setParent(dragged, tag)
                    actions.moved(tag)
                }
            }
            return DropHelper.fileURLs(from: providers, completion: handleDrop)
        }
        .background { if selected { actions.reclick.rowMarker(for: .tag(tag)) } }
        .contextMenu { menu }
    }

    @ViewBuilder
    private var menu: some View {
        Button("用选中的素材作为图标") {
            if let image = actions.selectedImage { store.setTagIcon(tag, from: store.fileURL(for: image)) }
        }
        .disabled(actions.selectedImage == nil)
        Button("从文件选择图标…") {
            if let url = Panels.chooseTagIcon() { store.setTagIcon(tag, from: url) }
        }
        if store.tagInfo[tag]?.icon != nil {
            // 移除后会改用上级的图标，提前说清楚
            let inherited = store.ancestors(of: tag).reversed().first { store.tagInfo[$0]?.icon != nil }
            Button(inherited.map { "移除图标，改用“\($0)”的" } ?? "移除图标") { store.removeTagIcon(tag) }
        }
        Divider()
        Button("新建子标签…") { actions.create(tag) }
        Menu("移动到") {
            let current = store.parent(of: tag)
            Button("顶层") { store.setParent(tag, nil) }
                .disabled(current == nil)
            Divider()
            ForEach(store.allTags.filter { store.canMove(tag, under: $0) }, id: \.self) { target in
                Toggle(store.tagPath(target), isOn: Binding(
                    get: { target == current },
                    set: { _ in
                        store.setParent(tag, target)
                        actions.moved(target)
                    }
                ))
                .disabled(target == current)
            }
        }
        if store.parent(of: tag) != nil {
            Button("移到顶层") { store.setParent(tag, nil) }
        }
        Divider()
        Button("重命名标签…") { actions.rename(tag) }
        Button("删除标签…") { actions.delete(tag) }
    }

    /// 拖进来的是资源库里的素材：给它们打上这个标签；是外部的图片文件：设成标签图标
    private func handleDrop(_ urls: [URL]) {
        let ids = urls.compactMap { store.item(atFileURL: $0)?.id }
        if !ids.isEmpty {
            store.addTag(ids, tag)
        } else if let image = urls.first(where: { LibraryStore.tagIconExtensions.contains($0.pathExtension.lowercased()) }) {
            store.setTagIcon(tag, from: image)
        }
    }
}

extension UTType {
    /// 在侧栏里拖动标签整理层级
    static let kuraTag = UTType(exportedAs: "io.github.kura.tag")
}

enum TagDrag {
    static func provider(for tag: String) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: UTType.kuraTag.identifier, visibility: .ownProcess) { completion in
            completion(Data(tag.utf8), nil)
            return nil
        }
        return provider
    }

    static func load(from providers: [NSItemProvider], completion: @escaping @MainActor (String) -> Void) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.kuraTag.identifier) }) else { return false }
        _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.kuraTag.identifier) { data, _ in
            guard let data, let tag = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { completion(tag) }
            }
        }
        return true
    }
}

struct FolderActions {
    var create: (String?) -> Void
    var rename: (Folder) -> Void
    var delete: (Folder) -> Void
    let reclick: ReclickTracker
}

struct FolderTree: View {
    @ObservedObject var store: LibraryStore
    let parentID: String?
    let counts: [String: Int]
    let selection: SidebarItem?
    @Binding var expanded: Set<String>
    let actions: FolderActions

    var body: some View {
        ForEach(store.childFolders(of: parentID)) { folder in
            if store.hasChildren(folder.id) {
                DisclosureGroup(isExpanded: isExpanded(folder.id)) {
                    FolderTree(store: store, parentID: folder.id, counts: counts, selection: selection, expanded: $expanded, actions: actions)
                } label: {
                    FolderRow(store: store, folder: folder, count: counts[folder.id] ?? 0, selected: selection == .folder(folder.id), actions: actions)
                }
            } else {
                FolderRow(store: store, folder: folder, count: counts[folder.id] ?? 0, selected: selection == .folder(folder.id), actions: actions)
            }
        }
    }

    private func isExpanded(_ id: String) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(id) },
            set: { if $0 { expanded.insert(id) } else { expanded.remove(id) } }
        )
    }
}

struct FolderRow: View {
    let store: LibraryStore
    let folder: Folder
    let count: Int
    let selected: Bool
    let actions: FolderActions
    @State private var dropTargeted = false

    var body: some View {
        Label {
            Text(folder.name)
        } icon: {
            GlyphIcon(.folder).foregroundStyle(Palette.folder(folder.color))
        }
        .badge(count)
        .tag(SidebarItem.folder(folder.id))
        .background { if selected { actions.reclick.rowMarker(for: .folder(folder.id)) } }
        .listRowBackground(
            dropTargeted ? RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.25)).padding(.horizontal, 8) : nil
        )
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            DropHelper.fileURLs(from: providers) { urls in
                store.importFiles(urls, into: folder.id)
            }
        }
        .contextMenu {
            Button("新建子文件夹…") { actions.create(folder.id) }
            Button("重命名…") { actions.rename(folder) }
            Divider()
            Button("删除文件夹…", role: .destructive) { actions.delete(folder) }
        }
    }
}

struct LibrarySwitcher: View {
    @EnvironmentObject private var app: AppModel
    let store: LibraryStore

    var body: some View {
        Menu {
            let others = app.recents.filter { $0.path != store.url.path }
            if !others.isEmpty {
                Section("切换资源库") {
                    ForEach(others) { recent in
                        Button(recent.name) { app.open(recent.url) }
                            .disabled(!recent.isAvailable)
                    }
                }
            }
            Button("新建资源库…") { app.showNewLibraryPanel() }
            Button("打开资源库…") { app.showOpenLibraryPanel() }
            Button("从 Eagle 导入…") { app.showEagleImportPanel() }
            Divider()
            Button("在访达中显示资源库") { ItemActions.reveal([store.url]) }
            Button("关闭资源库") { app.closeLibrary() }
        } label: {
            HStack(spacing: 10) {
                AppIconView(size: 30)
                Text(store.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                GlyphIcon(.upDown, size: 14)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

/// 认出“又点了一下已经选中的那一行”。列表点已选中的行不会改选中，也不会告诉我们；
/// 往行上加点击手势又会和列表的点选抢鼠标，点了常常没反应。所以在窗口层面看鼠标：
/// 按下和松开都落在选中的那一行上，而且按下时它就已经是选中的，就是再点了一下。左边的展开箭头不算，它自己会展开收起
final class ReclickTracker {
    /// 选中那一行和整个侧边栏背后各放一个不接收点击的 NSView，点的时候直接问它们在窗口里的位置
    fileprivate weak var selectedRow: MarkerView?
    fileprivate weak var list: MarkerView?
    private var pressed: SidebarItem?
    private var monitor: Any?

    func start(selection: @escaping () -> SidebarItem?, toggle: @escaping (SidebarItem) -> Void) {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
            guard let self else { return event }
            let hit = self.selectedItem(at: event).flatMap { $0 == selection() ? $0 : nil }
            if event.type == .leftMouseDown {
                // 按下时列表还没处理这一下，这时的选中就是点之前的选中
                pressed = event.modifierFlags.intersection([.command, .shift, .control, .option]).isEmpty ? hit : nil
            } else {
                if let pressed, pressed == hit {
                    DispatchQueue.main.async { toggle(pressed) }
                }
                pressed = nil
            }
            return event
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    /// 鼠标是否落在选中那一行上：从行内容的左边（展开箭头右边）到侧边栏右边
    private func selectedItem(at event: NSEvent) -> SidebarItem? {
        guard let row = selectedRow, let item = row.item, let list,
              let window = row.window, event.window === window else { return nil }
        let rowRect = row.convert(row.bounds, to: nil)
        let listRect = list.convert(list.bounds, to: nil)
        let area = NSRect(x: rowRect.minX, y: rowRect.minY, width: listRect.maxX - rowRect.minX, height: rowRect.height)
        return area.contains(event.locationInWindow) ? item : nil
    }

    /// 放在选中那一行的背景里
    func rowMarker(for item: SidebarItem) -> some View {
        Marker { view in
            view.item = item
            self.selectedRow = view
        }
    }

    /// 放在侧边栏列表的背景里
    var listMarker: some View {
        Marker { self.list = $0 }
    }
}

fileprivate final class MarkerView: NSView {
    var item: SidebarItem?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private struct Marker: NSViewRepresentable {
    var update: (MarkerView) -> Void

    func makeNSView(context: Context) -> MarkerView { MarkerView() }

    func updateNSView(_ view: MarkerView, context: Context) {
        update(view)
    }
}
