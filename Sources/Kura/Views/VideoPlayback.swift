import AVFoundation
import AppKit
import SwiftUI

/// 预览页的视频播放状态：播放、逐帧、倍速、循环、静音、跳转。控制条和快捷键共用一份。
@MainActor
final class PlaybackController: ObservableObject {
    static let speeds: [Float] = [0.5, 1, 1.5, 2]

    @Published private(set) var player: AVPlayer?
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published var speed: Float = 1 {
        didSet {
            player?.defaultRate = speed
            if isPlaying { player?.rate = speed }
        }
    }
    /// 素材多是短片，默认循环
    @Published var loops = true
    @Published var isMuted = false {
        didSet { player?.isMuted = isMuted }
    }
    @Published var volume: Float = 1 {
        didSet { player?.volume = volume }
    }
    /// 拖动进度条期间不让播放进度回写，避免滑块来回跳
    var isScrubbing = false

    private var loadedID: String?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var statusObservation: NSKeyValueObservation?
    private var generator: AVAssetImageGenerator?

    func load(_ asset: AVURLAsset, duration: Double, id: String) {
        unload()
        loadedID = id
        self.duration = duration
        let player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
        player.isMuted = isMuted
        player.volume = volume
        player.defaultRate = speed
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, !self.isScrubbing else { return }
                self.currentTime = time.seconds.isFinite ? time.seconds : 0
            }
        }
        statusObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            let playing = player.timeControlStatus != .paused
            DispatchQueue.main.async { self?.isPlaying = playing }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: player.currentItem, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.loops, let player = self.player else { return }
                player.seek(to: .zero)
                player.rate = self.speed
            }
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 320, height: 320)
        let tolerance = CMTime(seconds: 0.25, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance
        self.generator = generator

        self.player = player
        player.rate = speed
    }

    /// 只卸载自己加载的那个视频：切换素材时，新视频可能先加载、旧视图后消失
    func unload(id: String? = nil) {
        if let id, id != loadedID { return }
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        timeObserver = nil
        endObserver = nil
        statusObservation = nil
        player?.pause()
        player = nil
        generator = nil
        loadedID = nil
        isPlaying = false
        currentTime = 0
        duration = 0
    }

    func togglePlay() {
        guard let player else { return }
        if isPlaying {
            player.pause()
        } else {
            if duration > 0, currentTime >= duration - 0.05 { player.seek(to: .zero) }
            player.rate = speed
        }
    }

    func step(_ frames: Int) {
        guard let player else { return }
        player.pause()
        player.currentItem?.step(byCount: frames)
    }

    func seek(to seconds: Double) {
        guard let player else { return }
        let clamped = min(max(0, seconds), duration)
        currentTime = clamped
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func frameImage(at seconds: Double) async -> CGImage? {
        guard let generator else { return nil }
        return try? await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
    }

    static func label(for speed: Float) -> String {
        speed == speed.rounded() ? String(format: "%.0f×", speed) : String(format: "%.1f×", speed)
    }
}

/// 只负责显示画面的播放层，不带系统控制条
struct PlayerLayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> PlayerLayerNSView {
        let view = PlayerLayerNSView()
        view.playerLayer.player = player
        return view
    }

    func updateNSView(_ view: PlayerLayerNSView, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
    }
}

final class PlayerLayerNSView: NSView {
    let playerLayer = AVPlayerLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        playerLayer.videoGravity = .resizeAspect
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func makeBackingLayer() -> CALayer { playerLayer }
}

// MARK: - 控制条

/// 固定在视频下方、一直显示的控制条，样式见设计稿“预览 · 视频控制条”；浅色、深色跟随系统主题
struct VideoControlBar: View {
    @ObservedObject var playback: PlaybackController
    let coverTime: Double?
    let savingCover: Bool
    var onSetCover: () -> Void
    @State private var showVolume = false

    private static let iconColor = Color(light: "#4A4D55", dark: "#C9CBD1")

    var body: some View {
        HStack(spacing: 6) {
            barButton(playback.isPlaying ? .pause : .play, help: playback.isPlaying ? "暂停（空格）" : "播放（空格）", size: 18, filled: true, bright: true) {
                playback.togglePlay()
            }
            barButton(.stepBack, help: "上一帧（,）", filled: true) { playback.step(-1) }
            barButton(.stepForward, help: "下一帧（.）", filled: true) { playback.step(1) }

            Text(Format.duration(playback.currentTime))
                .foregroundStyle(Color(light: "#18181B", dark: "#F4F4F5"))
                .padding(.leading, 8)
            Text("/ \(Format.duration(playback.duration))")
                .foregroundStyle(Color(light: "#6B6F76", dark: "#8E929A"))

            Scrubber(playback: playback, coverTime: coverTime)
                .padding(.horizontal, 12)

            speedMenu
            barButton(.loop, help: playback.loops ? "关闭循环（L）" : "循环播放（L）", active: playback.loops) {
                playback.loops.toggle()
            }
            HStack(spacing: 2) {
                barButton(playback.isMuted ? .volumeMuted : .volume, help: playback.isMuted ? "取消静音（M）" : "静音（M）") {
                    playback.isMuted.toggle()
                }
                if showVolume {
                    Slider(
                        value: Binding(get: { Double(playback.volume) }, set: { playback.volume = Float($0) }),
                        in: 0...1
                    )
                    .controlSize(.mini)
                    .frame(width: 76)
                }
            }
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.15)) { showVolume = hovering }
            }

            Rectangle()
                .fill(Color(light: "#DCDCE0", dark: "#33343A"))
                .frame(width: 1, height: 18)
                .padding(.horizontal, 4)

            Button(action: onSetCover) {
                HStack(spacing: 6) {
                    GlyphIcon(.image)
                    Text("设为封面")
                }
                .padding(.horizontal, 8)
                .frame(height: 30)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(savingCover)
            .help("把当前帧设为封面")

            barButton(.fullscreen, help: "全屏（F）") {
                NSApp.keyWindow?.toggleFullScreen(nil)
            }
        }
        .font(.system(size: 12).monospacedDigit())
        .foregroundStyle(Self.iconColor)
        .padding(.horizontal, 14)
        .frame(height: 56)
        .background(Color(light: "#F7F7F8", dark: "#1A1B1E"))
        .overlay(alignment: .top) {
            Rectangle().fill(Color(light: "#E2E2E5", dark: "#26272B")).frame(height: 1)
        }
    }

    private var speedMenu: some View {
        Menu {
            Picker("播放速度", selection: $playback.speed) {
                ForEach(PlaybackController.speeds, id: \.self) { speed in
                    Text(PlaybackController.label(for: speed)).tag(speed)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Text(PlaybackController.label(for: playback.speed))
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(Color(light: "#2A2B30", dark: "#E4E5E8"))
                .frame(minWidth: 40, minHeight: 26)
                .padding(.horizontal, 2)
                .overlay {
                    RoundedRectangle(cornerRadius: 6).strokeBorder(Color(light: "#D4D4D8", dark: "#3A3B41"))
                }
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("播放速度")
    }

    private func barButton(
        _ glyph: Glyph, help: String, size: CGFloat = 16, filled: Bool = false,
        bright: Bool = false, active: Bool = false, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            GlyphIcon(glyph, size: size, lineWidth: filled ? 1.25 : 1.5, filled: filled)
                .foregroundStyle(bright || active ? Color(light: "#18181B", dark: "#FFFFFF") : Self.iconColor)
                .frame(width: size > 16 ? 34 : 30, height: size > 16 ? 34 : 30)
                .background(active ? Color(light: "#E6E6E9", dark: "#2E2F35") : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// 进度条：悬停变粗并预览该位置的画面和时间，点击或拖动跳转；朱红菱形标出封面帧
struct Scrubber: View {
    @ObservedObject var playback: PlaybackController
    let coverTime: Double?
    @State private var hoverFraction: CGFloat?
    @State private var hoverImage: NSImage?
    @State private var dragging = false

    /// 悬停位置按半秒取整，避免鼠标每动一点都去截一帧
    private var hoverKey: Int? {
        hoverFraction.map { Int(Double($0) * playback.duration * 2) }
    }

    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            let progress = playback.duration > 0 ? CGFloat(min(playback.currentTime / playback.duration, 1)) : 0
            let thickness: CGFloat = hoverFraction != nil || dragging ? 6 : 4
            ZStack(alignment: .leading) {
                Capsule().fill(Color(light: "#D4D4D8", dark: "#3A3B41")).frame(height: thickness)
                Capsule().fill(Color(light: "#2A2B30", dark: "#E9E6DF")).frame(width: max(thickness, width * progress), height: thickness)
                if let coverTime, playback.duration > 0 {
                    Rectangle()
                        .fill(Color(hex: "#D9573B"))
                        .frame(width: 8, height: 8)
                        .rotationEffect(.degrees(45))
                        .offset(x: width * CGFloat(min(coverTime / playback.duration, 1)) - 4)
                        .help("封面帧")
                }
                Circle()
                    .fill(Color.white)
                    .frame(width: 12, height: 12)
                    .overlay { Circle().strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5) }
                    .shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
                    .offset(x: width * progress - 6)
                if let hoverFraction {
                    Capsule()
                        .fill(Color(light: "#18181B", dark: "#FFFFFF"))
                        .frame(width: 2, height: 12)
                        .offset(x: width * hoverFraction - 1)
                    hoverTooltip(fraction: hoverFraction)
                        .position(x: min(max(width * hoverFraction, 78), width - 78), y: geometry.size.height / 2 - 72)
                }
            }
            .frame(width: width, height: geometry.size.height)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location): hoverFraction = min(max(location.x / width, 0), 1)
                case .ended: hoverFraction = nil
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        dragging = true
                        playback.isScrubbing = true
                        playback.seek(to: Double(min(max(value.location.x / width, 0), 1)) * playback.duration)
                    }
                    .onEnded { _ in
                        dragging = false
                        playback.isScrubbing = false
                    }
            )
        }
        .frame(height: 24)
        .task(id: hoverKey) {
            guard let hoverFraction else { return }
            try? await Task.sleep(for: .milliseconds(60))
            guard !Task.isCancelled,
                  let image = await playback.frameImage(at: Double(hoverFraction) * playback.duration) else { return }
            hoverImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        }
    }

    private func hoverTooltip(fraction: CGFloat) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Color.black
                if let hoverImage {
                    Image(nsImage: hoverImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }
            }
            .frame(width: 144, height: 81)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            Text(Format.duration(Double(fraction) * playback.duration))
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(Color(light: "#18181B", dark: "#F4F4F5"))
        }
        .padding(6)
        .background(Color(light: "#FFFFFF", dark: "#26272C"), in: RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.25), radius: 10, y: 6)
        .allowsHitTesting(false)
    }
}
