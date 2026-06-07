#if os(macOS)
import SwiftUI
import NotoVault

/// macOS-native Properties view, presented in a sheet by `NoteEditorScreen`. Unlike the
/// iOS `PropertiesSheet` (an inset-grouped list with a modal graphical date picker — both
/// awkward on the Mac), this uses a native grouped `Form` with inline controls: plain text
/// fields, an inline field-and-stepper `DatePicker`, and a right-click delete. It edits the
/// SAME shared data layer (`EditableFrontmatterDocument` + `session.applyExternalContentEdit`),
/// so frontmatter handling/persistence is identical across platforms.
struct MacPropertiesForm: View {
    @Bindable var session: NoteEditorSession
    var onClose: () -> Void
    var onMoveFolder: (() -> Void)?

    @Environment(\.openURL) private var openURL

    /// Pending text/url/tags edits, keyed by field key. Committed on submit or on close.
    @State private var drafts: [String: String] = [:]

    // add-property alert
    @State private var isAddingProperty = false
    @State private var newPropertyType: MacPropertyType = .text
    @State private var newPropertyKey = ""
    @State private var newPropertyValue = ""

    private static let reserved: Set<String> = ["id", "created", "modified"]

    private var fields: [EditableFrontmatterField] {
        EditableFrontmatterDocument(markdown: session.content)?.fields ?? []
    }

    private var customFields: [EditableFrontmatterField] {
        fields.filter { !Self.reserved.contains($0.key.lowercased()) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Form {
                Section {
                    folderRow
                    if let created = absoluteDate(forKey: "created") {
                        LabeledContent("Created", value: created)
                    }
                    LabeledContent("Modified", value: modifiedDisplay)
                    ForEach(customFields) { field in
                        fieldRow(for: field)
                            .contextMenu {
                                Button(role: .destructive) {
                                    deleteField(field.key)
                                } label: {
                                    Label("Delete Property", systemImage: "trash")
                                }
                            }
                    }
                }
                Section {
                    addPropertyMenu
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
        .background(NotoTheme.background)
        .tint(NotoTheme.accent)
        .accessibilityIdentifier("properties_sheet")
        // Commit any in-progress draft edits when the panel goes away by ANY route
        // (close button, folder move, or tapping the backdrop).
        .onDisappear { commitAll() }
        .alert("New \(newPropertyType.label) Property", isPresented: $isAddingProperty) {
            TextField("Name", text: $newPropertyKey)
            TextField(newPropertyType.valuePlaceholder, text: $newPropertyValue)
            Button("Cancel", role: .cancel) { resetAddState() }
            Button("Add") { commitAdd() }
        }
    }

    // MARK: Header — matches the app's paired ✕ / ✓ sheet header.

    private var header: some View {
        ZStack {
            Text("Properties")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(NotoTheme.head)
            HStack {
                // Editing auto-commits, so close IS confirm — a single ✕ (no paired ✓).
                SheetCircleButton(kind: .close) {
                    commitAll()
                    onClose()
                }
                .accessibilityIdentifier("properties_close_button")
                .accessibilityLabel("Done")
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    // MARK: Rows

    private var folderRow: some View {
        LabeledContent("Folder") {
            Button {
                commitAll()
                onMoveFolder?()
            } label: {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(NotoTheme.accent)
                        .frame(width: 7, height: 7)
                    Text(folderName)
                        .foregroundStyle(NotoTheme.muted)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(NotoTheme.faint)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("property_row_folder")
        }
    }

    @ViewBuilder
    private func fieldRow(for field: EditableFrontmatterField) -> some View {
        let kind = NotePropertyClassifier.kind(key: field.key, value: field.value)
        let label = field.key.capitalized
        switch kind {
        case .date:
            DatePicker(
                label,
                selection: dateBinding(for: field),
                displayedComponents: field.value.contains("T") ? [.date, .hourAndMinute] : [.date]
            )
            .accessibilityIdentifier("property_row_\(field.key.lowercased())")
        case .url:
            LabeledContent(label) {
                HStack(spacing: 6) {
                    TextField("", text: textBinding(for: field))
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(NotoTheme.accent)
                        .onSubmit { commit(field.key) }
                    Button {
                        openURLValue(textBinding(for: field).wrappedValue)
                    } label: {
                        Image(systemName: "arrow.up.right.square")
                            .foregroundStyle(NotoTheme.faint)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("open_url_button")
                }
            }
            .accessibilityIdentifier("property_row_\(field.key.lowercased())")
        case .tags:
            LabeledContent(label) {
                TextField("tag1, tag2", text: tagsBinding(for: field))
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(NotoTheme.head)
                    .onSubmit { commit(field.key) }
            }
            .accessibilityIdentifier("property_row_\(field.key.lowercased())")
        case .text:
            LabeledContent(label) {
                TextField("", text: textBinding(for: field))
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(NotoTheme.head)
                    .onSubmit { commit(field.key) }
            }
            .accessibilityIdentifier("property_row_\(field.key.lowercased())")
        }
    }

    private var addPropertyMenu: some View {
        Menu {
            ForEach(MacPropertyType.allCases, id: \.self) { type in
                Button {
                    beginAdding(type)
                } label: {
                    Label(type.label, systemImage: type.glyph)
                }
                .accessibilityIdentifier("property_type_\(type.rawValue)")
            }
        } label: {
            Label("Add property", systemImage: "plus")
                .foregroundStyle(NotoTheme.accent)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .accessibilityIdentifier("add_property_button")
    }

    // MARK: Bindings

    /// Text/url binding — reads the (unquoted) committed value unless a draft exists.
    private func textBinding(for field: EditableFrontmatterField) -> Binding<String> {
        Binding(
            get: { drafts[field.key] ?? Self.unquoted(field.value) },
            set: { drafts[field.key] = $0 }
        )
    }

    /// Tags binding — comma-joined for display, re-serialized on commit.
    private func tagsBinding(for field: EditableFrontmatterField) -> Binding<String> {
        Binding(
            get: { drafts[field.key] ?? NotePropertyClassifier.parseTags(field.value).joined(separator: ", ") },
            set: { drafts[field.key] = $0 }
        )
    }

    /// Date binding — writes back immediately (date changes are discrete).
    private func dateBinding(for field: EditableFrontmatterField) -> Binding<Date> {
        Binding(
            get: { NotePropertyClassifier.date(from: field.value) ?? Date(timeIntervalSince1970: 0) },
            set: { newDate in
                let dateOnly = !field.value.contains("T")
                updateField(field.key, NotePropertyClassifier.dateString(from: newDate, dateOnly: dateOnly))
            }
        )
    }

    // MARK: Commit

    private func commit(_ key: String) {
        guard let draft = drafts[key] else { return }
        let kind = NotePropertyClassifier.kind(key: key, value: fields.first { $0.key == key }?.value ?? "")
        if kind == .tags {
            let members = draft.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            updateField(key, NotePropertyClassifier.serializeTags(members))
        } else {
            updateField(key, draft)
        }
        drafts[key] = nil
    }

    private func commitAll() {
        for key in drafts.keys { commit(key) }
    }

    // MARK: Add property

    private func beginAdding(_ type: MacPropertyType) {
        newPropertyType = type
        newPropertyKey = ""
        newPropertyValue = ""
        isAddingProperty = true
    }

    private func commitAdd() {
        guard let parsed = EditableFrontmatterDocument.parsedFieldInput(
            key: newPropertyKey, value: newPropertyValue
        ) else {
            resetAddState()
            return
        }
        addField(parsed.key, parsed.value)
        resetAddState()
    }

    private func resetAddState() {
        isAddingProperty = false
        newPropertyKey = ""
        newPropertyValue = ""
    }

    // MARK: Write-back (shared data layer)

    private func openURLValue(_ value: String) {
        let trimmed = value.trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
        if let url = URL(string: trimmed) { openURL(url) }
    }

    private func updateField(_ key: String, _ value: String) {
        session.applyExternalContentEdit(
            EditableFrontmatterDocument.updatingField(key: key, value: value, in: session.content)
        )
    }

    private func addField(_ key: String, _ value: String) {
        session.applyExternalContentEdit(
            EditableFrontmatterDocument.addingField(key: key, value: value, in: session.content)
        )
    }

    private func deleteField(_ key: String) {
        drafts[key] = nil
        session.applyExternalContentEdit(
            EditableFrontmatterDocument.deletingField(key: key, in: session.content)
        )
    }

    // MARK: Derived

    private var folderName: String {
        let parent = session.note.fileURL.deletingLastPathComponent().standardizedFileURL
        let root = session.store.vaultRootURL.standardizedFileURL
        if parent == root {
            return root.lastPathComponent.isEmpty ? "Vault" : root.lastPathComponent
        }
        return parent.lastPathComponent
    }

    private var modifiedDisplay: String {
        if let raw = fields.first(where: { $0.key.lowercased() == "modified" })?.value,
           let date = NotePropertyClassifier.date(from: raw) {
            return NotoRelativeDate.compactString(from: date)
        }
        return NotoRelativeDate.compactString(from: session.note.modifiedDate)
    }

    private func absoluteDate(forKey key: String) -> String? {
        guard let raw = fields.first(where: { $0.key.lowercased() == key })?.value,
              let date = NotePropertyClassifier.date(from: raw) else { return nil }
        return Self.absoluteFormatter.string(from: date)
    }

    static func unquoted(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { return trimmed }
        let isDoubleQuoted = trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"")
        let isSingleQuoted = trimmed.hasPrefix("'") && trimmed.hasSuffix("'")
        return (isDoubleQuoted || isSingleQuoted) ? String(trimmed.dropFirst().dropLast()) : trimmed
    }

    private static let absoluteFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f
    }()
}

/// Add-property pull-down options (macOS).
private enum MacPropertyType: String, CaseIterable {
    case text, tags, date

    var label: String {
        switch self {
        case .text: return "Text"
        case .tags: return "Tags"
        case .date: return "Date & time"
        }
    }

    var glyph: String {
        switch self {
        case .text: return "textformat"
        case .tags: return "tag"
        case .date: return "calendar"
        }
    }

    var valuePlaceholder: String {
        switch self {
        case .text: return "Value"
        case .tags: return "tag1, tag2"
        case .date: return "2026-06-04"
        }
    }
}
#endif
