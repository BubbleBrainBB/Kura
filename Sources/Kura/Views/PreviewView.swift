import AVKit
import Quartz
import SwiftUI

/// 预览：和网格同一块底色、同一种标题（「全部素材 9 / 40」），返回、打开、上一个和下一个在窗口工具栏里；
/// 视频的播放控制在底部控制条上
struct PreviewView: View {
    @ObservedObject var store: LibraryStore
    /// 从哪个范围点进来的，标题和网格保持一致
    let scopeTitle: String
    let items: [Item]
    let item: Item
    var onClose: () -> Void
    var onSelect: (String) -> Void
    /// 工具栏右边给信息面板留出的宽度，按钮不压在面板上
    var trailingGap: CGFloat = 0
    @FocusState private var focused: Bool
    /// 视频播放状态，控制条和快捷键共用
    @StateObject private var playback = PlaybackController()

    private var index: Int { items.firstIndex { $0.id == item.id } ?? 0 }

    var body: some View {
        PreviewContent(store: store, item: item, playback: playback)
            .id(item.id)
            // 和网格一样留出边距，不贴着工具栏和窗口边
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            .padding(.top, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(scopeTitle)
            .modifier(CountedTitle(title: scopeTitle, count: "\(index + 1) / \(items.count)"))
            .toolbar { toolbar }
            .focusable()
            .focusEffectDisabled()
            .focused($focused)
            .onKeyPress(phases: .down) { press in
                if KeyboardFocus.isEditingText { return .ignored }
                switch press.key {
                case .escape:
                    onClose()
                    return .handled
                case .leftArrow:
                    step(-1)
                    return .handled
                case .rightArrow:
                    step(1)
                    return .handled
                case .space where item.kind == .video:
                    playback.togglePlay()
                    return .handled
                default:
                    return handleCharacter(press.characters)
                }
            }
            .onAppear {
                claimFocus()
                store.markViewed(item.id)
            }
            .onChange(of: item.id) { _, id in
                claimFocus()
                store.markViewed(id)
            }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button(action: onClose) {
                Label {
                    Text("返回资源库")
                } icon: {
                    GlyphIcon(.chevronLeft)
                }
            }
            .help("返回资源库（Esc）")
        }
        FlexibleToolbarSpace()
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                ItemActions.open(store.fileURL(for: item))
            } label: {
                Label {
                    Text("用默认应用打开")
                } icon: {
                    GlyphIcon(.external)
                }
            }
            .help("用默认应用打开")
            Button {
                ItemActions.reveal([store.fileURL(for: item)])
            } label: {
                Label {
                    Text("在访达中显示")
                } icon: {
                    GlyphIcon(.folder)
                }
            }
            .help("在访达中显示")
            Button { step(-1) } label: {
                Label {
                    Text("上一个")
                } icon: {
                    GlyphIcon(.chevronLeft)
                }
            }
            .help("上一个（←）")
            .disabled(index == 0)
            Button { step(1) } label: {
                Label {
                    Text("下一个")
                } icon: {
                    GlyphIcon(.chevronRight)
                }
            }
            .help("下一个（→）")
            .disabled(index >= items.count - 1)
        }
        if trailingGap > 0 {
            PlainToolbarItem(placement: .primaryAction) {
                Color.clear
                    .frame(width: trailingGap, height: 1)
                    .accessibilityHidden(true)
            }
        }
    }

    /// 逗号、句号逐帧（剪辑软件的通行做法），L 循环，M 静音，F 全屏
    private func handleCharacter(_ characters: String) -> KeyPress.Result {
        switch characters.lowercased() {
        case "f":
            NSApp.keyWindow?.toggleFullScreen(nil)
        case "," where item.kind == .video:
            playback.step(-1)
        case "." where item.kind == .video:
            playback.step(1)
        case "l" where item.kind == .video:
            playback.loops.toggle()
        case "m" where item.kind == .video:
            playback.isMuted.toggle()
        default:
            return .ignored
        }
        return .handled
    }

    /// 网格被换掉时，系统会把焦点挪到信息面板的名称输入框（还全选了文字），
    /// ← → 和空格就成了打字。等这一轮界面更新完再把焦点要回来
    private func claimFocus() {
        Task { @MainActor in
            focused = true
        }
    }

    private func step(_ delta: Int) {
        let next = index + delta
        guard items.indices.contains(next) else { return }
        onSelect(items[next].id)
    }
}

/// 按类型选择预览方式：图片可缩放、视频用系统播放器、其余交给 Quick Look
struct PreviewContent: View {
    let store: LibraryStore
    let item: Item
    @ObservedObject var playback: PlaybackController
    @State private var imageFailed = false

    var body: some View {
        let url = store.fileURL(for: item)
        switch item.kind {
        case .image where !imageFailed:
            ZoomableImage(url: url) { imageFailed = true }
        case .video:
            VideoPreview(store: store, item: item, playback: playback)
        default:
            QuickLookPreview(url: url)
        }
    }
}

// MARK: - 图片

struct ZoomableImage: NSViewRepresentable {
    let url: URL
    var onFailure: () -> Void

    func makeNSView(context: Context) -> ImageScrollView {
        ImageScrollView()
    }

    func updateNSView(_ view: ImageScrollView, context: Context) {
        if view.loadedURL != url {
            view.load(url, onFailure: onFailure)
        }
    }
}

/// 双指缩放、双击在“适合窗口”和 100% 之间切换；GIF 会动
final class ImageScrollView: NSScrollView {
    private let imageView = ClickableImageView()
    private(set) var loadedURL: URL?
    private var fitsToView = true

    init() {
        super.init(frame: .zero)
        contentView = CenteringClipView()
        drawsBackground = false
        contentView.drawsBackground = false
        hasHorizontalScroller = true
        hasVerticalScroller = true
        autohidesScrollers = true
        scrollerStyle = .overlay
        allowsMagnification = true
        maxMagnification = 16
        minMagnification = 0.02
        imageView.imageScaling = .scaleAxesIndependently
        imageView.animates = true
        imageView.onDoubleClick = { [weak self] point in self?.toggleZoom(at: point) }
        documentView = imageView
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func load(_ url: URL, onFailure: @escaping () -> Void) {
        loadedURL = url
        imageView.image = nil
        Task { @MainActor in
            let image = await Task.detached { Self.previewImage(url) }.value
            guard self.loadedURL == url else { return }
            guard let image, image.size.width > 0, image.size.height > 0 else {
                onFailure()
                return
            }
            imageView.image = image
            imageView.frame = NSRect(origin: .zero, size: image.size)
            fitsToView = true
            fit()
        }
    }

    /// SVG 常写成 width="1em"，直接读只有 1×1 点。按 viewBox 读出比例，再放大到适合预览的尺寸（矢量放大不会糊）
    nonisolated static func previewImage(_ url: URL) -> NSImage? {
        guard url.pathExtension.lowercased() == "svg",
              let text = try? String(contentsOf: url, encoding: .utf8),
              let image = NSImage(data: Data(SVGIcon.normalized(text).utf8)) else {
            return NSImage(contentsOf: url)
        }
        let longest = max(image.size.width, image.size.height)
        if longest > 0, longest < 1024 {
            let scale = 1024 / longest
            image.size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        }
        return image
    }

    override func layout() {
        super.layout()
        if fitsToView { fit() }
    }

    override func magnify(with event: NSEvent) {
        fitsToView = false
        super.magnify(with: event)
    }

    private func fit() {
        guard let size = imageView.image?.size, size.width > 0, size.height > 0, bounds.width > 0, bounds.height > 0 else { return }
        let scale = min(1, min(bounds.width / size.width, bounds.height / size.height))
        minMagnification = min(scale, 0.1)
        if abs(magnification - scale) > 0.001 { magnification = scale }
    }

    private func toggleZoom(at point: NSPoint) {
        if fitsToView, magnification < 0.999 {
            fitsToView = false
            setMagnification(1, centeredAt: point)
        } else {
            fitsToView = true
            fit()
        }
    }
}

final class ClickableImageView: NSImageView {
    var onDoubleClick: ((NSPoint) -> Void)?

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleClick?(convert(event.locationInWindow, from: nil))
        } else {
            super.mouseDown(with: event)
        }
    }
}

/// 图片比视口小时居中显示
final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let documentView else { return rect }
        if rect.width > documentView.frame.width {
            rect.origin.x = (documentView.frame.width - rect.width) / 2
        }
        if rect.height > documentView.frame.height {
            rect.origin.y = (documentView.frame.height - rect.height) / 2
        }
        return rect
    }
}

// MARK: - 视频

struct VideoPreview: View {
    let store: LibraryStore
    let item: Item
    @ObservedObject var playback: PlaybackController
    @State private var playable: Bool?
    @State private var savingCover = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if playable == false {
                    UnsupportedVideoView(item: item, fileURL: store.fileURL(for: item))
                } else if let player = playback.player {
                    PlayerLayerView(player: player)
                        .contentShape(Rectangle())
                        .onTapGesture { playback.togglePlay() }
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if playable == true {
                VideoControlBar(
                    playback: playback,
                    coverTime: item.effectiveCoverTime,
                    savingCover: savingCover,
                    onSetCover: setCover
                )
            }
        }
        .task(id: item.id) {
            let asset = AVURLAsset(url: store.fileURL(for: item))
            let ok = (try? await asset.load(.isPlayable)) ?? false
            playable = ok
            guard ok else { return }
            let seconds = (try? await asset.load(.duration))?.seconds ?? item.duration ?? 0
            playback.load(asset, duration: seconds.isFinite ? seconds : 0, id: item.id)
        }
        .onDisappear {
            playback.unload(id: item.id)
        }
    }

    private func setCover() {
        let seconds = playback.currentTime
        savingCover = true
        Task {
            await store.setCover(item.id, seconds: seconds)
            savingCover = false
        }
    }
}

struct UnsupportedVideoView: View {
    let item: Item
    let fileURL: URL

    var body: some View {
        VStack(spacing: 12) {
            GlyphIcon(.video, size: 44, lineWidth: 1.25)
                .foregroundStyle(.secondary)
            Text("系统播放器不支持 .\(item.ext) 格式")
                .font(.system(size: 15, weight: .semibold))
            Text("这一版只用 macOS 自带的解码器，能播放 MP4、MOV、M4V 等。\nMKV、WebM、FLV、AVI 计划在接入 libmpv 后支持。")
                .font(.system(size: 12))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("用其他应用打开") { ItemActions.open(fileURL) }
                .padding(.top, 4)
        }
        .padding(40)
    }
}

// MARK: - 其他格式

struct QuickLookPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal)!
        view.autostarts = true
        view.previewItem = url as NSURL
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        if (view.previewItem as? NSURL) as URL? != url {
            view.previewItem = url as NSURL
        }
    }
}
