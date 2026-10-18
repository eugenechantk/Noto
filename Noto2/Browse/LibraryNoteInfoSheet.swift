import NotoVault
import SwiftUI

/// A staged metadata editor: Close discards edits; Save commits through the existing session.
struct LibraryNoteInfoSheet: View {
    let session: NoteEditorSession
    let count: WordCounter.Count
    let onClose: () -> Void
    let onMoveFolder: () -> Void
    @State private var draft: String
    @State private var addingProperty = false
    @State private var propertyKey = ""
    @State private var propertyValue = ""
    @State private var editingTags: String?
    @State private var tagValue = ""

    init(session: NoteEditorSession, count: WordCounter.Count, onClose: @escaping () -> Void, onMoveFolder: @escaping () -> Void) {
        self.session = session
        self.count = count
        self.onClose = onClose
        self.onMoveFolder = onMoveFolder
        _draft = State(initialValue: session.latestEditorText.isEmpty ? session.content : session.latestEditorText)
    }

    private var fields: [EditableFrontmatterField] { EditableFrontmatterDocument(markdown: draft)?.fields ?? [] }
    private var customFields: [EditableFrontmatterField] { fields.filter { !["id", "created", "modified", "updated", "pinned"].contains($0.key.lowercased()) } }
    private var folderName: String {
        let relative = session.store.vaultRelativePath(for: session.note.fileURL) ?? session.note.fileURL.lastPathComponent
        let path = (relative as NSString).deletingLastPathComponent
        return path.isEmpty ? "Library" : path.replacingOccurrences(of: "/", with: " › ")
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button(action: onMoveFolder) {
                        HStack {
                            Text("Folder").foregroundStyle(NotoTheme.ink)
                            Spacer()
                            Text(folderName).foregroundStyle(NotoTheme.muted).lineLimit(1)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(NotoTheme.faint)
                        }
                    }.accessibilityIdentifier("property_row_folder")
                    metadataRow("Created", value: dateValue("created"))
                    metadataRow("Modified", value: dateValue("modified"))
                    metadataRow("Length", value: "\(count.words.formatted()) words · \(count.characters.formatted()) characters")
                }.listRowBackground(NotoTheme.card)
                Section {
                    ForEach(customFields) { field in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(field.key).foregroundStyle(NotoTheme.ink).frame(width: 76, alignment: .leading)
                            if NotePropertyClassifier.kind(key: field.key, value: field.value) == .tags {
                                tags(field)
                            } else {
                                TextField("Empty", text: Binding(get: {
                                    (EditableFrontmatterDocument(markdown: draft)?.fields.first { $0.key == field.key })?.value ?? ""
                                }, set: { value in draft = EditableFrontmatterDocument.updatingField(key: field.key, value: value, in: draft) }))
                                .foregroundStyle(NotoTheme.muted)
                                .textInputAutocapitalization(.never)
                                .accessibilityIdentifier("noteInfoProperty_\(field.key)")
                            }
                        }
                        .swipeActions { Button("Delete", role: .destructive) { draft = EditableFrontmatterDocument.deletingField(key: field.key, in: draft) } }
                    }
                    Button("Add property", systemImage: "plus") { addingProperty = true }
                        .foregroundStyle(NotoTheme.accentText).accessibilityIdentifier("noteInfoAddProperty")
                } header: { LibrarySectionHeading("Properties") }
                .listRowBackground(NotoTheme.card)
                HStack(spacing: 6) {
                    Image(systemName: "doc").frame(width: 14, height: 14).accessibilityHidden(true)
                    Text(session.note.fileURL.lastPathComponent)
                }
                .font(.system(size: 13)).foregroundStyle(NotoTheme.muted)
                .frame(maxWidth: .infinity).listRowBackground(Color.clear).listRowSeparator(.hidden)
            }
            .modifier(LibraryListStyle())
            .navigationTitle("Note info").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .close, action: onClose)
                        .accessibilityLabel("Cancel").accessibilityIdentifier("properties_close_button")
                }
            }
            .modifier(LibrarySheetAction(title: "Save", identifier: "noteInfoSave") {
                session.applyExternalContentEdit(draft)
                onClose()
            })
        }
        .accessibilityIdentifier("properties_sheet")
        .alert("Add property", isPresented: $addingProperty) {
            TextField("Name", text: $propertyKey).textInputAutocapitalization(.never)
            TextField("Value", text: $propertyValue)
            Button("Cancel", role: .cancel) { propertyKey = ""; propertyValue = "" }
            Button("Add") {
                if let input = EditableFrontmatterDocument.parsedFieldInput(key: propertyKey, value: propertyValue),
                   !["id", "created", "modified", "updated", "pinned"].contains(input.key.lowercased()) {
                    draft = EditableFrontmatterDocument.updatingField(key: input.key, value: input.value, in: draft)
                }
                propertyKey = ""; propertyValue = ""
            }
        }
        .alert("Edit tags", isPresented: Binding(get: { editingTags != nil }, set: { if !$0 { editingTags = nil } })) {
            TextField("Tags separated by commas", text: $tagValue).textInputAutocapitalization(.never)
            Button("Cancel", role: .cancel) { editingTags = nil }
            Button("Done") {
                if let key = editingTags {
                    let value = NotePropertyClassifier.serializeTags(NotePropertyClassifier.parseTags(tagValue))
                    draft = EditableFrontmatterDocument.updatingField(key: key, value: value, in: draft)
                }
                editingTags = nil
            }
        }
    }

    private func metadataRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(NotoTheme.ink)
            Spacer()
            Text(value).foregroundStyle(NotoTheme.muted).font(.subheadline).multilineTextAlignment(.trailing)
        }.accessibilityIdentifier("noteInfo_\(label.lowercased())")
    }

    private func tags(_ field: EditableFrontmatterField) -> some View {
        Button {
            editingTags = field.key
            tagValue = NotePropertyClassifier.parseTags(field.value).joined(separator: ", ")
        } label: {
            HStack(spacing: 6) {
                ForEach(NotePropertyClassifier.parseTags(field.value), id: \.self) { tag in
                    Text("#\(tag)").font(.system(size: 13, weight: .semibold)).foregroundStyle(NotoTheme.ink)
                        .padding(.horizontal, 10).frame(minHeight: 26)
                        .background(NotoTheme.secondaryFill, in: RoundedRectangle(cornerRadius: 8))
                }
                Image(systemName: "plus").font(.system(size: 13)).foregroundStyle(NotoTheme.muted)
                    .frame(width: 26, height: 26).background(NotoTheme.secondaryFill, in: Circle())
            }
        }.accessibilityLabel("Edit tags").accessibilityIdentifier("noteInfoTags")
    }

    private func dateValue(_ key: String) -> String {
        let value = fields.first { $0.key.lowercased() == key }?.value
        let date = value.flatMap(NotePropertyClassifier.date(from:)) ?? (key == "modified" ? session.note.modifiedDate : nil)
        return date?.formatted(date: .abbreviated, time: key == "created" ? .omitted : .shortened) ?? "—"
    }
}
