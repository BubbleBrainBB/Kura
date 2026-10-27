import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject private var app: AppModel
    @State private var selectedRecent: String?
    @State private var dropTargeted = false

    var body: some View {
        HStack(spacing: 0) {
            leftPane
                .frame(width: 320)
            Divider()
            rightPane
        }
        .frame(minWidth: 820, minHeight: 540)
    }

    private var leftPane: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                AppIconView(size: 84)
                Text("Kura")
                    .font(.system(size: 26, weight: .bold))
                    .padding(.top, 6)
                Text("版本 \(Bundle.main.shortVersion)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 36)

            VStack(spacing: 8) {
                WelcomeButton(title: "新建资源库…", glyph: .plus, prominent: true) {
                    app.showNewLibraryPanel()
                }
                WelcomeButton(title: "打开已有资源库…", glyph: .folder) {
                    app.showOpenLibraryPanel()
                }
                WelcomeButton(title: "从 Eagle 导入…", subtitle: "读取 .library，不会修改原资源库", glyph: .importFile) {
                    app.showEagleImportPanel()
                }
            }
            .padding(.top, 36)

            Spacer()

            Text("素材全部保存在本机。把资源库放进 iCloud Drive、Dropbox 或 NAS，就能在多台 Mac 之间同步。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 24)
        .frame(maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var rightPane: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("最近打开").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("双击打开 · 右键查看更多")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            if app.recents.isEmpty {
                Text("还没有打开过资源库。新建一个，或者把文件夹拖到下面。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(app.recents) { recent in
                            RecentRow(recent: recent, selected: selectedRecent == recent.id)
                                .onTapGesture {
                                    if NSApp.currentEvent?.clickCount == 2, recent.isAvailable {
                                        app.open(recent.url)
                                    } else {
                                        selectedRecent = recent.id
                                    }
                                }
                                .contextMenu {
                                    Button("打开") { app.open(recent.url) }
                                        .disabled(!recent.isAvailable)
                                    Button("在访达中显示") { ItemActions.reveal([recent.url]) }
                                        .disabled(!recent.isAvailable)
                                    Divider()
                                    Button("从列表中移除") { app.forget(recent) }
                                }
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            VStack(spacing: 6) {
                GlyphIcon(.importFile, size: 22)
                Text("把 Eagle 资源库（.library）或任意文件夹拖到这里导入")
                    .font(.system(size: 12))
            }
            .foregroundStyle(dropTargeted ? Color.accentColor : Color.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 92)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(dropTargeted ? Color.accentColor : Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .background(dropTargeted ? Color.accentColor.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 12))
            }
            .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
                DropHelper.fileURLs(from: providers) { app.handleDrop($0) }
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 28)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

struct WelcomeButton: View {
    let title: String
    var subtitle: String?
    let glyph: Glyph
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                GlyphIcon(glyph)
                    .frame(width: 18)
                    .foregroundStyle(prominent ? Color.white : Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: prominent ? .semibold : .regular))
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(prominent ? Color.white.opacity(0.8) : Color.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, subtitle == nil ? 11 : 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(prominent ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(prominent ? Color.clear : Color.primary.opacity(0.12))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct RecentRow: View {
    let recent: RecentLibrary
    let selected: Bool

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(recent.isAvailable ? Color.accentColor : Color.secondary.opacity(0.25))
                .frame(width: 40, height: 40)
                .overlay {
                    GlyphIcon(.library, size: 20)
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(recent.name).font(.system(size: 13, weight: .semibold))
                Text(recent.displayPath)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(recent.itemCount) 个素材 · \(Format.bytes(recent.byteSize))")
                status
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(selected ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var status: some View {
        if !recent.isAvailable {
            Label {
                Text("磁盘未连接")
            } icon: {
                GlyphIcon(.warning, size: 12)
            }
                .foregroundStyle(.orange)
        } else if recent.isInICloud {
            Text("iCloud Drive · \(recent.lastOpened.formatted(.relative(presentation: .named)))")
        } else {
            Text("本机 · \(recent.lastOpened.formatted(.relative(presentation: .named)))")
        }
    }
}
