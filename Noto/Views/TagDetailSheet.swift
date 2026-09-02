import SwiftUI
import NotoTags

struct TagDetailSheet: View {
    let tagDefinition: TagDefinition
    let tagController: TagController

    @Environment(\.dismiss) private var dismiss
    @State private var template: String
    @State private var showDeleteConfirmation = false

    init(tagDefinition: TagDefinition, tagController: TagController) {
        self.tagDefinition = tagDefinition
        self.tagController = tagController
        _template = State(initialValue: tagDefinition.template)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Tag name")
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                        Text("#\(tagDefinition.name.rawValue)")
                            .font(.title3)
                            .fontWeight(.semibold)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Content template")
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                        TextEditor(text: $template)
                            .frame(minHeight: 180)
                            .padding(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(AppTheme.separator, lineWidth: 1)
                            )
                            .accessibilityIdentifier("tag_template_editor")
                        Text("Added to the end of a note when this tag is added.")
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                    }

                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        HStack {
                            Spacer()
                            Text("Delete Tag")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .foregroundStyle(.white)
                    .accessibilityIdentifier("delete_tag_button")
                    .padding(.top, 8)
                }
                .padding(16)
            }
        }
        .background(AppTheme.background)
        .foregroundStyle(AppTheme.primaryText)
        .tint(Color(hex: 0xFF6A2E))
        .scrollContentBackground(.hidden)
        .confirmationDialog("Delete Tag", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                deleteTag()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Deleting this tag only removes its definition. Existing notes that use this tag are unchanged.")
        }
        .accessibilityIdentifier("tag_detail_sheet")
    }

    private var header: some View {
        ZStack {
            Text("#\(tagDefinition.name.rawValue)")
                .font(.headline)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
            HStack {
                SheetCircleButton(kind: .close) {
                    dismiss()
                }
                .accessibilityIdentifier("tag_detail_cancel_button")
                Spacer()
                SheetCircleButton(kind: .confirm) {
                    saveTemplate()
                }
                .accessibilityIdentifier("tag_detail_save_button")
            }
            .padding(.horizontal, 12)
        }
        .padding(.top, 10)
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    private func saveTemplate() {
        tagController.save(
            TagDefinition(
                name: tagDefinition.name,
                template: template,
                createdAt: tagDefinition.createdAt,
                modifiedAt: Date()
            )
        )
        dismiss()
    }

    private func deleteTag() {
        tagController.remove(tagDefinition.name)
        dismiss()
    }
}
