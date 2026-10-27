import AppKit
import UniformTypeIdentifiers

@MainActor
enum Panels {
    static func saveNewLibrary(suggestedName: String, title: String = "新建资源库") -> URL? {
        let panel = NSSavePanel()
        panel.title = title
        panel.prompt = "创建"
        panel.message = "资源库是一个文件夹，导入的素材会复制到里面。"
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func chooseLibrary() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "打开资源库"
        panel.prompt = "打开"
        panel.message = "选择一个 .kura 资源库"
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func chooseEagleLibrary() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "从 Eagle 导入"
        panel.prompt = "导入"
        panel.message = "选择 Eagle 资源库（.library）。只会读取，不会修改原资源库。"
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.treatsFilePackagesAsDirectories = false
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func chooseTagIcon() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "选择标签图标"
        panel.prompt = "选择"
        panel.message = "支持 SVG、PNG、JPG 等图片。单色 SVG 会跟随界面的文字颜色。"
        panel.allowedContentTypes = [.image, .pdf]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func chooseFilesToImport() -> [URL] {
        let panel = NSOpenPanel()
        panel.title = "导入素材"
        panel.prompt = "导入"
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        return panel.runModal() == .OK ? panel.urls : []
    }
}
