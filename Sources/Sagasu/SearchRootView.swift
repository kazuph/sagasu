import SwiftUI
import AppKit

struct SearchRootView: View {
    @ObservedObject var viewModel: SearchViewModel
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                SearchInputField(
                    text: $viewModel.rawQuery,
                    placeholder: viewModel.promptText,
                    onSubmit: {
                        viewModel.activateSelectedResult()
                    },
                    onMoveUp: {
                        viewModel.selectPrevious()
                    },
                    onMoveDown: {
                        viewModel.selectNext()
                    },
                    onTogglePin: {
                        viewModel.togglePinForSelectedClipboardEntry()
                    },
                    onDeleteClipboardEntry: {
                        viewModel.deleteSelectedClipboardEntry()
                    },
                    onEscape: onCancel
                )
                .frame(height: 26)

                HStack(spacing: 6) {
                    ModeBadge(
                        title: viewModel.badgeTitle,
                        color: viewModel.parsedQuery.mode.badgeColor
                    )
                    Text(viewModel.helperText)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.red)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(.ultraThinMaterial)

            Divider()

            HStack(spacing: 0) {
                ScrollViewReader { scrollViewProxy in
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            if viewModel.results.isEmpty {
                                EmptyResultsView(
                                    parsedQuery: viewModel.parsedQuery,
                                    isSearching: viewModel.isSearching
                                )
                                    .padding(.top, 20)
                            } else {
                                ForEach(Array(viewModel.results.enumerated()), id: \.element.id) { index, result in
                                    SearchResultRow(
                                        result: result,
                                        isSelected: index == viewModel.selectedIndex
                                    )
                                    .id(result.id)
                                    .onTapGesture {
                                        viewModel.select(index: index)
                                        viewModel.activateSelectedResult()
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                    }
                    .background(Color(nsColor: .windowBackgroundColor))
                    .onChange(of: viewModel.selectedResultID) { _, selectedResultID in
                        guard let selectedResultID else { return }
                        withAnimation(.snappy(duration: 0.15)) {
                            scrollViewProxy.scrollTo(selectedResultID, anchor: .center)
                        }
                    }
                }

                if let previewImageURL = viewModel.selectedPreviewImageURL {
                    Divider()
                    SelectedImagePreviewView(url: previewImageURL)
                        .frame(width: 220)
                        .background(.ultraThinMaterial)
                }
            }
        }
        .frame(minWidth: 680, minHeight: 348)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.14), radius: 20, x: 0, y: 14)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(12)
        .id(viewModel.presentationID)
        .onExitCommand(perform: onCancel)
    }
}

private struct SearchResultRow: View {
    let result: SearchResult
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            SearchResultVisualView(
                visual: result.visual,
                isSelected: isSelected
            )
            .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(result.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                    .lineLimit(1)
                Text(compactMetadata)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.86) : Color.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
        )
        .help(
            [result.title, result.subtitle, result.detail]
                .filter { $0.isEmpty == false }
                .joined(separator: "\n")
        )
    }

    private var compactMetadata: String {
        let parts = [result.subtitle, result.detail]
            .filter { $0.isEmpty == false }
            .reduce(into: [String]()) { partialResult, item in
                if partialResult.contains(item) == false {
                    partialResult.append(item)
                }
            }

        return parts.joined(separator: "  ·  ")
    }
}

private struct SearchResultVisualView: View {
    let visual: SearchResultVisual
    let isSelected: Bool

    var body: some View {
        switch visual {
        case .symbol(let systemImage):
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isSelected ? Color.white : Color.accentColor)

        case .fileIcon(let url):
            NativeImageView(
                image: ResultImageProvider.shared.icon(for: url),
                isSelected: isSelected
            )

        case .imageThumbnail(let url):
            ThumbnailView(url: url, isSelected: isSelected)
        }
    }
}

private struct NativeImageView: View {
    let image: NSImage
    let isSelected: Bool

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(isSelected ? Color.white.opacity(0.24) : Color.black.opacity(0.08), lineWidth: 0.5)
            )
    }
}

private struct ThumbnailView: View {
    let url: URL
    let isSelected: Bool

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                NativeImageView(image: image, isSelected: isSelected)
            } else {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.22) : Color.secondary.opacity(0.12))
                    .overlay(
                        Image(systemName: "photo")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(isSelected ? Color.white.opacity(0.8) : Color.secondary)
                    )
            }
        }
        .task(id: url) {
            image = await ResultImageProvider.shared.thumbnail(for: url)
        }
    }
}

@MainActor
private final class ResultImageProvider {
    static let shared = ResultImageProvider()

    private let iconCache = NSCache<NSURL, NSImage>()
    private let thumbnailCache = NSCache<NSURL, NSImage>()

    func icon(for url: URL) -> NSImage {
        let key = url as NSURL
        if let cached = iconCache.object(forKey: key) {
            return cached
        }

        let image = NSWorkspace.shared.icon(forFile: url.path)
        image.size = NSSize(width: 22, height: 22)
        iconCache.setObject(image, forKey: key)
        return image
    }

    func thumbnail(for url: URL) async -> NSImage? {
        let key = url as NSURL
        if let cached = thumbnailCache.object(forKey: key) {
            return cached
        }

        let image = await Task.detached(priority: .userInitiated) {
            NSImage(contentsOf: url)
        }.value

        guard let image else { return nil }
        image.size = NSSize(width: 22, height: 22)
        thumbnailCache.setObject(image, forKey: key)
        return image
    }

    func previewImage(for url: URL) async -> NSImage? {
        await Task.detached(priority: .userInitiated) {
            NSImage(contentsOf: url)
        }.value
    }
}

private struct EmptyResultsView: View {
    let parsedQuery: ParsedSearchQuery
    let isSearching: Bool

    var body: some View {
        VStack(spacing: 8) {
            if isSearching {
                ProgressView()
                    .controlSize(.small)
                Text("Searching…")
                    .font(.system(size: 16, weight: .semibold))
                Text("Looking through \(displayName.lowercased())…")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Image(systemName: parsedQuery.mode.emptyStateIcon)
                    .font(.system(size: 26))
                    .foregroundStyle(.secondary)
                Text(emptyStateTitle)
                    .font(.system(size: 16, weight: .semibold))
                Text(emptyStateDescription)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var displayName: String {
        if parsedQuery.mode == .clipboard && parsedQuery.clipboardImageOnly {
            return "Clipboard Images"
        }
        return parsedQuery.mode.displayName
    }

    private var emptyStateTitle: String {
        if parsedQuery.mode == .clipboard && parsedQuery.clipboardImageOnly {
            return parsedQuery.query.isEmpty ? "Type after `vi ` to search clipboard images" : "No clipboard images matched"
        }
        return parsedQuery.mode.emptyStateTitle(for: parsedQuery.query)
    }

    private var emptyStateDescription: String {
        if parsedQuery.mode == .clipboard && parsedQuery.clipboardImageOnly {
            return "Only saved clipboard images are searched here. Use `v ` to search text and image history together."
        }
        return parsedQuery.mode.emptyStateDescription(for: parsedQuery.query)
    }
}

private struct SelectedImagePreviewView: View {
    let url: URL

    @State private var image: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Preview")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            Group {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                } else {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.secondary.opacity(0.12))
                        .overlay(
                            ProgressView()
                                .controlSize(.small)
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 0.5)
            )
        }
        .padding(12)
        .task(id: url) {
            image = await ResultImageProvider.shared.previewImage(for: url)
        }
    }
}

private struct ModeBadge: View {
    let title: String
    let color: Color

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(color.opacity(0.14))
            )
            .foregroundStyle(color)
    }
}

private extension SearchMode {
    var badgeColor: Color {
        switch self {
        case .applications:
            return .accentColor
        case .directories:
            return .cyan
        case .files:
            return .blue
        case .terminals:
            return .green
        case .notes:
            return .orange
        case .clipboard:
            return .green
        case .githubOwnedRepositories, .githubGlobalRepositories, .githubIssues, .githubPullRequests, .ghqRepositories:
            return .purple
        case .linearIssues:
            return .indigo
        }
    }

    var emptyStateIcon: String {
        switch self {
        case .applications:
            return "app.badge"
        case .directories:
            return "folder"
        case .files:
            return "folder.badge.questionmark"
        case .terminals:
            return "terminal"
        case .notes:
            return "note.text.badge.plus"
        case .clipboard:
            return "doc.on.clipboard"
        case .githubOwnedRepositories, .githubGlobalRepositories:
            return "chevron.left.forwardslash.chevron.right"
        case .githubIssues:
            return "smallcircle.filled.circle"
        case .githubPullRequests:
            return "arrow.triangle.pull"
        case .ghqRepositories:
            return "externaldrive"
        case .linearIssues:
            return "line.3.horizontal.decrease.circle"
        }
    }

    func emptyStateTitle(for query: String) -> String {
        switch self {
        case .applications:
            return query.isEmpty ? "Search applications" : "No applications matched"
        case .directories:
            return query.isEmpty ? "Recent and common directories" : "No directories matched"
        case .files:
            return query.isEmpty ? "Type after `f ` to search files" : "No files matched"
        case .terminals:
            return query.isEmpty ? "Herdr panes" : "No Herdr panes matched"
        case .notes:
            return query.isEmpty ? "Type after `n ` to search Notes" : "No notes matched"
        case .clipboard:
            return "Clipboard history is empty"
        case .githubOwnedRepositories:
            return query.isEmpty ? "Your ghq and GitHub repositories" : "No owned repositories matched"
        case .githubGlobalRepositories:
            return query.isEmpty ? "Type after `gh ` to search GitHub" : "No GitHub repositories matched"
        case .githubIssues:
            return query.isEmpty ? "Type after `gi ` to search issues" : "No GitHub issues matched"
        case .githubPullRequests:
            return query.isEmpty ? "Type after `gp ` to search pull requests" : "No GitHub pull requests matched"
        case .ghqRepositories:
            return query.isEmpty ? "ghq repositories" : "No ghq repositories matched"
        case .linearIssues:
            return query.isEmpty ? "Type after `l ` to search Linear issues" : "No Linear issues matched"
        }
    }

    func emptyStateDescription(for query: String) -> String {
        switch self {
        case .applications:
            return query.isEmpty
                ? "Command + Space opens in application-first mode, with Google and ChatGPT routes once you type."
                : "Try a shorter app name or use the Google / ChatGPT routes shown in default mode."
        case .directories:
            return "Use `d ` for directories only, or `f ` when you also want file results."
        case .files:
            return query.isEmpty
                ? "Search is limited to Desktop, Downloads, Documents, Pictures, Movies, Dropbox, iCloud, and recent places."
                : "Search is limited to Desktop, Downloads, Documents, Pictures, Movies, Dropbox, iCloud, and recent places."
        case .terminals:
            return "Use `t ` to jump to a Herdr workspace, tab, and pane."
        case .notes:
            return query.isEmpty
                ? "The first Notes search may ask macOS for automation permission."
                : "The first Notes search may ask macOS for automation permission."
        case .clipboard:
            return "Copy text or images anywhere on macOS, then search them later with `v `. Press ⌘P on a selected entry to toggle pin."
        case .githubOwnedRepositories:
            return "`g ` searches ghq first, then repositories owned by you and your organizations when gh is available."
        case .githubGlobalRepositories:
            return "`gh ` searches repositories across GitHub when gh is available."
        case .githubIssues:
            return "`gi ` searches issues in repositories owned by you and your organizations."
        case .githubPullRequests:
            return "`gp ` searches pull requests in repositories owned by you and your organizations."
        case .ghqRepositories:
            return "`ghq ` searches only local ghq repository entries."
        case .linearIssues:
            return "Sagasu stores your Linear API key in macOS Keychain and opens issue results in Chrome."
        }
    }
}
