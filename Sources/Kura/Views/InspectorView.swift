import SwiftUI

struct InspectorView: View {
    @ObservedObject var store: LibraryStore
    let selection: Set<String>
    /// 没选素材时展示当前浏览范围的属性
    let scope: SidebarItem
    let scopeTitle: String
    let visibleItems: [Item]
    let searching: Bool
    /// 在信息面板里点父标签、子标签时切换浏览范围
    var onSelectScope: (SidebarItem) -> Void = { _ in }

    var body: some View {
        let items = store.items.filter { selection.contains($0.id) }
        if items.count == 1, let item = items.first {
            ItemInspector(store: store, item: item)
                .id(item.id)
        } else if items.count > 1 {
            MultiItemInspector(store: store, items: items)
        } else {
            ScopeInspector(store: store, scope: scope, title: scopeTitle, items: visibleItems, searching: searching, onSelectScope: onSelectScope)
        }
    }
}

/// 未选中素材时：当前范围（全部、某个文件夹、某个标签…）的属性
struct ScopeInspector: View {
    let store: LibraryStore
    let scope: SidebarItem
    let title: String
    let items: [Item]
    let searching: Bool
    var onSelectScope: (SidebarItem) -> Void = { _ in }
    @State private var childDraft = ""
    @State private var askingChild = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                InspectorSection(title: searching ? "属性 · 搜索结果" : "属性") {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                        ForEach(rows, id: \.0) { row in
                            GridRow {
                                Text(row.0).foregroundStyle(.secondary)
                                Text(row.1).monospacedDigit().textSelection(.enabled)
                            }
                        }
                    }
                    .font(.system(size: 12))
                }

                if case .tag(let tag) = scope {
                    tagSections(tag)
                }

                Text(scope == .trash ? "清空废纸篓后，文件会移到系统废纸篓。" : "选中素材可以查看和编辑它的信息。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .alert(newChildTitle, isPresented: $askingChild) {
            TextField("名称", text: $childDraft)
            Button("好") {
                guard case .tag(let tag) = scope else { return }
                let name = childDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                store.createTag(name, parent: tag)
            }
            Button("取消", role: .cancel) {}
        }
    }

    private var newChildTitle: String {
        if case .tag(let tag) = scope { return "在“\(tag)”下新建子标签" }
        return ""
    }

    /// 父标签：列出子标签，可以点进去；自己设了图标的，显示图标
    @ViewBuilder
    private func tagSections(_ tag: String) -> some View {
        let children = store.tagChildren[tag] ?? []
        if !children.isEmpty {
            let counts = store.counts.tags
            InspectorSection(title: "子标签 · \(children.count)") {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(children, id: \.self) { child in
                        Button {
                            onSelectScope(.tag(child))
                        } label: {
                            HStack(spacing: 8) {
                                TagMark(store: store, tag: child, size: 14)
                                    .foregroundStyle(.secondary)
                                Text(child)
                                Spacer(minLength: 4)
                                Text("\(counts[child] ?? 0)")
                                    .monospacedDigit()
                                    .foregroundStyle(.tertiary)
                                GlyphIcon(.chevronRight, size: 12)
                                    .foregroundStyle(.tertiary)
                            }
                            .font(.system(size: 12))
                            .frame(height: 24)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    Button {
                        childDraft = ""
                        askingChild = true
                    } label: {
                        HStack(spacing: 8) {
                            GlyphIcon(.plus, size: 14)
                            Text("新建子标签…")
                        }
                        .font(.system(size: 12))
                        .frame(height: 24)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                }
            }
        }
        if store.tagInfo[tag]?.icon != nil, let url = store.tagIconURL(tag) {
            InspectorSection(title: "图标") {
                HStack(spacing: 10) {
                    TagIconImage(url: url, size: 20)
                        .frame(width: 36, height: 36)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                    if !children.isEmpty {
                        Text("子标签没单独设图标时，都用这一个")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 8) {
            switch scope {
            case .folder(let id):
                GlyphIcon(.folder).foregroundStyle(Palette.folder(store.folder(id)?.color ?? ""))
                FolderNameField(store: store, folderID: id, name: title)
                    .id(id)
            case .tag(let tag):
                VStack(alignment: .leading, spacing: 4) {
                    let parents = store.ancestors(of: tag)
                    if !parents.isEmpty {
                        HStack(spacing: 3) {
                            ForEach(parents, id: \.self) { parent in
                                Button(parent) { onSelectScope(.tag(parent)) }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(Color.accentColor)
                                Text("›").foregroundStyle(.tertiary)
                            }
                        }
                        .font(.system(size: 11))
                    }
                    HStack(spacing: 8) {
                        TagMark(store: store, tag: tag)
                            .foregroundStyle(.secondary)
                        Text(tag).font(.system(size: 15, weight: .semibold))
                    }
                }
            default:
                GlyphIcon(glyph).foregroundStyle(.secondary)
                Text(title).font(.system(size: 15, weight: .semibold))
            }
        }
    }

    private var glyph: Glyph {
        switch scope {
        case .all: .all
        case .uncategorized: .uncategorized
        case .untagged: .untagged
        case .recent: .recent
        case .trash: .trash
        case .folder: .folder
        case .tag: .tag
        }
    }

    private var rows: [(String, String)] {
        var rows: [(String, String)] = [
            ("素材", "\(items.count) 个"),
            ("大小", Format.bytes(items.reduce(0) { $0 + $1.size })),
        ]
        let images = items.filter { $0.kind == .image }.count
        let videos = items.filter { $0.kind == .video }.count
        let others = items.count - images - videos
        if images > 0 { rows.append(("图片", "\(images) 个")) }
        if videos > 0 { rows.append(("视频", "\(videos) 个")) }
        if others > 0 { rows.append(("其他", "\(others) 个")) }
        if case .tag(let tag) = scope {
            if store.tagChildren[tag]?.isEmpty == false {
                rows.insert(("直接标记", "\(items.filter { $0.tags.contains(tag) }.count) 个"), at: 1)
            }
            if let source = store.tagIconSource(tag), source != tag {
                rows.append(("图标", "继承自“\(source)”"))
            }
        }
        if case .folder(let id) = scope {
            let children = store.childFolders(of: id).count
            if children > 0 { rows.append(("子文件夹", "\(children) 个")) }
        }
        if let latest = items.map(\.addedAt).max() {
            rows.append(("最近添加", Format.date(latest)))
        }
        return rows
    }
}

/// 文件夹名可以直接在信息面板里改，回车或离开输入框时保存
private struct FolderNameField: View {
    let store: LibraryStore
    let folderID: String
    @State private var draft: String
    @FocusState private var focused: Bool

    init(store: LibraryStore, folderID: String, name: String) {
        self.store = store
        self.folderID = folderID
        _draft = State(initialValue: name)
    }

    var body: some View {
        TextField("文件夹名称", text: $draft)
            .textFieldStyle(.plain)
            .font(.system(size: 15, weight: .semibold))
            .focused($focused)
            .onSubmit(commit)
            .onChange(of: focused) { _, isFocused in
                if !isFocused { commit() }
            }
    }

    private func commit() {
        store.renameFolder(folderID, to: draft)
        draft = store.folder(folderID)?.name ?? draft
    }
}

struct InspectorSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            content
        }
    }
}

struct ItemInspector: View {
    let store: LibraryStore
    let item: Item
    @State private var name: String
    @State private var note: String
    @State private var source: String

    init(store: LibraryStore, item: Item) {
        self.store = store
        self.item = item
        _name = State(initialValue: item.name)
        _note = State(initialValue: item.note)
        _source = State(initialValue: item.url)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ThumbnailView(url: store.thumbURL(for: item), rev: item.thumbRev, kind: item.kind, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .frame(height: min(220, 268 / item.displayAspect))
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 6) {
                    TextField("名称", text: $name)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15, weight: .semibold))
                        .onSubmit(commitName)
                    Text("\(item.ext.uppercased()) · \(Format.bytes(item.size))")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    RatingControl(rating: item.rating) { store.setRating([item.id], $0) }
                        .padding(.top, 4)
                }

                if !item.colors.isEmpty {
                    InspectorSection(title: "颜色") {
                        HStack(spacing: 8) {
                            ForEach(item.colors, id: \.self) { hex in
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 22, height: 22)
                                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.15)))
                                    .onTapGesture { ItemActions.copyText(hex) }
                                    .help("\(hex)（点击拷贝）")
                            }
                        }
                    }
                }

                InspectorSection(title: "标签") {
                    TagEditor(
                        store: store,
                        tags: item.tags,
                        onAdd: { store.addTagPath([item.id], $0) },
                        onRemove: { store.removeTag([item.id], $0) }
                    )
                }

                // 不用 TextEditor：它在 ScrollView 里的点击区域会盖住上方的输入框
                InspectorSection(title: "备注") {
                    TextField("添加备注", text: $note, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...10)
                }

                InspectorSection(title: "来源") {
                    HStack(spacing: 6) {
                        TextField("https://", text: $source)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(commitSource)
                        if let url = URL(string: source), url.scheme?.hasPrefix("http") == true {
                            Link(destination: url) {
                                GlyphIcon(.external)
                            }
                            .help("在浏览器中打开")
                        }
                    }
                }

                InspectorSection(title: "文件夹") {
                    FlowLayout {
                        ForEach(item.folderIDs, id: \.self) { id in
                            if let folder = store.folder(id) {
                                TagChip(title: folder.name, glyph: .folder) {
                                    store.removeFromFolder([item.id], id)
                                }
                            }
                        }
                        AddToFolderMenu(store: store, ids: [item.id])
                    }
                }

                InspectorSection(title: "信息") {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                        ForEach(infoRows, id: \.0) { row in
                            GridRow {
                                Text(row.0).foregroundStyle(.secondary)
                                Text(row.1).textSelection(.enabled)
                            }
                        }
                    }
                    .font(.system(size: 12))
                }

                HStack {
                    Button("在访达中显示") { ItemActions.reveal([store.fileURL(for: item)]) }
                    Button("打开") { ItemActions.open(store.fileURL(for: item)) }
                }
                .controlSize(.small)
            }
            .padding(16)
        }
        .task(id: name) {
            try? await Task.sleep(for: .milliseconds(500))
            if !Task.isCancelled { commitName() }
        }
        .task(id: note) {
            try? await Task.sleep(for: .milliseconds(500))
            if !Task.isCancelled { commitNote() }
        }
        .task(id: source) {
            try? await Task.sleep(for: .milliseconds(500))
            if !Task.isCancelled { commitSource() }
        }
        .onDisappear {
            commitName()
            commitNote()
            commitSource()
        }
    }

    private var infoRows: [(String, String)] {
        var rows: [(String, String)] = [("格式", item.ext.uppercased())]
        if let dimensions = item.dimensionText { rows.append(("尺寸", dimensions)) }
        if let duration = item.duration { rows.append(("时长", Format.duration(duration))) }
        rows.append(("文件大小", Format.bytes(item.size)))
        rows.append(("添加时间", Format.date(item.addedAt)))
        rows.append(("修改时间", Format.date(item.modifiedAt)))
        return rows
    }

    private func commitName() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed != store.item(item.id)?.name { store.rename(item.id, to: trimmed) }
    }

    private func commitNote() {
        if note != store.item(item.id)?.note { store.setNote(item.id, note) }
    }

    private func commitSource() {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed != store.item(item.id)?.url { store.setSourceURL(item.id, trimmed) }
    }
}

struct AddToFolderMenu: View {
    let store: LibraryStore
    let ids: [String]

    var body: some View {
        Menu {
            if store.folders.isEmpty {
                Text("还没有文件夹")
            }
            ForEach(store.folderOutline(), id: \.folder.id) { entry in
                Button(String(repeating: "    ", count: entry.depth) + entry.folder.name) {
                    store.addToFolder(ids, entry.folder.id)
                }
            }
        } label: {
            Label {
                Text("添加")
            } icon: {
                Glyph.plus.image(size: 12)
            }
                .font(.system(size: 12))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

struct MultiItemInspector: View {
    let store: LibraryStore
    let items: [Item]

    var body: some View {
        let ids = items.map(\.id)
        let commonTags = items.dropFirst().reduce(Set(items.first?.tags ?? [])) { $0.intersection($1.tags) }
        let commonRating = Set(items.map(\.rating)).count == 1 ? items.first?.rating ?? 0 : 0
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ZStack {
                    ForEach(Array(items.prefix(3).enumerated().reversed()), id: \.element.id) { offset, item in
                        ThumbnailView(url: store.thumbURL(for: item), rev: item.thumbRev, kind: item.kind)
                            .frame(width: 130, height: 130)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white, lineWidth: 2))
                            .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                            .rotationEffect(.degrees(Double(offset) * 7 - 7))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 170)

                VStack(alignment: .leading, spacing: 4) {
                    Text("已选择 \(items.count) 个素材").font(.system(size: 15, weight: .semibold))
                    Text("共 \(Format.bytes(items.reduce(0) { $0 + $1.size }))")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    RatingControl(rating: commonRating) { store.setRating(ids, $0) }
                        .padding(.top, 4)
                }

                InspectorSection(title: "共同标签") {
                    TagEditor(
                        store: store,
                        tags: commonTags.sorted { $0.localizedStandardCompare($1) == .orderedAscending },
                        onAdd: { store.addTagPath(ids, $0) },
                        onRemove: { store.removeTag(ids, $0) }
                    )
                }

                InspectorSection(title: "文件夹") {
                    AddToFolderMenu(store: store, ids: ids)
                }

                Button(role: .destructive) {
                    store.moveToTrash(ids)
                } label: {
                    Label {
                        Text("移到废纸篓")
                    } icon: {
                        GlyphIcon(.trash, size: 14)
                    }
                }
                .controlSize(.small)
            }
            .padding(16)
        }
    }
}
