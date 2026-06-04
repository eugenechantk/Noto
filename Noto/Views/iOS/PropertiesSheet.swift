#if os(iOS)
import SwiftUI
import NotoVault

/// v2 Properties sheet (`NotoPropertyList` / `noto-properties-hig.jsx`) presented over the
/// editor. Renders the note's YAML frontmatter as an inset-grouped iOS list and edits it
/// through `EditableFrontmatterDocument` + `session.applyExternalContentEdit`, which
/// preserves every key and persists synchronously (no data loss).
///
/// Editable kinds (inferred via `NotePropertyClassifier`). Editing is INLINE (a text field
/// in the row, with the accent caret) except where a picker is required:
///   • text   — tap value → inline edit
///   • url    — tap value → open in browser; pencil → inline edit the URL
///   • tags   — tap a chip → inline-edit that member (empty removes); "+" adds one
///   • date   — tap row → date & time picker (not inline)
///   • folder — tap → move the note via the file picker (not inline)
struct PropertiesSheet: View {
    @Bindable var session: NoteEditorSession
    var onClose: () -> Void
    var onMoveFolder: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    // inline editing — one field at a time. `editingTagIndex` non-nil means a tag member.
    @State private var editingKey: String?
    @State private var editingTagIndex: Int?
    @State private var editingTagMembers: [String] = []
    @State private var draft = ""
    @FocusState private var fieldFocused: Bool

    // date editing (in-sheet picker overlay)
    @State private var editingDateKey: String?
    @State private var editingDate = Date(timeIntervalSince1970: 0)
    @State private var editingDateOnly = true

    // add property (type menu → inline new row reuses the inline editor for the value)
    @State private var isAddingProperty = false
    @State private var newPropertyType: PropertyType = .text
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
        ZStack {
            VStack(spacing: 0) {
                header
                propertyList
            }
            if editingDateKey != nil {
                dateEditorOverlay
            }
        }
        .background(NotoTheme.groupedBackground.ignoresSafeArea())
        .accessibilityIdentifier("properties_sheet")
        .alert("New \(newPropertyType.label) Property", isPresented: $isAddingProperty) {
            TextField("Name", text: $newPropertyKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            TextField(newPropertyType.valuePlaceholder, text: $newPropertyValue)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Cancel", role: .cancel) { resetAddState() }
            Button("Add") { commitAdd() }
        }
    }

    // MARK: Header

    private var header: some View {
        ZStack {
            Text("Properties")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(NotoTheme.head)
            HStack {
                SheetCircleButton(kind: .close) {
                    commitInlineEdit()
                    onClose()
                    dismiss()
                }
                .accessibilityIdentifier("properties_close_button")
                .accessibilityLabel("Close")
                Spacer()
                SheetCircleButton(kind: .confirm) {
                    commitInlineEdit()
                    onClose()
                    dismiss()
                }
                .accessibilityIdentifier("properties_confirm_button")
                .accessibilityLabel("Done")
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    // MARK: List

    private var propertyList: some View {
        List {
            Section {
                folderRow
                dateRow(key: "created", label: "Created", glyph: "calendar", absolute: true)
                dateRow(key: "modified", label: "Modified", glyph: "clock", absolute: false)
                ForEach(customFields) { field in
                    propertyRow(for: field)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                deleteField(field.key)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
                addPropertyRow
            }
            .listRowBackground(NotoTheme.card)
            .listRowSeparatorTint(NotoTheme.separator)
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(NotoTheme.groupedBackground)
        .contentMargins(.top, 12, for: .scrollContent)
        .environment(\.defaultMinListRowHeight, 44)
        .tint(NotoTheme.accent)
    }

    // MARK: Rows

    private var folderRow: some View {
        Button {
            commitInlineEdit()
            onMoveFolder?()
        } label: {
            PropertyRowLayout(glyph: "folder", label: "Folder", showsChevron: true) {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(NotoTheme.accent)
                        .frame(width: 7, height: 7)
                    Text(folderName)
                        .lineLimit(1)
                        .foregroundStyle(NotoTheme.muted)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("property_row_folder")
    }

    @ViewBuilder
    private func dateRow(key: String, label: String, glyph: String, absolute: Bool) -> some View {
        if let value = formattedDate(forKey: key, absolute: absolute) {
            PropertyRowLayout(glyph: glyph, label: label, showsChevron: false) {
                Text(value)
                    .foregroundStyle(NotoTheme.faint)
                    .lineLimit(1)
            }
            .accessibilityIdentifier("property_row_\(key)")
        }
    }

    @ViewBuilder
    private func propertyRow(for field: EditableFrontmatterField) -> some View {
        let lowerKey = field.key.lowercased()
        let kind = NotePropertyClassifier.kind(key: field.key, value: field.value)
        PropertyRowLayout(
            glyph: glyph(forKey: lowerKey, kind: kind),
            label: field.key.capitalized,
            showsChevron: lowerKey.contains("status")
        ) {
            valueView(for: field, kind: kind)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // Whole-row tap drives text (inline) and date (picker). url/tags use their
            // own element taps so this is a no-op for them.
            switch kind {
            case .text where !lowerKey.contains("status"): beginInlineEdit(field)
            case .date: beginDateEdit(field)
            default: break
            }
        }
        .accessibilityIdentifier("property_row_\(lowerKey)")
    }

    @ViewBuilder
    private func valueView(for field: EditableFrontmatterField, kind: NotePropertyKind) -> some View {
        let lowerKey = field.key.lowercased()
        if editingKey == field.key, editingTagIndex == nil, kind != .tags, kind != .date {
            inlineTextField
        } else {
            switch kind {
            case .tags:
                tagsValue(for: field)
            case .url:
                HStack(spacing: 6) {
                    Button {
                        openURLValue(field.value)
                    } label: {
                        Text(Self.unquoted(field.value))
                            .foregroundStyle(NotoTheme.accent)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .buttonStyle(.plain)
                    Button {
                        beginInlineEdit(field)
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(NotoTheme.faint)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("edit_url_button")
                }
            case .date, .text:
                if lowerKey.contains("status") {
                    HStack(spacing: 7) {
                        Circle().fill(statusColor(for: field.value)).frame(width: 9, height: 9)
                        Text(Self.unquoted(field.value)).foregroundStyle(NotoTheme.muted).lineLimit(1)
                    }
                } else {
                    Text(displayValue(for: field, kind: kind))
                        .foregroundStyle(NotoTheme.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }

    /// Inline editing field — right-aligned, accent caret, commits on return or focus loss.
    private var inlineTextField: some View {
        TextField("", text: $draft)
            .focused($fieldFocused)
            .multilineTextAlignment(.trailing)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .foregroundStyle(NotoTheme.head)
            .tint(NotoTheme.accent)
            .onSubmit { commitInlineEdit() }
            .onChange(of: fieldFocused) { _, focused in
                if !focused { commitInlineEdit() }
            }
            .onAppear { fieldFocused = true }
            .accessibilityIdentifier("property_inline_field")
    }

    private func tagsValue(for field: EditableFrontmatterField) -> some View {
        let tags = NotePropertyClassifier.parseTags(field.value)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(Array(tags.enumerated()), id: \.offset) { index, tag in
                    if editingKey == field.key, editingTagIndex == index {
                        inlineTagField
                    } else {
                        Button {
                            beginTagEdit(key: field.key, index: index, tags: tags)
                        } label: {
                            TagChip(text: tag)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if !(editingKey == field.key && editingTagIndex == tags.count) {
                    Button {
                        beginTagEdit(key: field.key, index: tags.count, tags: tags)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(NotoTheme.muted)
                            .frame(width: 24, height: 24)
                            .background(NotoTheme.chipFill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("add_tag_button")
                } else {
                    inlineTagField
                }
            }
        }
        .mask(LinearGradient(
            stops: [.init(color: .black, location: 0.88), .init(color: .clear, location: 1)],
            startPoint: .leading, endPoint: .trailing
        ))
    }

    /// Inline chip-sized editor for a single tag member.
    private var inlineTagField: some View {
        TextField("tag", text: $draft)
            .focused($fieldFocused)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .font(.system(size: 13.5))
            .foregroundStyle(NotoTheme.head)
            .tint(NotoTheme.accent)
            .frame(minWidth: 44)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(NotoTheme.chipFill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .fixedSize()
            .onSubmit { commitInlineEdit() }
            .onChange(of: fieldFocused) { _, focused in
                if !focused { commitInlineEdit() }
            }
            .onAppear { fieldFocused = true }
            .accessibilityIdentifier("property_inline_tag_field")
    }

    private var addPropertyRow: some View {
        Menu {
            ForEach(PropertyType.allCases, id: \.self) { type in
                Button {
                    beginAdding(type)
                } label: {
                    Label(type.label, systemImage: type.glyph)
                }
                .accessibilityIdentifier("property_type_\(type.rawValue)")
            }
        } label: {
            PropertyRowLayout(glyph: "plus", label: "Add property", accent: true, showsChevron: false) {
                EmptyView()
            }
        }
        .accessibilityIdentifier("add_property_button")
    }

    // MARK: Inline editing — begin / commit

    private func beginInlineEdit(_ field: EditableFrontmatterField) {
        commitInlineEdit() // commit any other field first
        editingTagIndex = nil
        editingKey = field.key
        draft = Self.unquoted(field.value)
    }

    /// Strips a single pair of surrounding quotes for display/editing. Frontmatter
    /// values are stored quoted (e.g. `"Tuki"`); we show/edit them bare.
    static func unquoted(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { return trimmed }
        let isDoubleQuoted = trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"")
        let isSingleQuoted = trimmed.hasPrefix("'") && trimmed.hasSuffix("'")
        return (isDoubleQuoted || isSingleQuoted) ? String(trimmed.dropFirst().dropLast()) : trimmed
    }

    private func beginTagEdit(key: String, index: Int, tags: [String]) {
        commitInlineEdit()
        editingKey = key
        editingTagIndex = index
        editingTagMembers = tags
        draft = index < tags.count ? tags[index] : ""
    }

    private func commitInlineEdit() {
        guard let key = editingKey else { return }
        if let idx = editingTagIndex {
            var members = editingTagMembers
            let trimmed = draft.trimmingCharacters(in: .whitespaces)
            if idx < members.count {
                if trimmed.isEmpty { members.remove(at: idx) } else { members[idx] = trimmed }
            } else if !trimmed.isEmpty {
                members.append(trimmed)
            }
            updateField(key, NotePropertyClassifier.serializeTags(members))
        } else {
            updateField(key, draft)
        }
        editingKey = nil
        editingTagIndex = nil
    }

    // MARK: Date editing (picker overlay)

    private func beginDateEdit(_ field: EditableFrontmatterField) {
        commitInlineEdit()
        let parsed = NotePropertyClassifier.date(from: field.value) ?? Date(timeIntervalSince1970: 0)
        editingDateKey = field.key
        editingDate = parsed
        editingDateOnly = !field.value.contains("T")
    }

    private var dateEditorOverlay: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { editingDateKey = nil }
            VStack(spacing: 12) {
                DatePicker(
                    "",
                    selection: $editingDate,
                    displayedComponents: editingDateOnly ? [.date] : [.date, .hourAndMinute]
                )
                .datePickerStyle(.graphical)
                .labelsHidden()
                .tint(NotoTheme.accent)
                HStack {
                    Button("Cancel") { editingDateKey = nil }
                        .foregroundStyle(NotoTheme.muted)
                    Spacer()
                    Button("Save") { commitDateEdit() }
                        .fontWeight(.semibold)
                        .foregroundStyle(NotoTheme.accent)
                }
                .padding(.horizontal, 4)
            }
            .padding(16)
            .background(NotoTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 24)
            .accessibilityIdentifier("property_date_editor")
        }
    }

    private func commitDateEdit() {
        guard let key = editingDateKey else { return }
        updateField(key, NotePropertyClassifier.dateString(from: editingDate, dateOnly: editingDateOnly))
        editingDateKey = nil
    }

    // MARK: Add property

    private func beginAdding(_ type: PropertyType) {
        commitInlineEdit()
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

    // MARK: Write-back

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
        if editingKey == key { editingKey = nil; editingTagIndex = nil }
        session.applyExternalContentEdit(
            EditableFrontmatterDocument.deletingField(key: key, in: session.content)
        )
    }

    // MARK: Derived values

    private var folderName: String {
        let parent = session.note.fileURL.deletingLastPathComponent().standardizedFileURL
        let root = session.store.vaultRootURL.standardizedFileURL
        if parent == root {
            return root.lastPathComponent.isEmpty ? "Vault" : root.lastPathComponent
        }
        return parent.lastPathComponent
    }

    private func displayValue(for field: EditableFrontmatterField, kind: NotePropertyKind) -> String {
        if kind == .date, let date = NotePropertyClassifier.date(from: field.value) {
            return field.value.contains("T")
                ? Self.absoluteDateTimeFormatter.string(from: date)
                : Self.absoluteFormatter.string(from: date)
        }
        let value = Self.unquoted(field.value)
        return value.isEmpty ? "Empty" : value
    }

    private func formattedDate(forKey key: String, absolute: Bool) -> String? {
        let raw = fields.first { $0.key.lowercased() == key }?.value
        if let raw, let date = NotePropertyClassifier.date(from: raw) {
            return absolute ? Self.absoluteFormatter.string(from: date) : NotoRelativeDate.compactString(from: date)
        }
        if key == "modified" {
            return NotoRelativeDate.compactString(from: session.note.modifiedDate)
        }
        return nil
    }

    private func glyph(forKey key: String, kind: NotePropertyKind) -> String {
        if key == "folder" { return "folder" }
        if key == "created" { return "calendar" }
        if key == "modified" || key == "updated" { return "clock" }
        if key.contains("status") { return "smallcircle.filled.circle" }
        if key.contains("author") || key.contains("person") || key == "by" { return "person" }
        switch kind {
        case .tags: return "tag"
        case .url: return "link"
        case .date: return "calendar"
        case .text: return "textformat"
        }
    }

    private func statusColor(for label: String) -> Color {
        switch label.lowercased() {
        case "done", "complete", "completed", "published": return Color(.sRGB, red: 0.20, green: 0.78, blue: 0.35)
        case "drafting", "draft", "in progress", "wip": return NotoTheme.statusAmber
        case "blocked", "archived": return NotoTheme.destructive
        default: return NotoTheme.statusAmber
        }
    }

    private static let absoluteFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f
    }()

    private static let absoluteDateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy · h:mm a"
        return f
    }()
}

/// Property type for the Add-property pull-down menu (HIG pull-down).
private enum PropertyType: String, CaseIterable {
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

/// One inset-grouped property row: leading glyph (22 box, 13 gap) · label (16) ·
/// trailing value · optional chevron. Mirrors `Row` in `noto-properties-hig.jsx`.
private struct PropertyRowLayout<Value: View>: View {
    let glyph: String
    let label: String
    var accent = false
    var showsChevron: Bool
    @ViewBuilder var value: () -> Value

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: glyph)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(accent ? NotoTheme.accent : NotoTheme.muted)
                .frame(width: 22)
            Text(label)
                .font(.system(size: 16))
                .foregroundStyle(accent ? NotoTheme.accent : NotoTheme.head)
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 8)
            value()
                .font(.system(size: 16))
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(NotoTheme.faint)
            }
        }
        .frame(minHeight: 44)
    }
}

/// Tag chip — fill `rgba(118,118,128,0.24)`, 24pt tall, radius 7, label 13.5.
struct TagChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13.5))
            .foregroundStyle(NotoTheme.head)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(NotoTheme.chipFill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}
#endif
