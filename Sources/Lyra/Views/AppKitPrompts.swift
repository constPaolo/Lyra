import AppKit

@MainActor
enum AppKitPrompts {
    /// Modal text prompt used for creating/renaming playlists. Returns the
    /// trimmed value, or nil if cancelled or left empty.
    static func promptForName(title: String, defaultValue: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = "Enter a name for the playlist."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(string: defaultValue)
        field.placeholderString = "Playlist name"
        field.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        alert.accessoryView = field
        field.selectText(nil)

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// Folder chooser used to add a music library root.
    static func chooseMusicFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Folder"
        panel.message = "Select a folder containing your music library"
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }
}
