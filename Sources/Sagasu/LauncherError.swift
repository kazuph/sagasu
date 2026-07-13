import Foundation
import Security

enum LauncherError: LocalizedError {
    case accessibilityPermissionRequired
    case clipboardEntryUnavailable
    case clipboardImageMissing
    case clipboardImageTextNotFound
    case clipboardWriteFailed
    case herdrUnavailable
    case hotKeyRegistrationFailed(OSStatus)
    case windowManagementFailed(String)
    case notesAutomationFailed(String)
    case commandFailed(executable: String, message: String)
    case snapshotFailed(String)
    case linearAPIKeyRequired
    case linearRequestFailed(String)
    case keychainReadFailed(OSStatus)
    case keychainWriteFailed(OSStatus)

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
        case .windowManagementFailed(let message):
            return "Window management failed: \(message)"
        case .notesAutomationFailed(let message):
            return "Notes search failed: \(message)"
        case .commandFailed(let executable, let message):
            return "\(executable) failed: \(message)"
        case .snapshotFailed(let message):
            return "Snapshot failed: \(message)"
        case .linearAPIKeyRequired:
            return "Enter a Linear API key to enable `l ` search."
        case .linearRequestFailed(let message):
            return "Linear search failed: \(message)"
        case .keychainReadFailed(let status):
            return "Could not read the Linear API key from Keychain. OSStatus \(status)."
        case .keychainWriteFailed(let status):
            return "Could not save the Linear API key to Keychain. OSStatus \(status)."
        }
    }
}
