import NotoLinkPreview
import NotoShareCapture
import SwiftUI
import UIKit

@MainActor
@Observable
final class ShareCaptureModel {
    enum State: Equatable {
        case loading, composing, saving, saved
        case failure(String)
    }

    var state = State.loading
    var draft: ShareCaptureDraft?
    var preview: ShareLinkPreviewModel?
    var isFromSafari = false
    var saveError: String?
    var isSaved: Bool { state == .saved }
}

/// The extension remains in the host's original sheet through composition,
/// durable save, and confirmation. Closing the composer saves nothing.
struct ShareCaptureSheet: View {
    @Bindable var model: ShareCaptureModel
    let onSave: () -> Void
    let onClose: () -> Void

    @FocusState private var thoughtFocused: Bool

    var body: some View {
        NavigationStack {
            Group {
                switch model.state {
                case .loading:
                    ProgressView("Loading link…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityIdentifier("shareCaptureLoading")
                case .composing, .saving:
                    composer
                case .saved:
                    saved
                case .failure(let message):
                    ContentUnavailableView("Couldn't capture link", systemImage: "link",
                                           description: Text(message))
                        .accessibilityIdentifier("shareCaptureError")
                }
            }
            .background(NotoTheme.sheet.ignoresSafeArea())
            .navigationTitle("Noto 2")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !model.isSaved {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(role: .close, action: onClose)
                            .tint(NotoTheme.ink)
                            .accessibilityLabel("Cancel, save nothing")
                            .accessibilityIdentifier("shareCaptureCancelButton")
                    }
                }
            }
            .safeAreaBar(edge: .bottom) {
                bottomAction
            }
        }
        .tint(NotoTheme.accent)
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("shareCaptureSheet")
        .onChange(of: model.state) { _, state in
            thoughtFocused = state == .composing
        }
        .onAppear { thoughtFocused = model.state == .composing }
    }

    private var composer: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Label(model.isFromSafari ? "From Safari · goes to Inbox" : "Goes to Inbox", systemImage: "tray")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("shareCaptureDestination")

                TextField("Add a thought…", text: Binding(
                    get: { model.draft?.thought ?? "" },
                    set: { model.draft?.thought = $0 }
                ), axis: .vertical)
                .font(.body)
                .lineLimit(1...8)
                .focused($thoughtFocused)
                .disabled(model.state == .saving)
                .accessibilityLabel("Thought about this link")
                .accessibilityIdentifier("shareCaptureThoughtField")

                if let preview = model.preview {
                    ShareCaptureLinkCard(content: preview.content, compact: false)
                        .accessibilityIdentifier("shareCaptureLinkCard")
                }

                if let error = model.saveError {
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("shareCaptureSaveError")
                }
            }
            .frame(maxWidth: 540, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 22)
            .padding(.top, 16)
            .padding(.bottom, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .accessibilityIdentifier("shareCaptureComposer")
    }

    private var saved: some View {
        ScrollView {
            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundStyle(NotoTheme.onAccent)
                        .frame(width: 64, height: 64)
                        .background(NotoTheme.accent, in: Circle())
                        .accessibilityHidden(true)
                    Text("Saved to Inbox")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(NotoTheme.ink)
                        .accessibilityIdentifier("shareCaptureSavedTitle")
                    Text("You'll file it the next time you open Noto 2.")
                        .font(.subheadline)
                        .foregroundStyle(NotoTheme.muted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 280)
                }
                .padding(.top, 72)

                VStack(alignment: .leading, spacing: 10) {
                    if let thought = model.draft?.thought.trimmingCharacters(in: .whitespacesAndNewlines), !thought.isEmpty {
                        Text(thought)
                            .font(.subheadline)
                            .foregroundStyle(NotoTheme.ink)
                            .lineLimit(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("shareCaptureSavedThought")
                    }
                    if let preview = model.preview {
                        ShareCaptureLinkCard(content: preview.content, compact: true)
                            .accessibilityIdentifier("shareCaptureSavedLinkCard")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(NotoTheme.card, in: RoundedRectangle(cornerRadius: 22))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("shareCaptureSavedCard")
                .padding(.top, 28)
            }
            .frame(maxWidth: 540)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
        .accessibilityIdentifier("shareCaptureSavedState")
    }

    @ViewBuilder
    private var bottomAction: some View {
        if model.state == .composing || model.state == .saving {
            Button(action: onSave) {
                Label(model.state == .saving ? "Saving…" : "Save to Inbox", systemImage: "tray.and.arrow.down")
                    .font(.headline)
                    .foregroundStyle(NotoTheme.onAccent)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .tint(NotoTheme.accent)
            .disabled(model.state == .saving)
            .accessibilityIdentifier("shareCaptureSaveButton")
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        } else if model.isSaved {
            VStack(spacing: 10) {
                Button(action: onClose) {
                    Text("Done")
                        .font(.headline)
                        .foregroundStyle(NotoTheme.ink)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                .accessibilityIdentifier("shareCaptureDoneButton")
                Text("Closes on its own in a moment")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
}

/// Shares the preview service and content model with the editor. The sheet
/// uses the canvas's compact geometry instead of the editor's fixed height.
private struct ShareCaptureLinkCard: View {
    let content: LinkPreviewCardContent
    let compact: Bool

    var body: some View {
        Group {
            if compact {
                HStack(spacing: 10) {
                    Group {
                        if let data = content.imageData, let image = UIImage(data: data) {
                            Image(uiImage: image).resizable().scaledToFill()
                        } else {
                            Image(systemName: "link")
                                .font(.system(size: 14))
                                .foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .frame(width: 40, height: 40)
                    .background(NotoTheme.secondaryFill)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    details
                }
                .padding(6)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Group {
                        if let data = content.imageData, let image = UIImage(data: data) {
                            Image(uiImage: image).resizable().scaledToFill()
                        } else {
                            Image(systemName: "photo")
                                .font(.title3)
                                .foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .frame(height: 110)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    details.padding(14)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(compact ? NotoTheme.subdued : NotoTheme.secondaryFill)
        .clipShape(RoundedRectangle(cornerRadius: compact ? 14 : 18))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(content.title)
        .accessibilityValue(content.host)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(content.title)
                .font(compact ? .system(size: 14, weight: .semibold) : .subheadline.weight(.semibold))
                .foregroundStyle(NotoTheme.ink)
                .lineLimit(compact ? 1 : 2)
            Text(content.host)
                .font(.caption)
                .foregroundStyle(NotoTheme.muted)
                .lineLimit(1)
        }
    }
}
