import Foundation

enum LauncherError: LocalizedError {
    case accessibilityPermissionRequired
    case clipboardEntryUnavailable
    case clipboardImageMissing
    case clipboardImageTextNotFound
    case clipboardWriteFailed
    case herdrUnavailable
    case hotKeyRegistrationFailed(OSStatus)
    case notesAutomationFailed(String)
    case commandFailed(executable: String, message: String)
    case snapshotFailed(String)

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionRequired:
            return "Window management needs Accessibility permission for Sagasu. Grant Sagasu access in System Settings > Privacy & Security > Accessibility, then relaunch Sagasu."
        case .clipboardEntryUnavailable:
            return "The selected clipboard history entry is no longer available."
        case .clipboardImageMissing:
            return "The saved clipboard image could not be restored because its backing file is missing."
        case .clipboardImageTextNotFound:
            return "The clipboard image was saved, but no text was recognized in it."
        case .clipboardWriteFailed:
            return "Clipboard history entry could not be written back to the system pasteboard."
        case .herdrUnavailable:
            return "Herdr is not available at ~/.local/bin/herdr, /opt/homebrew/bin/herdr, or /usr/local/bin/herdr."
        case .hotKeyRegistrationFailed(let status):
            return "Global hotkey registration failed with status \(status)."
        case .notesAutomationFailed(let message):
            return "Notes search failed: \(message)"
        case .commandFailed(let executable, let message):
            return "\(executable) failed: \(message)"
        case .snapshotFailed(let message):
            return "Snapshot failed: \(message)"
        }
    }
}
