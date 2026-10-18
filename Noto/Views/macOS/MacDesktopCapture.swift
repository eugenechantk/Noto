#if os(macOS)
import AppKit
import SwiftUI
import NotoVault

struct MacDesktopCapture: View {
    @Bindable var model: MacDesktopModel
    var isWide: Bool
    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.width < 760
            let wide = isWide
            let top: CGFloat = compact ? 16 : wide ? 40 : 80
            let height = min(compact ? 640.0 : wide ? 520.0 : 600.0, max(240, geometry.size.height - top - 110))
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(model.draft.isEmpty ? "New capture" : Date().formatted(date: .omitted, time: .shortened) + " · \(WordCounter().count(in: model.draft).words) words")
                        Spacer()
                        Label("Goes to Inbox", systemImage: "tray")
                    }.font(.system(size: 12)).foregroundStyle(MacDesktopStyle.secondary)
                    ZStack(alignment: .topLeading) {
                        if model.draft.isEmpty { Text("What's on your mind?").foregroundStyle(MacDesktopStyle.secondary).padding(.top, 3).padding(.leading, 1).allowsHitTesting(false) }
                        MacDesktopCaptureInput(text: $model.draft)
                    }.frame(maxHeight: .infinity)
                    Text("Right-click for more").font(.system(size: 12)).foregroundStyle(MacDesktopStyle.secondary).frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(.horizontal, compact ? 24 : 30).padding(.top, 26).padding(.bottom, 18)
                .frame(maxWidth: 720).frame(height: height)
                .background(Color(red: 27/255, green: 31/255, blue: 39/255), in: RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.08)))
                .shadow(color: .black.opacity(0.35), radius: 25, y: 20)
                .padding(.horizontal, compact ? 15 : 32).padding(.top, top)
                .contextMenu {
                    Button("Add to Note…") { model.paletteUsesDraft = true; model.palette = .append }.disabled(model.draft.isEmpty)
                    Button("New Note…") { model.paletteUsesDraft = true; model.palette = .create }.disabled(model.draft.isEmpty)
                    Button("Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(model.draft, forType: .string) }
                }
                .accessibilityElement(children: .contain).accessibilityIdentifier("macCaptureCard")
                HStack(spacing: 24) {
                    Text("⌘↩  File to Inbox")
                    Text("⌘⌫  Discard")
                    Text("⌘Z  Undo")
                }.font(.system(size: 11)).foregroundStyle(MacDesktopStyle.secondary).padding(.top, 22)
                Spacer(minLength: 0)
                HStack { Text("inbox/ · filed captures wait in the Inbox"); Spacer(); Text("\(model.filedToday) filed today") }
                    .font(.system(size: 11)).foregroundStyle(MacDesktopStyle.secondary).padding(.horizontal, 16).frame(height: 30)
                    .overlay(alignment: .top) { MacDesktopStyle.separator.frame(height: 1) }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .topLeading) {
                    if !compact && !wide { MacDesktopDestinationMenu(model: model, isListTitle: true).frame(width: 140).padding(.leading, 10) }
                }
        }
        .accessibilityElement(children: .contain).accessibilityIdentifier("macCaptureScreen")
    }
}

private struct MacDesktopCaptureInput: NSViewRepresentable {
    @Binding var text: String
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        let view = Input(frame: .zero)
        view.isRichText = false; view.isEditable = true; view.isSelectable = true; view.allowsUndo = true
        view.drawsBackground = false; view.font = .systemFont(ofSize: 16); view.textColor = .white
        view.textContainerInset = NSSize(width: 0, height: 3)
        view.textContainer?.lineFragmentPadding = 1
        view.isVerticallyResizable = true; view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]; view.textContainer?.widthTracksTextView = true
        view.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 6
        view.defaultParagraphStyle = paragraph
        view.string = text; view.delegate = context.coordinator
        view.setAccessibilityIdentifier("macCaptureText"); view.setAccessibilityLabel("Capture text")
        scroll.documentView = view
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let view = scroll.documentView as? NSTextView, view.string != text else { return }
        view.string = text
        view.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        view.undoManager?.removeAllActions()
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MacDesktopCaptureInput
        init(_ parent: MacDesktopCaptureInput) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            if let view = notification.object as? NSTextView { parent.text = view.string }
        }
    }
    final class Input: NSTextView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window else { return }
                window.makeFirstResponder(self)
            }
        }
    }
}

struct MacDesktopInbox: View {
    @Bindable var model: MacDesktopModel
    var narrow: Bool
    var compact: Bool
    var onEdit: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            if let note = model.selectedNote {
                VStack(spacing: narrow ? compact ? 24 : 26 : 20) {
                    if !narrow { action("↑", "New note", .green, "macInboxCreate") { present(.create) } }
                    HStack(spacing: 16) {
                        if !narrow { action("←", "Later", .orange, "macInboxLater") { model.inboxAction("later") }.frame(width: 90) }
                        card.frame(height: compact ? 460 : narrow ? 440 : 420)
                        if !narrow { action("→", "Add to", .blue, "macInboxAppend") { present(.append) }.frame(width: 90) }
                    }
                    if !narrow { action("↓", "Discard", .red, "macInboxDiscard") { model.inboxAction("discard") } }
                    else { arrowKeys }
                }.padding(.horizontal, compact ? 15 : narrow ? 24 : 16).padding(.top, compact ? 40 : narrow ? 64 : 38)
                    .offset(x: narrow ? 0 : -17)
                Spacer(minLength: 20)
                HStack { Text("inbox/" + note.fileURL.lastPathComponent); Spacer(); Text("\(model.processedToday) of \(model.inboxProgressTotal) done today") }
                    .font(.system(size: 11)).foregroundStyle(MacDesktopStyle.secondary).padding(.horizontal, 16).frame(height: 30)
                    .overlay(alignment: .top) { MacDesktopStyle.separator.frame(height: 1) }
            } else {
                ContentUnavailableView("Inbox is clear", systemImage: "tray", description: Text("Your next thought starts in Capture."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity).accessibilityIdentifier("macInboxClear")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MacDesktopKeyboardTarget(onKey: handleKey).frame(width: 0, height: 0))
        .accessibilityElement(children: .contain).accessibilityIdentifier("macInboxScreen")
    }
    private func handleKey(_ key: MacDesktopPaletteKey, _ flags: NSEvent.ModifierFlags) -> Bool {
        let modifiers = flags.intersection([.command, .option, .shift, .control])
        if key == .escape { model.select(.all); return true }
        guard model.palette == nil, model.currentEntry?.isAvailable == true else { return false }
        if modifiers == .option {
            if key == .down { model.nextInbox(); return true }
            if key == .up { model.nextInbox(direction: -1); return true }
            return false
        }
        guard modifiers.isEmpty else { return false }
        switch key {
        case .enter: onEdit()
        case .right: present(.append)
        case .up: present(.create)
        case .left: model.inboxAction("later")
        case .down: model.inboxAction("discard")
        default: return false
        }
        return true
    }
    private var card: some View {
        VStack(alignment: .leading, spacing: 20) {
            if model.currentEntry?.isAvailable == false { ProgressView("Downloading from iCloud…") }
            else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(VaultMarkdown.stripFrontmatter(model.document).components(separatedBy: "\n\n").enumerated()), id: \.offset) { index, paragraph in
                            MacDesktopInboxParagraph(markdown: paragraph.trimmingCharacters(in: .whitespacesAndNewlines), usesWordWrapping: !narrow && index > 0)
                                .padding(.top, paragraphTopSpacing(at: index))
                        }
                    }.font(.system(size: 16)).lineSpacing(6).frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: .infinity)
            }
            HStack(spacing: 20) {
                Button("↩ Edit the text", action: onEdit).buttonStyle(.plain).accessibilityIdentifier("macInboxEdit")
                Text("⌥↓ Next without acting")
                Spacer(minLength: 0)
            }.font(.system(size: 11)).foregroundStyle(MacDesktopStyle.secondary)
        }.padding(.horizontal, compact ? 24 : 30).padding(.vertical, 26).frame(maxWidth: narrow ? 520 : 616)
            .background(Color(red: 27/255, green: 31/255, blue: 39/255), in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.08)))
            .shadow(color: .black.opacity(0.35), radius: 25, y: 20)
            .accessibilityElement(children: .contain).accessibilityIdentifier("macInboxCard")
    }
    private func paragraphTopSpacing(at index: Int) -> CGFloat {
        if index == 0 { return compact ? 0 : 4 }
        return compact ? 18 : index == 1 ? 19 : 16
    }
    private var arrowKeys: some View {
        VStack(spacing: 8) {
            action("↑", "New note", .green, "macInboxCreate") { present(.create) }
            HStack(spacing: 8) {
                action("←", "Later", .orange, "macInboxLater") { model.inboxAction("later") }
                action("↓", "Discard", .red, "macInboxDiscard") { model.inboxAction("discard") }
                action("→", "Add to", .blue, "macInboxAppend") { present(.append) }
            }
        }
    }
    private func action(_ arrow: String, _ title: String, _ color: Color, _ id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(arrow).font(.system(size: 12)).frame(width: 20, height: 20)
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(color.opacity(0.4)))
                Text(title).font(.system(size: 13, weight: .bold))
            }.padding(.leading, 7).padding(.trailing, 12).frame(height: 34)
                .foregroundStyle(color).background(.white.opacity(0.06), in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.1)))
        }.buttonStyle(.plain).accessibilityLabel(title).accessibilityIdentifier(id).disabled(model.currentEntry?.isAvailable != true)
    }
    private func present(_ purpose: MacPalettePurpose) { model.paletteUsesDraft = false; model.palette = purpose }
}
private struct MacDesktopInboxParagraph: View {
    let markdown: String
    var usesWordWrapping = false
    var body: some View {
        if let match = HyperlinkMarkdown.matches(in: markdown).first,
           match.fullRange.length == markdown.utf16.count, case .external(let url) = match.target {
            Link(destination: url) {
                HStack(spacing: 12) {
                    Image(systemName: "link").font(.system(size: 18)).foregroundStyle(MacDesktopStyle.secondary)
                        .frame(width: 52, height: 52).background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(match.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                        Text(url.host() ?? url.absoluteString).font(.system(size: 12)).foregroundStyle(MacDesktopStyle.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }.padding(10).frame(height: 72).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
            }.buttonStyle(.plain)
        } else if usesWordWrapping, let plainText = MacDesktopInboxWrappingText.plainText(from: markdown) {
            MacDesktopInboxWrappingText(text: plainText).frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 2)
        } else {
            Text(.init(markdown)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A read-only text view keeps display and selection in one text layout, with
/// ordinary word wrapping even when the last line contains a single word.
struct MacDesktopInboxWrappingText: NSViewRepresentable {
    let text: String

    static func plainText(from markdown: String) -> String? {
        guard let parsed = try? AttributedString(markdown: markdown, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)),
              String(parsed.characters) == markdown,
              parsed.runs.allSatisfy({ $0.inlinePresentationIntent == nil && $0.link == nil }) else { return nil }
        return markdown
    }

    func makeNSView(context: Context) -> NSTextView {
        let view = NSTextView(frame: .zero)
        view.isEditable = false
        view.isSelectable = true
        view.drawsBackground = false
        view.textContainerInset = .zero
        view.isHorizontallyResizable = false
        view.isVerticallyResizable = true
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = false
        return view
    }

    func updateNSView(_ view: NSTextView, context: Context) {
        if view.string != text { view.textStorage?.setAttributedString(Self.attributedText(text)) }
    }

    static func attributedText(_ text: String) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineBreakStrategy = []
        paragraph.lineSpacing = 6
        return NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 16),
            .foregroundColor: NSColor(srgbRed: 236 / 255, green: 236 / 255, blue: 238 / 255, alpha: 1),
            .paragraphStyle: paragraph
        ])
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView view: NSTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0, let container = view.textContainer, let layout = view.layoutManager else { return nil }
        container.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        return CGSize(width: width, height: ceil(layout.usedRect(for: container).height))
    }
}
#endif
