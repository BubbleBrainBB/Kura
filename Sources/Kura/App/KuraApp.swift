import AppKit
import SwiftUI

@main
struct KuraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("Kura", id: "main") {
            RootView()
                .environmentObject(model)
        }
        .defaultSize(model.library == nil && !model.isRestoring ? WindowSizer.welcome : WindowSizer.library)
        .commands { AppCommands(model: model) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// 「编辑 › 粘贴」（⌘V）：光标在输入框里时由输入框自己粘贴文字；
    /// 没有输入框接收时这个动作沿响应链传到这里，把剪贴板里的图片、文件导入资源库
    @MainActor @objc func paste(_ sender: Any?) {
        NotificationCenter.default.post(name: .kuraPaste, object: nil)
    }

    @MainActor
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(paste(_:)) {
            return AppModel.shared?.library != nil && PasteboardImport.hasContent()
        }
        return true
    }

    /// 拖到 Dock 图标上、或 `open -a "Kura" 文件…` 打开的文件：资源库直接打开，其余导入当前资源库
    @MainActor
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let model = AppModel.shared else { return }
        if let library = model.library, !urls.contains(where: LibraryStore.isLibrary) {
            library.importFiles(urls)
        } else {
            model.handleDrop(urls)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if let library = model.library {
                MainView(store: library)
                    .id(library.url)
            } else if model.isRestoring {
                // 等待系统授权访问资源库所在文件夹时，窗口先出来并说明在做什么
                ProgressView("正在打开资源库…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                WelcomeView()
            }
        }
        .onChange(of: model.library == nil) { _, isWelcome in
            WindowSizer.resize(to: isWelcome ? WindowSizer.welcome : WindowSizer.library, growOnly: !isWelcome)
        }
        .onChange(of: model.isRestoring) { _, restoring in
            // 上次的资源库打不开时回到欢迎页的尺寸
            if !restoring, model.library == nil {
                WindowSizer.resize(to: WindowSizer.welcome, growOnly: false)
            }
        }
        .alert(
            "出错了",
            isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } }),
            presenting: model.errorMessage
        ) { _ in
            Button("好") {}
        } message: { message in
            Text(message)
        }
    }
}

enum WindowSizer {
    static let welcome = CGSize(width: 960, height: 620)
    static let library = CGSize(width: 1280, height: 800)

    /// 在欢迎页和资源库之间切换时调整窗口大小，保持窗口中心不动
    @MainActor
    static func resize(to size: CGSize, growOnly: Bool) {
        guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: \.isVisible) else { return }
        let current = window.contentRect(forFrameRect: window.frame).size
        if growOnly, current.width >= size.width, current.height >= size.height { return }
        let target = growOnly ? CGSize(width: max(current.width, size.width), height: max(current.height, size.height)) : size
        let newFrame = window.frameRect(forContentRect: NSRect(origin: .zero, size: target))
        var frame = window.frame
        frame.origin.x -= (newFrame.width - frame.width) / 2
        frame.origin.y -= (newFrame.height - frame.height) / 2
        frame.size = newFrame.size
        window.setFrame(frame, display: true, animate: true)
    }
}

struct AppCommands: Commands {
    @ObservedObject var model: AppModel

    /// 主界面用 @AppStorage 读这两个开关，改 UserDefaults 就会同步过去
    private func togglePanel(_ key: String) {
        let defaults = UserDefaults.standard
        defaults.set(!(defaults.object(forKey: key) as? Bool ?? true), forKey: key)
    }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("新建资源库…") { model.showNewLibraryPanel() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("打开资源库…") { model.showOpenLibraryPanel() }
                .keyboardShortcut("o")
            Divider()
            Button("导入文件…") {
                guard let library = model.library else { return }
                let urls = Panels.chooseFilesToImport()
                if !urls.isEmpty { library.importFiles(urls) }
            }
            .keyboardShortcut("i")
            .disabled(model.library == nil)
            Button("从 Eagle 导入…") { model.showEagleImportPanel() }
            Divider()
            Button("关闭资源库") { model.closeLibrary() }
                .disabled(model.library == nil)
        }
        CommandGroup(after: .sidebar) {
            Button("显示或隐藏侧栏") { togglePanel("showSidebar") }
                .keyboardShortcut("s", modifiers: [.control, .command])
                .disabled(model.library == nil)
            Button("显示或隐藏信息面板") { togglePanel("showInspector") }
                .keyboardShortcut("i", modifiers: [.option, .command])
                .disabled(model.library == nil)
            Divider()
            Button("放大缩略图") { ThumbnailSize.adjust(by: 1) }
                .keyboardShortcut("+")
                .disabled(model.library == nil)
            Button("缩小缩略图") { ThumbnailSize.adjust(by: -1) }
                .keyboardShortcut("-")
                .disabled(model.library == nil)
        }
        CommandGroup(after: .textEditing) {
            Button("搜索素材") { NotificationCenter.default.post(name: .kuraFocusSearch, object: nil) }
                .keyboardShortcut("f")
                .disabled(model.library == nil)
        }
    }
}
