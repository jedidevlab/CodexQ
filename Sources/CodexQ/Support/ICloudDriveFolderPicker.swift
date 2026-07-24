import AppKit

@MainActor
enum ICloudDriveFolderPicker {
    static func chooseFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "选择 iCloud Drive 成本账本文件夹"
        panel.message = "请选择 iCloud Drive 中的专用文件夹。CodexQ 只会写入脱敏 Token 成本账本。"
        panel.prompt = "选择"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }
}
