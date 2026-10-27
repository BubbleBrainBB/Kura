import SwiftUI

/// 瀑布流布局：每个素材依次放进当前最矮的一列，算出它在网格里的位置
struct MasonryLayout {
    static let spacing: CGFloat = 16
    static let padding: CGFloat = 20

    let columnWidth: CGFloat
    /// 和 items 一一对应
    let frames: [CGRect]
    let contentHeight: CGFloat

    init(width: CGFloat, target: Double, items: [Item]) {
        let usable = max(0, width - Self.padding * 2)
        let count = max(1, Int((usable + Self.spacing) / (CGFloat(target) + Self.spacing)))
        let columnWidth = max(60, floor((usable - Self.spacing * CGFloat(count - 1)) / CGFloat(count)))
        var heights = Array(repeating: Self.padding, count: count)
        var frames: [CGRect] = []
        frames.reserveCapacity(items.count)
        for item in items {
            let column = heights.indices.min { heights[$0] < heights[$1] } ?? 0
            let height = GridCell.height(for: item, width: columnWidth)
            let x = Self.padding + CGFloat(column) * (columnWidth + Self.spacing)
            frames.append(CGRect(x: x, y: heights[column], width: columnWidth, height: height))
            heights[column] += height + Self.spacing
        }
        self.columnWidth = columnWidth
        self.frames = frames
        contentHeight = (heights.max() ?? Self.padding) - Self.spacing + Self.padding
    }

    /// 和这一段纵向范围有交集的素材下标
    func indices(between top: CGFloat, and bottom: CGFloat) -> [Int] {
        frames.indices.filter { frames[$0].maxY >= top && frames[$0].minY <= bottom }
    }
}

/// 素材网格。每个素材按算好的坐标摆放，宽度一变它就从旧位置滑到新位置（同一个素材换列也是同一个视图）；
/// 只建出看得见的那一段（上下各多留一些），素材再多也不慢
struct MasonryGrid: View {
    @ObservedObject var store: LibraryStore
    let items: [Item]
    let scope: SidebarItem
    let thumbnailSize: Double
    @Binding var selection: Set<String>
    var onOpen: (String) -> Void
    var onRequestDelete: ([String]) -> Void

    /// 素材换位置、改大小时的过渡
    static let moveAnimation = Animation.smooth(duration: 0.32)
    private static let scrollSpace = "masonry-scroll"

    @State private var anchorID: String?
    @State private var dropTargeted = false
    /// 视口顶部滚到了第几个“半屏”。只在跨过半屏时才变，滚动时不用每帧重算要建哪些素材
    @State private var scrollBand = 0
    @FocusState private var focused: Bool

    var body: some View {
        GeometryReader { geometry in
            let layout = MasonryLayout(width: geometry.size.width, target: thumbnailSize, items: items)
            let viewport = max(geometry.size.height, 1)
            let half = viewport / 2
            // 上面多留一屏，下面多留一屏半
            let top = CGFloat(scrollBand - 2) * half
            let bottom = CGFloat(scrollBand + 5) * half
            ScrollView {
                ZStack(alignment: .topLeading) {
                    Color.clear
                        .frame(width: geometry.size.width, height: max(layout.contentHeight, viewport))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selection = []
                            focused = true
                        }
                        .background {
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: MasonryScrollOffsetKey.self,
                                    value: -proxy.frame(in: .named(Self.scrollSpace)).minY
                                )
                            }
                        }
                    ForEach(layout.indices(between: top, and: bottom), id: \.self) { index in
                        cell(items[index], frame: layout.frames[index])
                    }
                }
            }
            .coordinateSpace(name: Self.scrollSpace)
            .onPreferenceChange(MasonryScrollOffsetKey.self) { offset in
                let band = Int((max(offset, 0) / half).rounded(.down))
                if band != scrollBand { scrollBand = band }
            }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(phases: .down, action: handleKey)
        .onAppear { focused = true }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            DropHelper.fileURLs(from: providers) { urls in
                store.importFiles(urls, into: currentFolderID)
            }
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
    }

    private var currentFolderID: String? {
        if case .folder(let id) = scope { return id }
        return nil
    }

    private func cell(_ item: Item, frame: CGRect) -> some View {
        PlacedCell(rect: frame) { size in
            GridCell(item: item, thumbnailURL: store.thumbURL(for: item), width: size.width, selected: selection.contains(item.id))
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .contentShape(Rectangle())
                .onTapGesture { click(item) }
                .onDrag { NSItemProvider(contentsOf: store.fileURL(for: item)) ?? NSItemProvider() }
                .contextMenu {
                    ItemMenu(
                        store: store,
                        ids: selection.contains(item.id) ? Array(selection) : [item.id],
                        scope: scope,
                        onOpen: { onOpen(item.id) },
                        onRequestDelete: onRequestDelete
                    )
                }
        }
        // 网格变宽变窄、换列、调缩略图大小时，素材从原来的位置滑过去
        .animation(Self.moveAnimation, value: frame)
    }

    private func click(_ item: Item) {
        focused = true
        let event = NSApp.currentEvent
        if event?.clickCount == 2 {
            onOpen(item.id)
            return
        }
        let flags = event?.modifierFlags ?? []
        if flags.contains(.command) {
            if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
            anchorID = item.id
        } else if flags.contains(.shift),
                  let anchorID,
                  let from = items.firstIndex(where: { $0.id == anchorID }),
                  let to = items.firstIndex(where: { $0.id == item.id }) {
            selection = Set(items[min(from, to)...max(from, to)].map(\.id))
        } else {
            selection = [item.id]
            anchorID = item.id
        }
    }

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        if KeyboardFocus.isEditingText { return .ignored }
        if press.key == .space || press.key == .return {
            guard let id = items.first(where: { selection.contains($0.id) })?.id else { return .ignored }
            onOpen(id)
            return .handled
        }
        if press.key == .delete || press.key == .deleteForward || press.characters == "\u{7F}" {
            guard !selection.isEmpty else { return .ignored }
            if scope == .trash {
                onRequestDelete(Array(selection))
            } else {
                store.moveToTrash(Array(selection))
                selection = []
            }
            return .handled
        }
        if press.key == .leftArrow || press.key == .rightArrow {
            step(press.key == .leftArrow ? -1 : 1)
            return .handled
        }
        if press.modifiers.contains(.command), press.characters == "a" {
            selection = Set(items.map(\.id))
            return .handled
        }
        return .ignored
    }

    private func step(_ delta: Int) {
        guard !items.isEmpty else { return }
        let current = anchorID.flatMap { id in items.firstIndex { $0.id == id } }
        let next = current.map { min(max($0 + delta, 0), items.count - 1) } ?? 0
        selection = [items[next].id]
        anchorID = items[next].id
    }
}

/// 把素材摆到 rect 的位置。rect 由它自己插值：动画的每一帧都按中间的大小重新排里面的内容，
/// 动画不会传进格子里面。否则文件名每帧被截成不同长度，系统会给它做淡入淡出，名字就和缩略图分开了
private struct PlacedCell<Content: View>: View, Animatable {
    var rect: CGRect
    /// 点击、拖动、右键都放在里面，在 offset 之前，点击区域才跟着格子走
    @ViewBuilder let content: (CGSize) -> Content

    var animatableData: CGRect.AnimatableData {
        get { rect.animatableData }
        set { rect.animatableData = newValue }
    }

    var body: some View {
        content(rect.size)
            .offset(x: rect.minX, y: rect.minY)
    }
}

private struct MasonryScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct GridCell: View {
    static let captionHeight: CGFloat = 38

    /// 缩略图加下面两行文字的总高度
    static func height(for item: Item, width: CGFloat) -> CGFloat {
        (width / item.displayAspect).rounded() + captionHeight
    }

    let item: Item
    let thumbnailURL: URL?
    let width: CGFloat
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ThumbnailView(url: thumbnailURL, rev: item.thumbRev, kind: item.kind)
                .frame(width: width, height: (width / item.displayAspect).rounded())
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08))
                }
                .overlay(alignment: .bottomTrailing) {
                    if item.kind == .video, let duration = item.duration {
                        VideoBadge(duration: duration).padding(6)
                    }
                }
                .overlay {
                    if selected {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Color.accentColor, lineWidth: 3)
                            .padding(-4)
                    }
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    // 截断长度变了直接换，不做文字的淡入淡出
                    .contentTransition(.identity)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .foregroundStyle(selected ? Color.white : Color.primary)
                    .background(selected ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 4))
                Text(item.metaLine)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 5)
            }
        }
    }
}

struct ItemMenu: View {
    let store: LibraryStore
    let ids: [String]
    let scope: SidebarItem
    var onOpen: () -> Void
    var onRequestDelete: ([String]) -> Void

    var body: some View {
        let urls = ids.compactMap { store.item($0) }.map { store.fileURL(for: $0) }
        if scope == .trash {
            Button("恢复") { store.restore(ids) }
            Button("永久删除…", role: .destructive) { onRequestDelete(ids) }
        } else {
            if ids.count == 1 {
                Button("预览") { onOpen() }
            }
            Button("用默认应用打开") { urls.forEach(ItemActions.open) }
            Button("在访达中显示") { ItemActions.reveal(urls) }
            Button("拷贝") { ItemActions.copyFiles(urls) }
            Divider()
            Menu("添加到文件夹") {
                if store.folders.isEmpty {
                    Text("还没有文件夹")
                }
                ForEach(store.folderOutline(), id: \.folder.id) { entry in
                    Button(String(repeating: "    ", count: entry.depth) + entry.folder.name) {
                        store.addToFolder(ids, entry.folder.id)
                    }
                }
            }
            if case .folder(let folderID) = scope {
                Button("从当前文件夹移除") { store.removeFromFolder(ids, folderID) }
            }
            Menu("评分") {
                ForEach(0...5, id: \.self) { value in
                    Button(value == 0 ? "清除评分" : String(repeating: "★", count: value)) {
                        store.setRating(ids, value)
                    }
                }
            }
            Divider()
            Button("移到废纸篓") { store.moveToTrash(ids) }
        }
    }
}
