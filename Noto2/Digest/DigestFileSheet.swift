import NotoDigest
import NotoVault
import SwiftUI

/// Where a capture goes. Presented by swiping the digest card right or up and
/// pre-selected to the corresponding mode.
enum DigestFileMode: String, Identifiable, CaseIterable {
    case addTo, create

    var id: String { rawValue }
    var label: String { self == .addTo ? "Add to" : "Create" }
}

enum DigestFileFocusTarget: Hashable {
    case search, title
}

/// Testable initial input contract for the sheet. Create deliberately starts
/// with no suggested title: naming the note is always an explicit user action.
struct DigestFileInputState: Equatable {
    var mode: DigestFileMode
    var query = ""
    var newTitle = ""

    var focusTarget: DigestFileFocusTarget {
        mode == .addTo ? .search : .title
    }
}

/// The destination the user picked, handed back to `DigestScreen` to execute.
/// The sheet chooses; the model files. Keeping the write out of the sheet means
/// the card animation and the error banner stay in one place.
enum DigestDestination {
    case existingNote(url: URL, title: String)
    case newNote(title: String, folderURL: URL)
}

/// Two-mode filing sheet: search the vault for a note to append to, or name a
/// new note and choose the folder it lands in.
struct DigestFileSheet: View {
    let vaultController: VaultController
    let capture: DigestEntry
    let onFile: (DigestDestination) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var input: DigestFileInputState
    @FocusState private var focusedInput: DigestFileFocusTarget?
    @State private var allCandidates: [PageMentionDocument] = []
    @State private var matches: [PageMentionDocument] = []
    @State private var folders: [DigestFolderOption] = []
    @State private var selectedFolder: URL?
    @State private var isLoadingDestinations = true

    init(
        vaultController: VaultController,
        capture: DigestEntry,
        mode: DigestFileMode,
        onFile: @escaping (DigestDestination) -> Void
    ) {
        self.vaultController = vaultController
        self.capture = capture
        self.onFile = onFile
        _input = State(initialValue: DigestFileInputState(mode: mode))
        _folders = State(initialValue: [
            DigestFolderOption(url: vaultController.vaultURL.standardizedFileURL, label: "Vault root")
        ])
    }

    private var trimmedTitle: String { input.newTitle.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canCreate: Bool { DigestMarkdown.filename(forTitle: trimmedTitle) != nil }
    private var destinationFolder: URL { selectedFolder ?? vaultController.vaultURL }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                capturePreview
                Picker("Mode", selection: $input.mode) {
                    ForEach(DigestFileMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .accessibilityIdentifier("digestFileModePicker")

                switch input.mode {
                case .addTo: addToList
                case .create: createForm
                }
            }
            .background(NotoTheme.background.ignoresSafeArea())
            .navigationTitle(input.mode == .addTo ? "Add to a note" : "Create a note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    SheetCircleButton(kind: .close) { dismiss() }
                        .accessibilityIdentifier("digestFileCloseButton")
                        .accessibilityLabel("Cancel")
                }
                if input.mode == .create {
                    ToolbarItem(placement: .topBarTrailing) {
                        SheetCircleButton(kind: .confirm) { confirmCreate() }
                            .disabled(!canCreate)
                            .opacity(canCreate ? 1 : 0.4)
                            .accessibilityIdentifier("digestCreateConfirmButton")
                            .accessibilityLabel("Create note")
                    }
                }
            }
        }
        .presentationDetents([.large])
        .task {
            // Focus before awaiting the vault scan so typing is available as
            // soon as the sheet is on screen, even for a large or iCloud vault.
            await Task.yield()
            focusedInput = input.focusTarget
            await loadDestinations()
        }
        .onChange(of: input.mode) { _, _ in
            Task { @MainActor in
                await Task.yield()
                focusedInput = input.focusTarget
            }
        }
        .onChange(of: input.query) { _, _ in refreshMatches() }
    }

    // MARK: - Shared header

    /// The capture stays visible while choosing — you are deciding about *this*
    /// thought, and a picker that hides it makes you guess.
    private var capturePreview: some View {
        Text(capture.body)
            .font(.system(size: NotoTheme.FontSize.body))
            .foregroundStyle(NotoTheme.ink)
            .lineLimit(3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(NotoTheme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .accessibilityIdentifier("digestFileCapturePreview")
    }

    // MARK: - Add to an existing note

    private var addToList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(NotoTheme.muted)
                TextField("Search notes", text: $input.query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($focusedInput, equals: .search)
                    .accessibilityIdentifier("digestAddToSearchField")
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(NotoTheme.card, in: Capsule())
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            List {
                if isLoadingDestinations {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Loading notes…")
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    .listRowBackground(NotoTheme.background)
                    .accessibilityIdentifier("digestNotePickerLoading")
                } else if matches.isEmpty {
                    Text(input.query.isEmpty ? "No notes in this vault yet." : "No notes match “\(input.query)”.")
                        .foregroundStyle(AppTheme.secondaryText)
                        .listRowBackground(NotoTheme.background)
                        .accessibilityIdentifier("digestNotePickerEmptyState")
                }
                ForEach(matches) { document in
                    Button {
                        onFile(.existingNote(url: document.fileURL, title: document.title))
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(document.title)
                                .font(.system(size: NotoTheme.FontSize.rowTitle, weight: .semibold))
                                .foregroundStyle(NotoTheme.head)
                                .lineLimit(1)
                            Text(document.relativePath)
                                .font(.system(size: NotoTheme.FontSize.subtitle))
                                .foregroundStyle(NotoTheme.muted)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(NotoTheme.background)
                    .accessibilityIdentifier("digestNotePickerRow")
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .accessibilityIdentifier("digestNotePicker")
        }
    }

    private func refreshMatches() {
        matches = DigestNotePicker.filingCandidates(
            allCandidates,
            matching: input.query
        )
    }

    private func loadDestinations() async {
        let vaultURL = vaultController.vaultURL.standardizedFileURL
        let rows = await Task.detached(priority: .userInitiated) {
            (try? SidebarTreeLoader().loadRows(rootURL: vaultURL)) ?? []
        }.value

        allCandidates = DigestNotePicker.documents(from: rows, vaultURL: vaultURL)
        folders = DigestFolderOption.options(from: rows, vaultURL: vaultURL)
        refreshMatches()
        isLoadingDestinations = false
    }

    // MARK: - Create a new note

    private var createForm: some View {
        Form {
            Section("Title") {
                HStack(spacing: 8) {
                    TextField("Note title", text: $input.newTitle)
                        .textInputAutocapitalization(.sentences)
                        .submitLabel(.done)
                        .onSubmit { if canCreate { confirmCreate() } }
                        .focused($focusedInput, equals: .title)
                        .accessibilityIdentifier("digestCreateTitleField")
                }
            }
            Section("Folder") {
                Picker("Folder", selection: Binding(
                    get: { destinationFolder },
                    set: { selectedFolder = $0 }
                )) {
                    ForEach(folders) { folder in
                        Text(folder.label).tag(folder.url)
                    }
                }
                .pickerStyle(.navigationLink)
                .accessibilityIdentifier("digestCreateFolderPicker")
            }
            Section {
                Text(capture.body)
                    .font(.system(size: NotoTheme.FontSize.body))
                    .foregroundStyle(AppTheme.secondaryText)
            } header: {
                Text("Body")
            } footer: {
                Text("Saved as \(DigestMarkdown.filename(forTitle: trimmedTitle) ?? "…") in \(folderLabel).")
            }
        }
        .scrollContentBackground(.hidden)
        .accessibilityIdentifier("digestCreateForm")
    }

    private var folderLabel: String {
        folders.first { $0.url == destinationFolder }?.label ?? "the vault root"
    }

    private func confirmCreate() {
        guard canCreate else { return }
        onFile(.newNote(title: trimmedTitle, folderURL: destinationFolder))
        dismiss()
    }
}

/// Which vault notes may receive a capture.
enum DigestNotePicker {
    static let visibleLimit = 40

    /// Everything except the inbox itself. Other captures are not filing
    /// destinations, and the capture on the card *is* an inbox note — without
    /// this filter you could pick it and append a note to itself. The caller
    /// over-fetches so these exclusions don't eat into the visible count.
    static func filingCandidates(
        _ documents: [PageMentionDocument],
        matching query: String = "",
        limit: Int = visibleLimit
    ) -> [PageMentionDocument] {
        let inboxPrefix = DigestInbox.folderName.lowercased() + "/"
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return documents
            .filter {
                !$0.relativePath.lowercased().hasPrefix(inboxPrefix)
                    && (trimmedQuery.isEmpty || $0.title.localizedCaseInsensitiveContains(trimmedQuery))
            }
            .prefix(limit)
            .map { $0 }
    }

    static func documents(from rows: [SidebarTreeNode], vaultURL: URL) -> [PageMentionDocument] {
        let pathResolver = VaultPathResolver(vaultRootURL: vaultURL)
        return rows.compactMap { row in
            guard case .note = row.kind,
                  let relativePath = pathResolver.relativePath(for: row.url) else {
                return nil
            }
            return PageMentionDocument(
                id: row.noteID ?? VaultDirectoryLoader.stableID(for: row.url),
                title: row.name,
                relativePath: relativePath,
                fileURL: row.url
            )
        }
        .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }
}

/// A pickable destination folder, flattened out of the vault tree with its depth
/// shown as indentation so `Projects / Alpha` is distinguishable from `Alpha`.
struct DigestFolderOption: Identifiable, Hashable {
    let url: URL
    let label: String

    var id: URL { url }

    /// The vault root plus every folder already loaded for this sheet, excluding
    /// `inbox/` — filing a capture back into the inbox is never the intent.
    static func options(from rows: [SidebarTreeNode], vaultURL: URL) -> [DigestFolderOption] {
        var options = [DigestFolderOption(url: vaultURL.standardizedFileURL, label: "Vault root")]
        for row in rows {
            guard case .folder = row.kind else { continue }
            guard row.url.lastPathComponent.lowercased() != DigestInbox.folderName else { continue }
            options.append(
                DigestFolderOption(
                    url: row.url,
                    label: String(repeating: "   ", count: row.depth) + row.name
                )
            )
        }
        return options
    }
}
