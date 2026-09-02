import NotoDigest
import NotoVault
import SwiftUI

/// Where a capture goes. Presented when the digest card is swiped right (or the
/// Add to / Create buttons are tapped), pre-selected to the tapped mode.
enum DigestFileMode: String, Identifiable, CaseIterable {
    case addTo, create

    var id: String { rawValue }
    var label: String { self == .addTo ? "Add to" : "Create" }
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
    @State var mode: DigestFileMode
    let onFile: (DigestDestination) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var matches: [PageMentionDocument] = []
    @State private var newTitle = ""
    @State private var folders: [DigestFolderOption] = []
    @State private var selectedFolder: URL?

    private var trimmedTitle: String { newTitle.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canCreate: Bool { DigestMarkdown.filename(forTitle: trimmedTitle) != nil }
    private var destinationFolder: URL { selectedFolder ?? vaultController.vaultURL }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                capturePreview
                Picker("Mode", selection: $mode) {
                    ForEach(DigestFileMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .accessibilityIdentifier("digestFileModePicker")

                switch mode {
                case .addTo: addToList
                case .create: createForm
                }
            }
            .background(NotoTheme.background.ignoresSafeArea())
            .navigationTitle(mode == .addTo ? "Add to a note" : "Create a note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    SheetCircleButton(kind: .close) { dismiss() }
                        .accessibilityIdentifier("digestFileCloseButton")
                        .accessibilityLabel("Cancel")
                }
                if mode == .create {
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
            refreshMatches()
            folders = DigestFolderOption.load(vaultURL: vaultController.vaultURL)
            // Seed the title from the capture's first line — most captures are
            // already a serviceable title, and an empty field means retyping the
            // thought you just read on the card.
            if newTitle.isEmpty { newTitle = DigestFolderOption.suggestedTitle(from: capture) }
        }
        .onChange(of: query) { _, _ in refreshMatches() }
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
        List {
            if matches.isEmpty {
                Text(query.isEmpty ? "No notes in this vault yet." : "No notes match “\(query)”.")
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
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search notes")
        .accessibilityIdentifier("digestNotePicker")
    }

    private func refreshMatches() {
        matches = DigestNotePicker.filingCandidates(
            vaultController.pageMentions(matching: query, limit: 120, allowEmptyQuery: true)
        )
    }

    // MARK: - Create a new note

    private var createForm: some View {
        Form {
            Section("Title") {
                HStack(spacing: 8) {
                    TextField("Note title", text: $newTitle)
                        .textInputAutocapitalization(.sentences)
                        .submitLabel(.done)
                        .onSubmit { if canCreate { confirmCreate() } }
                        .accessibilityIdentifier("digestCreateTitleField")
                    // The field is pre-filled from the capture's first line, which
                    // is often a whole sentence. Without this you'd hold backspace
                    // 60 times before you could type your own title.
                    if !newTitle.isEmpty {
                        Button {
                            newTitle = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(NotoTheme.faint)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("digestCreateTitleClearButton")
                        .accessibilityLabel("Clear title")
                    }
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
        limit: Int = visibleLimit
    ) -> [PageMentionDocument] {
        let inboxPrefix = DigestInbox.folderName.lowercased() + "/"
        return documents
            .filter { !$0.relativePath.lowercased().hasPrefix(inboxPrefix) }
            .prefix(limit)
            .map { $0 }
    }
}

/// A pickable destination folder, flattened out of the vault tree with its depth
/// shown as indentation so `Projects / Alpha` is distinguishable from `Alpha`.
struct DigestFolderOption: Identifiable, Hashable {
    let url: URL
    let label: String

    var id: URL { url }

    /// The vault root plus every folder in it, excluding `inbox/` — filing a
    /// capture back into the inbox is never the intent.
    static func load(vaultURL: URL) -> [DigestFolderOption] {
        var options = [DigestFolderOption(url: vaultURL.standardizedFileURL, label: "Vault root")]
        let rows = (try? SidebarTreeLoader().loadRows(rootURL: vaultURL)) ?? []
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

    /// A sensible starting title: the capture's first line, stripped of markdown
    /// heading and list markers, capped so the filename stays readable, and with
    /// sentence punctuation trimmed off both ends.
    ///
    /// The trailing trim matters — a capture is usually a sentence, and keeping its
    /// full stop produced filenames like `draft the Q4 roadmap one-pager..md`. The
    /// leading trim keeps `VaultMarkdown.sanitizeFilename` from turning a "Note:
    /// …"-style prefix colon into a fullwidth look-alike.
    static func suggestedTitle(from capture: DigestEntry) -> String {
        var line = capture.summary
        if let heading = line.range(of: #"^#{1,6}\s*"#, options: .regularExpression) {
            line = String(line[heading.upperBound...])
        }
        if let marker = line.range(of: #"^([-*+]|\d+\.)\s+(\[[ xX]\]\s*)?"#, options: .regularExpression) {
            line = String(line[marker.upperBound...])
        }
        line = line.trimmingCharacters(in: .whitespaces)
        if line.count > 60 {
            line = String(line.prefix(60))
        }
        return line.trimmingCharacters(in: Self.titleTrimSet)
    }

    /// Whitespace plus the sentence punctuation that reads as noise in a filename.
    /// Deliberately excludes `?` and `!` — "Ship the digest?" is a title.
    private static let titleTrimSet = CharacterSet(charactersIn: ".,;:—–- ").union(.whitespacesAndNewlines)
}
