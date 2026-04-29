import Foundation

enum LauncherError: LocalizedError {
    case clipboardEntryUnavailable
    case clipboardImageMissing
    case clipboardWriteFailed
    case hotKeyRegistrationFailed(OSStatus)
    case notesAutomationFailed(String)
    case commandFailed(executable: String, message: String)
    case snapshotFailed(String)

    var errorDescription: String? {
        switch self {
        case .clipboardEntryUnavailable:
            return "The selected clipboard history entry is no longer available."
        case .clipboardImageMissing:
            return "The saved clipboard image could not be restored because its backing file is missing."
        case .clipboardWriteFailed:
            return "Clipboard history entry could not be written back to the system pasteboard."
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
