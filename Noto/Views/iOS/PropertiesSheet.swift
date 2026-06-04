#if os(iOS)
import SwiftUI
import NotoVault

/// v2 Properties sheet (`NotoPropertyList` / `noto-properties-hig.jsx`) presented over the
/// editor. Renders the note's YAML frontmatter as an inset-grouped iOS list and edits it
/// through `EditableFrontmatterDocument`, which preserves every key (no data loss).
struct PropertiesSheet: View {
    @Bindable var session: NoteEditorSession
    var onClose: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var editingKey: String?
    @State private var editingValue = ""
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
        VStack(spacing: 0) {
            header
            propertyList
        }
        .background(NotoTheme.groupedBackground.ignoresSafeArea())
        .accessibilityIdentifier("properties_sheet")
        // NOTE: Editing (add/edit/delete) is intentionally disabled this pass.
        // The write-back path (`apply`) updates `session.content` correctly — the list
        // reflects edits in-memory — but the open editor's UITextView owns the persisted
        // text and does not adopt external content changes while this sheet covers it, so
        // edits never reach disk. Re-enable once the editor pass adds an authoritative
        // session write-back that updates the text view. The edit helpers below are kept
        // ready for that. See `.codex/feature/ios-properties-redesign.md`.
    }

    // MARK: Header

    private var header: some View {
        ZStack {
            Text("Properties")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(NotoTheme.head)
            HStack {
                SheetCircleButton(kind: .close) {
                    onClose()
                    dismiss()
                }
                .accessibilityIdentifier("properties_close_button")
                .accessibilityLabel("Close")
                Spacer()
                SheetCircleButton(kind: .confirm) {
                    onClose()
                    dismiss()
                }
                .accessibilityIdentifier("properties_confirm_button")
                .accessibilityLabel("Done")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
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
                }
            }
            .listRowBackground(NotoTheme.card)
            .listRowSeparatorTint(NotoTheme.separator)
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(NotoTheme.groupedBackground)
        .environment(\.defaultMinListRowHeight, 44)
        .tint(NotoTheme.accent)
    }

    // MARK: Rows

    private var folderRow: some View {
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
        let key = field.key.lowercased()
        PropertyRowLayout(glyph: glyph(forKey: key), label: field.key.capitalized, showsChevron: key.contains("status")) {
            switch rendering(for: field) {
            case .tags(let tags):
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(Array(tags.enumerated()), id: \.offset) { _, tag in
                            TagChip(text: tag)
                        }
                    }
                }
                .mask(LinearGradient(
                    stops: [.init(color: .black, location: 0.88), .init(color: .clear, location: 1)],
                    startPoint: .leading, endPoint: .trailing
                ))
            case .status(let label):
                HStack(spacing: 7) {
                    Circle()
                        .fill(statusColor(for: label))
                        .frame(width: 9, height: 9)
                    Text(label)
                        .foregroundStyle(NotoTheme.muted)
                        .lineLimit(1)
                }
            case .plain(let text):
                Text(text)
                    .foregroundStyle(NotoTheme.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .accessibilityIdentifier("property_row_\(key)")
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
        .accessibilityValue("property_type_menu")
    }

    // MARK: Editing

    private var editingAlertBinding: Binding<Bool> {
        Binding(get: { editingKey != nil }, set: { if !$0 { editingKey = nil } })
    }

    private func beginEditing(_ field: EditableFrontmatterField) {
        editingKey = field.key
        editingValue = field.value
    }

    private func commitEdit() {
        guard let key = editingKey else { return }
        apply(EditableFrontmatterDocument.updatingField(key: key, value: editingValue, in: session.content))
        editingKey = nil
    }

    private func beginAdding(_ type: PropertyType) {
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
        apply(EditableFrontmatterDocument.addingField(key: parsed.key, value: parsed.value, in: session.content))
        resetAddState()
    }

    private func resetAddState() {
        isAddingProperty = false
        newPropertyKey = ""
        newPropertyValue = ""
    }

    private func deleteField(_ key: String) {
        apply(EditableFrontmatterDocument.deletingField(key: key, in: session.content))
    }

    /// Apply a new markdown string through the same path the TextKit editor uses on every
    /// keystroke — updates the bound text view and runs metadata + autosave.
    private func apply(_ newMarkdown: String) {
        session.content = newMarkdown
        session.handleEditorChange(newMarkdown)
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

    private func formattedDate(forKey key: String, absolute: Bool) -> String? {
        let raw = fields.first { $0.key.lowercased() == key }?.value
        if let raw, let date = Self.isoFormatter.date(from: raw) {
            return absolute ? Self.absoluteFormatter.string(from: date) : NotoRelativeDate.compactString(from: date)
        }
        // Fallback for Modified: use the note's known modified date.
        if key == "modified" {
            return NotoRelativeDate.compactString(from: session.note.modifiedDate)
        }
        return nil
    }

    private enum FieldRendering {
        case tags([String])
        case status(String)
        case plain(String)
    }

    private func rendering(for field: EditableFrontmatterField) -> FieldRendering {
        let key = field.key.lowercased()
        let value = field.value.trimmingCharacters(in: .whitespaces)
        if key == "tags" || key == "keywords" {
            return .tags(Self.parseTags(value))
        }
        if key.contains("status") {
            return .status(value.isEmpty ? "—" : value)
        }
        return .plain(value.isEmpty ? "Empty" : value)
    }

    private static func parseTags(_ value: String) -> [String] {
        var trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("["), trimmed.hasSuffix("]") {
            trimmed = String(trimmed.dropFirst().dropLast())
        }
        // Handle both inline (`a, b`) and YAML block lists (`- a\n- b`).
        let separators = CharacterSet(charactersIn: ",\n")
        return trimmed
            .components(separatedBy: separators)
            .map {
                var item = $0.trimmingCharacters(in: .whitespaces)
                if item.hasPrefix("- ") { item = String(item.dropFirst(2)) }
                else if item.hasPrefix("-") { item = String(item.dropFirst()) }
                return item.trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
            }
            .filter { !$0.isEmpty }
    }

    private func glyph(forKey key: String) -> String {
        if key == "folder" { return "folder" }
        if key == "created" { return "calendar" }
        if key == "modified" || key == "updated" { return "clock" }
        if key == "tags" || key.contains("tag") || key == "keywords" { return "tag" }
        if key.contains("url") || key.contains("link") || key.contains("source") { return "link" }
        if key.contains("status") { return "smallcircle.filled.circle" }
        if key.contains("author") || key.contains("person") || key == "by" { return "person" }
        if key.contains("date") || key.contains("published") { return "calendar" }
        return "textformat"
    }

    private func statusColor(for label: String) -> Color {
        switch label.lowercased() {
        case "done", "complete", "completed", "published": return Color(.sRGB, red: 0.20, green: 0.78, blue: 0.35)
        case "drafting", "draft", "in progress", "wip": return NotoTheme.statusAmber
        case "blocked", "archived": return NotoTheme.destructive
        default: return NotoTheme.statusAmber
        }
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let absoluteFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
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
