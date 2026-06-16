import AppKit

@MainActor
enum StatusPopoverAnchor {
    static func rect(for button: NSButton) -> NSRect {
        button.cell?.imageRect(forBounds: button.bounds) ?? button.bounds
    }
}
