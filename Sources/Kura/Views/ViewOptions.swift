import SwiftUI

/// 缩略图大小：工具栏「视图」里的滑条、⌘+ / ⌘− 和触控板捏合共用
enum ThumbnailSize {
    static let key = "thumbnailSize"
    static let range: ClosedRange<Double> = 120...420
    static let standard = 200.0
    private static let step = 40.0

    static func clamped(_ size: Double) -> Double {
        min(max(size, range.lowerBound), range.upperBound)
    }

    /// 菜单命令用：直接改 UserDefaults，网格那边的 @AppStorage 会跟着变
    static func adjust(by direction: Double) {
        let defaults = UserDefaults.standard
        let current = defaults.object(forKey: key) as? Double ?? standard
        defaults.set(clamped(current + direction * step), forKey: key)
    }
}

extension SortKey {
    /// 排序方向按字段说人话，不说「升序 / 降序」
    var descendingLabel: String {
        switch self {
        case .added, .modified: "新的在前"
        case .name: "Z 到 A"
        case .size: "大的在前"
        case .rating: "高的在前"
        }
    }

    var ascendingLabel: String {
        switch self {
        case .added, .modified: "旧的在前"
        case .name: "A 到 Z"
        case .size: "小的在前"
        case .rating: "低的在前"
        }
    }
}

/// 工具栏「视图」弹出的面板：类型、排序、缩略图大小
struct ViewOptionsPanel: View {
    @Binding var kind: KindFilter
    @Binding var sortKey: SortKey
    @Binding var ascending: Bool
    @Binding var thumbnailSize: Double

    static func isCustomized(kind: KindFilter, sortKey: SortKey, ascending: Bool) -> Bool {
        kind != .all || sortKey != .added || ascending
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            section("类型") {
                Picker("类型", selection: $kind) {
                    ForEach(KindFilter.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            section("排序") {
                VStack(spacing: 1) {
                    ForEach(SortKey.allCases) { key in
                        OptionRow(title: key.title, checked: key == sortKey) { sortKey = key }
                    }
                }
                Picker("顺序", selection: $ascending) {
                    Text(sortKey.descendingLabel).tag(false)
                    Text(sortKey.ascendingLabel).tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.top, 4)
            }

            section("缩略图大小") {
                HStack(spacing: 8) {
                    GlyphIcon(.thumbSmall, size: 13)
                    Slider(value: $thumbnailSize, in: ThumbnailSize.range)
                    GlyphIcon(.thumbLarge, size: 15)
                }
                .foregroundStyle(.secondary)
                Text("也可以用 ⌘+ / ⌘− 或触控板捏合")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            Divider()

            Button("恢复默认") {
                kind = .all
                sortKey = .added
                ascending = false
                thumbnailSize = ThumbnailSize.standard
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .font(.system(size: 12))
            .disabled(!Self.isCustomized(kind: kind, sortKey: sortKey, ascending: ascending) && thumbnailSize == ThumbnailSize.standard)
        }
        .padding(14)
        .frame(width: 250)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }
}

private struct OptionRow: View {
    let title: String
    let checked: Bool
    var action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(checked ? "✓" : "")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 12)
                Text(title)
                Spacer(minLength: 0)
            }
            .font(.system(size: 12))
            .padding(.horizontal, 6)
            .frame(height: 24)
            .background(
                checked ? Color.accentColor.opacity(0.12) : hovered ? Color.primary.opacity(0.06) : .clear,
                in: RoundedRectangle(cornerRadius: 5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

extension Notification.Name {
    /// 「编辑 › 搜索素材」⌘F：把光标放进工具栏的搜索框
    static let kuraFocusSearch = Notification.Name("KuraFocusSearch")
}

/// 工具栏里的搜索框。不用 .searchable：系统搜索框总排在工具栏最右端，会伸到信息面板上方
struct ToolbarSearchField: View {
    @Binding var text: String
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 5) {
            GlyphIcon(.search, size: 13)
                .foregroundStyle(.secondary)
            TextField("搜索名称、标签、备注", text: $text)
                .textFieldStyle(.plain)
                .focused($focused)
                .onExitCommand {
                    text = ""
                    focused = false
                }
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    GlyphIcon(.close, size: 10, lineWidth: 1.75)
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("清除搜索")
            }
        }
        .font(.system(size: 12))
        .padding(.horizontal, 8)
        .frame(width: 200, height: 26)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
        .onReceive(NotificationCenter.default.publisher(for: .kuraFocusSearch)) { _ in focused = true }
    }
}

/// 不要系统给工具栏项加的玻璃底（macOS 26 起）
struct PlainToolbarItem<Content: View>: ToolbarContent {
    var placement: ToolbarItemPlacement = .automatic
    @ViewBuilder var content: Content

    var body: some ToolbarContent {
        if #available(macOS 26.0, *) {
            ToolbarItem(placement: placement) { content }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: placement) { content }
        }
    }
}

/// 把后面的工具栏项推到右边（macOS 26 起才有 ToolbarSpacer）
struct FlexibleToolbarSpace: ToolbarContent {
    var body: some ToolbarContent {
        if #available(macOS 26.0, *) {
            ToolbarSpacer(.flexible, placement: .primaryAction)
        }
    }
}

/// 自己画的标题，后面可以跟着灰色的数量：「全部素材 40」。
/// 去掉系统标题后工具栏变矮，网格和预览用同一种，切换时不跳动
struct CountedTitle: ViewModifier {
    let title: String
    var count: String?

    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content
                .toolbar(removing: .title)
                .toolbar {
                    PlainToolbarItem(placement: .navigation) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(title)
                                .font(.system(size: 15, weight: .semibold))
                                .lineLimit(1)
                            if let count {
                                Text(count)
                                    .font(.system(size: 13))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .fixedSize()
                    }
                }
        } else {
            content
        }
    }
}
