import AppKit
import SwiftUI

// 信息面板用的小部件：平时是看得舒服的卡片，点了才变成可编辑的样子

extension View {
    /// 白底、细边的卡片（备注、来源、信息都用这一种）
    func inspectorCard(cornerRadius: CGFloat = 8) -> some View {
        background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
            )
    }

    /// 正在编辑时的强调色描边和外圈
    func editingRing(_ active: Bool, cornerRadius: CGFloat = 8) -> some View {
        overlay {
            if active {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 1)
                    .background(
                        RoundedRectangle(cornerRadius: cornerRadius + 2, style: .continuous)
                            .stroke(Color.accentColor.opacity(0.25), lineWidth: 3)
                            .padding(-1.5)
                    )
                    .allowsHitTesting(false)
            }
        }
    }
}

/// 分区：上面一条细线，标题在左，右边可以放一个小操作
struct InspectorSection<Content: View, Accessory: View>: View {
    let title: String
    @ViewBuilder var content: Content
    @ViewBuilder var accessory: Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    accessory
                }
                .frame(height: 14)
                content
            }
            .padding(.vertical, 14)
        }
    }
}

extension InspectorSection where Accessory == EmptyView {
    init(title: String, @ViewBuilder content: () -> Content) {
        self.init(title: title, content: content, accessory: { EmptyView() })
    }
}

/// 分区标题右边的文字按钮：「编辑」「完成」
struct SectionAction: View {
    let title: String
    var action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(Color.accentColor)
    }
}

// MARK: - 预览图

/// 素材预览。鼠标移上去在右下角出现「打开」和「在访达中显示」；双击用默认应用打开
struct ItemPreview: View {
    let store: LibraryStore
    let item: Item
    @State private var hovered = false

    var body: some View {
        let url = store.fileURL(for: item)
        ThumbnailView(url: store.thumbURL(for: item), rev: item.thumbRev, kind: item.kind, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .padding(10)
            .frame(maxWidth: .infinity)
            .frame(height: min(220, max(120, 268 / item.displayAspect)))
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { ItemActions.open(url) }
            .overlay(alignment: .bottomTrailing) {
                if hovered {
                    HStack(spacing: 6) {
                        PreviewButton(help: "用默认应用打开") { ItemActions.open(url) } label: {
                            GlyphIcon(.external, size: 13)
                            Text("打开")
                        }
                        PreviewButton(help: "在访达中显示") { ItemActions.reveal([url]) } label: {
                            GlyphIcon(.folder, size: 13)
                        }
                    }
                    .padding(8)
                    .transition(.opacity)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if item.kind == .video, let duration = item.duration {
                    VideoBadge(duration: duration).padding(8)
                }
            }
            .onHover { inside in
                withAnimation(.easeOut(duration: 0.15)) { hovered = inside }
            }
    }
}

private struct PreviewButton<Label: View>: View {
    let help: String
    var action: () -> Void
    @ViewBuilder var label: Label

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) { label }
                .font(.system(size: 11.5))
                .padding(.horizontal, 8)
                .frame(minWidth: 26, minHeight: 26)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

// MARK: - 颜色

/// 一条色带。悬停的那一格加白框，色值显示在分区标题右边；点击拷贝
struct PaletteStrip: View {
    let colors: [String]
    @Binding var hovered: String?
    @Binding var copied: String?

    var body: some View {
        HStack(spacing: 0) {
            ForEach(colors, id: \.self) { hex in
                Rectangle()
                    .fill(Color(hex: hex))
                    .overlay {
                        if hovered == hex {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .strokeBorder(.white, lineWidth: 2)
                                .shadow(color: .black.opacity(0.3), radius: 1)
                                .padding(2)
                        }
                    }
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside { hovered = hex } else if hovered == hex { hovered = nil }
                    }
                    .onTapGesture {
                        ItemActions.copyText(hex)
                        copied = hex
                    }
            }
        }
        .frame(height: 24)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
    }
}

// MARK: - 小卡片（标签、文件夹）

struct InspectorChip<Mark: View>: View {
    let title: String
    @ViewBuilder var mark: Mark
    var onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 5) {
            mark
            Text(title)
                .font(.system(size: 12))
                .lineLimit(1)
            if let onRemove {
                Button(action: onRemove) {
                    GlyphIcon(.close, size: 9, lineWidth: 1.75)
                        .frame(width: 14, height: 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .help("移除")
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, onRemove == nil ? 8 : 4)
        .frame(height: 24)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.04), radius: 0.5, y: 0.5)
    }
}

/// 虚线框的「+ 标签」「+ 文件夹」
struct AddChip: View {
    let title: String
    var action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                GlyphIcon(.plus, size: 11, lineWidth: 1.75)
                Text(title).font(.system(size: 12))
            }
            .padding(.leading, 6)
            .padding(.trailing, 8)
            .frame(height: 24)
            .foregroundStyle(hovered ? .secondary : .tertiary)
            .background(hovered ? Color.primary.opacity(0.05) : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

// MARK: - 标签

/// 已有标签是小卡片，后面一个「+ 标签」；点它原地变成输入框，下面列出匹配的标签和子标签路径。
/// ↑ ↓ 选，回车加上，Esc 收起。输入「上级/名称」直接建成子标签
struct TagEditor: View {
    let store: LibraryStore
    let tags: [String]
    /// 收到的可能是「上级/名称」这样的路径，交给 store.addTagPath 处理
    var onAdd: (String) -> Void
    var onRemove: (String) -> Void
    @State private var editing = false
    @State private var draft = ""
    @State private var highlighted = 0
    @FocusState private var focused: Bool

    private enum Option: Hashable {
        case existing(String)
        case create(String)
    }

    var body: some View {
        let query = draft.trimmingCharacters(in: .whitespaces)
        let options = options(for: query)
        VStack(alignment: .leading, spacing: 6) {
            FlowLayout {
                ForEach(tags, id: \.self) { tag in
                    InspectorChip(title: tag, mark: { TagMark(store: store, tag: tag, size: 13).foregroundStyle(.secondary) }) {
                        onRemove(tag)
                    }
                    .help(store.tagPath(tag))
                }
                if editing {
                    input(options)
                } else {
                    AddChip(title: tags.isEmpty ? "添加标签" : "标签") { startEditing() }
                }
            }
            if editing, !query.isEmpty {
                suggestions(options)
                if !query.contains("/") {
                    Text("输入「上级/名称」可以直接建成子标签")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .onChange(of: draft) { _, _ in highlighted = 0 }
    }

    private func input(_ options: [Option]) -> some View {
        TextField("标签名", text: $draft)
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .focused($focused)
            .onSubmit { choose(options.indices.contains(highlighted) ? options[highlighted] : nil) }
            .onExitCommand(perform: stopEditing)
            .onKeyPress(.downArrow) {
                highlighted = min(highlighted + 1, max(options.count - 1, 0))
                return .handled
            }
            .onKeyPress(.upArrow) {
                highlighted = max(highlighted - 1, 0)
                return .handled
            }
            .padding(.horizontal, 8)
            .frame(width: 120, height: 24)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .editingRing(true, cornerRadius: 6)
            .onChange(of: focused) { _, isFocused in
                guard !isFocused else { return }
                // 点下拉里的选项时输入框会先失去焦点，等这一下点击处理完再决定收不收起
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    if !focused { stopEditing() }
                }
            }
    }

    private func suggestions(_ options: [Option]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.element) { index, option in
                SuggestionRow(highlighted: index == highlighted, action: { choose(option) }) {
                    switch option {
                    case .existing(let tag):
                        TagMark(store: store, tag: tag, size: 13)
                        let parents = store.ancestors(of: tag)
                        (parents.isEmpty ? Text("") : Text(parents.joined(separator: " › ") + " › ").foregroundStyle(.secondary))
                            + Text(tag)
                    case .create(let name):
                        GlyphIcon(.plus, size: 13, lineWidth: 1.75)
                        Text("新建标签「\(name)」")
                    }
                }
                .onHover { if $0 { highlighted = index } }
            }
        }
        .padding(4)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.1), radius: 10, y: 4)
    }

    /// 按名字匹配已有的标签，上级匹配上的子标签也列出来（输 Moon 能看到 Moonshot › Kimi）；
    /// 没有同名的就在最后给「新建」
    private func options(for query: String) -> [Option] {
        guard !query.isEmpty else { return [] }
        let all = store.allTags.filter { !tags.contains($0) }
        let direct = all.filter { $0.localizedCaseInsensitiveContains(query) }
        let viaParent = all.filter { tag in
            !direct.contains(tag) && store.ancestors(of: tag).contains { $0.localizedCaseInsensitiveContains(query) }
        }
        var options = (direct + viaParent).prefix(8).map(Option.existing)
        if !store.allTags.contains(where: { $0.caseInsensitiveCompare(query) == .orderedSame }) {
            let name = query.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " › ")
            options.append(.create(name))
        }
        return options
    }

    private func startEditing() {
        draft = ""
        editing = true
        DispatchQueue.main.async { focused = true }
    }

    private func stopEditing() {
        editing = false
        draft = ""
        focused = false
    }

    /// 选了已有标签就加它；新建或直接回车时，支持用逗号一次输入多个，和已有标签只差大小写时用已有的写法
    private func choose(_ option: Option?) {
        if case .existing(let tag) = option {
            onAdd(tag)
        } else {
            let all = store.allTags
            let parts = draft.split(whereSeparator: { $0 == "," || $0 == "，" })
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            for part in parts {
                onAdd(all.first { $0.caseInsensitiveCompare(part) == .orderedSame } ?? part)
            }
        }
        draft = ""
        // 接着输下一个
        DispatchQueue.main.async { focused = true }
    }
}

private struct SuggestionRow<Label: View>: View {
    let highlighted: Bool
    var action: () -> Void
    @ViewBuilder var label: Label

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) { label }
                .font(.system(size: 12))
                .lineLimit(1)
                .foregroundStyle(highlighted ? Color.white : Color.primary)
                .padding(.horizontal, 7)
                .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
                .background(highlighted ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 文件夹

/// 「+ 文件夹」：弹出所有文件夹，已经在里面的打勾，再点一下就移出
struct AddToFolderChip: View {
    let store: LibraryStore
    let ids: [String]
    var title = "文件夹"

    var body: some View {
        AddChip(title: title, action: showMenu)
    }

    private func showMenu() {
        let menu = NSMenu()
        let outline = store.folderOutline()
        if outline.isEmpty {
            let empty = NSMenuItem(title: "还没有文件夹", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        for entry in outline {
            let id = entry.folder.id
            let inside = !ids.isEmpty && ids.allSatisfy { store.item($0)?.folderIDs.contains(id) == true }
            let item = ClosureMenuItem(title: entry.folder.name) {
                if inside { store.removeFromFolder(ids, id) } else { store.addToFolder(ids, id) }
            }
            item.indentationLevel = entry.depth
            item.state = inside ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}

final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func run() {
        handler()
    }
}

// MARK: - 备注

/// 备注卡片：全文显示，行距放宽，点进去直接编辑，回车换行，Esc 或点别处结束。
/// 自己包一个 NSTextView 而不用 TextEditor：TextEditor 带滚动视图，在面板的 ScrollView 里点击区域会盖住上面的输入框
struct NoteEditor: View {
    @Binding var text: String
    @State private var focused = false

    var body: some View {
        let ghost = text.isEmpty && !focused
        GrowingTextView(text: $text, focused: $focused)
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    HStack(spacing: 7) {
                        if !focused { GlyphIcon(.note, size: 14) }
                        Text("添加备注…")
                    }
                    .font(.system(size: 12.5))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, GrowingTextView.inset.width)
                    .padding(.top, GrowingTextView.inset.height - 1)
                    .allowsHitTesting(false)
                }
            }
            .background {
                if !ghost {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(nsColor: .controlBackgroundColor))
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(ghost ? 0.12 : 0.1), lineWidth: ghost ? 1 : 0.5)
            )
            .editingRing(focused)
    }
}

struct GrowingTextView: NSViewRepresentable {
    static let inset = NSSize(width: 11, height: 9)
    static let font = NSFont.systemFont(ofSize: 12.5)

    @Binding var text: String
    @Binding var focused: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NoteTextView {
        let view = NoteTextView(usingTextLayoutManager: false)
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 4
        view.delegate = context.coordinator
        view.onFocusChange = { focused in context.coordinator.parent.focused = focused }
        view.isRichText = false
        view.importsGraphics = false
        view.allowsUndo = true
        view.drawsBackground = false
        view.isVerticallyResizable = false
        view.isHorizontallyResizable = false
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.textContainerInset = Self.inset
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = true
        view.font = Self.font
        view.defaultParagraphStyle = style
        view.typingAttributes = [.font: Self.font, .paragraphStyle: style, .foregroundColor: NSColor.labelColor]
        view.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: view.typingAttributes))
        return view
    }

    func updateNSView(_ view: NoteTextView, context: Context) {
        context.coordinator.parent = self
        if view.string != text {
            view.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: view.typingAttributes))
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NoteTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 268
        guard let container = nsView.textContainer, let manager = nsView.layoutManager else { return nil }
        container.containerSize = NSSize(width: max(0, width - Self.inset.width * 2), height: .greatestFiniteMagnitude)
        manager.ensureLayout(for: container)
        let used = manager.usedRect(for: container).height
        let line = manager.defaultLineHeight(for: Self.font)
        return CGSize(width: width, height: ceil(max(used, line) + Self.inset.height * 2))
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: GrowingTextView

        init(_ parent: GrowingTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.text = view.string
        }
    }
}

final class NoteTextView: NSTextView {
    var onFocusChange: ((Bool) -> Void)?

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onFocusChange?(true) }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted { onFocusChange?(false) }
        return accepted
    }

    override func cancelOperation(_ sender: Any?) {
        window?.makeFirstResponder(nil)
    }
}

// MARK: - 来源

/// 来源链接：网站图标跟着一行「域名/路径」，像浏览器标签页。域名用正文色、路径用灰色，太长从中间省略；
/// 鼠标移上去才出现底色和箭头，点了在浏览器打开
struct SourceLinkCard: View {
    let text: String
    @State private var hovered = false

    var body: some View {
        if let url = URL(string: text), url.scheme?.hasPrefix("http") == true, let host = url.host() {
            let site = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            let path = Self.path(of: url)
            Link(destination: url) {
                HStack(spacing: 8) {
                    SiteIcon(host: host, site: site)
                    (Text(site).foregroundStyle(.primary) + Text(path.isEmpty ? "" : "/" + path).foregroundStyle(.secondary))
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                    GlyphIcon(.external, size: 13)
                        .foregroundStyle(.secondary)
                        .opacity(hovered ? 1 : 0)
                }
                .padding(.horizontal, 6)
                .frame(height: 28)
                .background(hovered ? Color.primary.opacity(0.05) : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .padding(.horizontal, -6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovered = $0 }
            .help(text)
        } else {
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .textSelection(.enabled)
        }
    }

    /// 只显示路径，?s=20 这类分享参数不显示（悬停提示里有完整链接）
    private static func path(of url: URL) -> String {
        url.path().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

/// 网站自己的 favicon；还在取时是灰色方块，取不到用首字母
private struct SiteIcon: View {
    let host: String
    let site: String
    @State private var image: NSImage?
    @State private var failed = false

    init(host: String, site: String) {
        self.host = host
        self.site = site
        _image = State(initialValue: Favicons.cached(host))
    }

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else if failed {
                Palette.tag(site)
                Text(String(site.prefix(1)).uppercased())
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                Color.primary.opacity(0.08)
            }
        }
        .frame(width: 16, height: 16)
        .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
        .task(id: host) {
            guard image == nil else { return }
            image = await Favicons.image(for: host)
            failed = image == nil
        }
    }
}

/// 没有内容时的一行：虚一点的边框、灰色图标和提示
struct GhostRow: View {
    let glyph: Glyph
    let title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                GlyphIcon(glyph, size: 14)
                Text(title).font(.system(size: 12.5))
            }
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 11)
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 信息

/// 名称在左、数值靠右，细线分隔
struct InfoCard: View {
    let rows: [(String, String)]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 { Divider() }
                HStack(spacing: 12) {
                    Text(row.0).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Text(row.1)
                        .monospacedDigit()
                        .lineLimit(1)
                        .textSelection(.enabled)
                }
                .font(.system(size: 12))
                .frame(height: 30)
            }
        }
        .padding(.horizontal, 10)
        .inspectorCard()
    }
}
