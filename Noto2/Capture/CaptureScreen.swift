import SwiftUI
import UIKit
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto2", category: "CaptureScreen")

/// The start screen: a Tinder-style card stack over the vault.
/// Swipe **right or up** to file the draft to `inbox/<date>-<sha8>.md`
/// (see `CaptureFilingService`); swipe **left** to discard it. The card pins
/// to the finger, tilts, detaches mid-flick, and the next empty card rises
/// from behind. The outcome line lives in a fixed slot ABOVE the card so
/// nothing shifts. No buttons.
struct CaptureScreen: View {
    let vaultURL: URL?
    /// Opens a just-filed capture in the editor. Capture stays free of the vault
    /// workspace (cold-launch budget), so the owner resolves and routes.
    var onOpenFiledNote: ((URL) -> Void)?

    /// The draft survives app kills — a thought typed on the train should not
    /// vanish because iOS reclaimed the process.
    @AppStorage("noto2.capture.draft") private var draft: String = ""
    /// Bumping the document id forces the editor to reload `draft` even while
    /// the text view is first responder (the editor's update guard otherwise
    /// refuses to replace text under an active keyboard).
    @State private var editorDocumentID = UUID().uuidString
    @State private var isSending = false
    @State private var status: CaptureStatus?
    @State private var errorMessage: String?

    // Card gesture state.
    @State private var cardDrag: CGFloat = 0          // vertical finger travel (≤ 0 upward)
    @State private var cardDragX: CGFloat = 0         // horizontal finger travel
    @State private var flyDirection: FlyDirection?    // set while animating off-screen
    @State private var cardArriving = false           // fresh card entering from below
    @State private var flyDuration: Double = 0.25     // matched to release velocity
    @State private var keyboardVisible = false        // card grows into the smaller space

    private enum FlyDirection {
        case up, right, left
    }

    /// Drag distance at which release commits.
    private static let commitThreshold: CGFloat = 90
    /// Predicted (flick) distance that commits even on a short fast swipe.
    private static let flickThreshold: CGFloat = 240
    /// Velocity (pt/s) that commits regardless of distance.
    private static let commitVelocity: CGFloat = 700
    /// Drag distance past which a still-moving flick detaches mid-gesture.
    private static let autoCommitDistance: CGFloat = 150
    private static let cardCornerRadius: CGFloat = 24

    private var normalizedDraft: String { CaptureFilingService.normalizedBody(draft) }
    private var canSend: Bool { vaultURL != nil && !isSending && !normalizedDraft.isEmpty }

    /// 0→1 toward the file commit (up or right).
    private var sendProgress: CGFloat {
        if flyDirection == .up || flyDirection == .right { return 1 }
        let up = max(0, -cardDrag / Self.commitThreshold)
        let right = max(0, cardDragX / 120)
        return min(1, max(up, right))
    }
    /// 0→1 toward the discard commit (left).
    private var discardProgress: CGFloat {
        if flyDirection == .left { return 1 }
        return min(1, max(0, -cardDragX / 120))
    }
    /// 0→1 over a longer travel; drives the background card rising into place.
    private var swapProgress: CGFloat {
        if flyDirection != nil { return 1 }
        let travel = max(-cardDrag, abs(cardDragX))
        return min(1, max(0, travel / 280))
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                statusSlot
                Spacer(minLength: 8)
                ZStack {
                    backCard
                    card(in: geometry)
                }
                .frame(height: Self.cardHeight(available: geometry.size.height, keyboardVisible: keyboardVisible))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // The swipe works from the gaps too — matters when a long note
            // makes the editor consume in-card pans for scrolling.
            .contentShape(Rectangle())
            .simultaneousGesture(dragGesture)
        }
        .background(NotoTheme.background.ignoresSafeArea())
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            withAnimation(.easeOut(duration: 0.25)) { keyboardVisible = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeOut(duration: 0.25)) { keyboardVisible = false }
        }
        .alert("Couldn't file the capture", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Fixed slots (no layout shift)

    /// Always-reserved line above the card. A filed capture's line is a button
    /// that opens the note it just wrote; a discard is inert text.
    private var statusSlot: some View {
        Group {
            if let status, let fileURL = status.fileURL {
                Button {
                    onOpenFiledNote?(fileURL)
                } label: {
                    statusContent(status, showsChevron: true)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("captureStatusOpenButton")
                .accessibilityHint("Opens the note you just filed")
            } else {
                statusContent(status, showsChevron: false)
            }
        }
        .font(.footnote)
        .foregroundStyle(status?.isDiscard == true ? AppTheme.mutedText : AppTheme.secondaryText)
        .frame(maxWidth: .infinity, alignment: .center)
        .frame(height: 22)
        .padding(.top, 12)
        .animation(.easeInOut(duration: 0.2), value: status)
        .accessibilityIdentifier("captureStatusLine")
    }

    private func statusContent(_ status: CaptureStatus?, showsChevron: Bool) -> some View {
        HStack(spacing: 6) {
            if let status {
                Image(systemName: status.glyph)
                Text(status.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                }
            }
        }
        .contentShape(Rectangle())
    }

    // MARK: - Card

    /// Roomy but never full-height at rest; with the keyboard up the card grows
    /// into (almost all of) the remaining space, keeping just the status slot
    /// and a small swipe margin.
    private static func cardHeight(available: CGFloat, keyboardVisible: Bool) -> CGFloat {
        if keyboardVisible {
            return max(220, available - 58)
        }
        return min(560, max(280, available * 0.82))
    }

    private func card(in geometry: GeometryProxy) -> some View {
        let shape = RoundedRectangle(cornerRadius: Self.cardCornerRadius, style: .continuous)
        return ZStack {
            shape.fill(NotoTheme.card)

            TextKit2EditorView(
                text: $draft,
                documentID: editorDocumentID,
                autoFocus: true,
                // The iOS editor publishes edits through this callback (the
                // binding is only flushed on resign), so mirror them here or
                // the swipe never has anything to send.
                onTextChange: { newText in draft = newText },
                vaultRootURL: vaultURL,
                keyboardToolbarStyle: .floating,
                backgroundColorOverride: NotoTheme.uiCard,
                // With bounce off, a swipe over a short draft passes through the
                // text view to the container's drag gesture.
                disablesScrollBounce: true,
                // Document insets instead of outer padding, so overflowing text
                // scrolls through the edge zones and the mask below fades it.
                topTextInsetOverride: 28,
                bottomTextInsetOverride: 22,
                // Placeholder lives inside the editor (a UILabel toggled in
                // textViewDidChange) so it vanishes on the first keystroke —
                // a SwiftUI overlay driven by the debounced onTextChange
                // mirror lagged and let typed text overlap it.
                placeholder: "What's on your mind?"
            )
            .accessibilityIdentifier("captureEditor")
            // Sides keep light outer padding (nothing scrolls horizontally);
            // top/bottom fades replace hard clips for overflowing text.
            .padding(.horizontal, 6)
            .mask(
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                        .frame(height: 26)
                    Rectangle().fill(Color.black)
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 20)
                }
            )
            .clipShape(shape)

            // File overlay (orange) — fades in dragging up/right, floods on commit.
            commitOverlay(shape: shape, fill: NotoTheme.accent.opacity(0.92),
                          glyph: "checkmark", label: "Filed", progress: sendProgress)
                .accessibilityIdentifier("captureCommitOverlay")
            // Discard overlay (muted) — fades in dragging left.
            commitOverlay(shape: shape, fill: Color(white: 0.22).opacity(0.94),
                          glyph: "trash", label: "Discarded", progress: discardProgress)
                .accessibilityIdentifier("captureDiscardOverlay")
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        .offset(cardOffset(in: geometry))
        .rotationEffect(.degrees(cardRotation), anchor: .bottom)
        .scaleEffect(cardArriving ? 0.94 : 1)
        .opacity(cardArriving ? 0 : 1)
        .accessibilityIdentifier("captureCard")
    }

    private func commitOverlay(shape: RoundedRectangle, fill: Color, glyph: String, label: String, progress: CGFloat) -> some View {
        shape
            .fill(fill)
            .overlay(alignment: .top) {
                VStack(spacing: 6) {
                    Image(systemName: glyph)
                        .font(.title2.weight(.bold))
                    Text(label)
                        .font(.headline)
                }
                .foregroundStyle(.white)
                .padding(.top, 28)
            }
            .opacity(Double(progress) * 0.95)
            .allowsHitTesting(false)
    }

    private func cardOffset(in geometry: GeometryProxy) -> CGSize {
        switch flyDirection {
        case .up:
            return CGSize(width: cardDragX, height: -(geometry.size.height + 320))
        case .right:
            return CGSize(width: geometry.size.width + 320, height: cardDrag)
        case .left:
            return CGSize(width: -(geometry.size.width + 320), height: cardDrag)
        case nil:
            return CGSize(width: cardDragX, height: cardDrag + (cardArriving ? 44 : 0))
        }
    }

    /// Tinder tilt: mostly from lateral travel, a touch from vertical.
    private var cardRotation: Double {
        switch flyDirection {
        case .up: return -6
        case .right: return 9
        case .left: return -9
        case nil:
            let lateral = Double(cardDragX) / 18
            let vertical = Double(max(-4, cardDrag / 45))
            return min(10, max(-10, lateral + vertical))
        }
    }

    /// The next card in the stack: same shell, empty, slightly shrunk, peeking
    /// below the front card; rises to identity as the front card travels away.
    private var backCard: some View {
        let shape = RoundedRectangle(cornerRadius: Self.cardCornerRadius, style: .continuous)
        let p: CGFloat = swapProgress
        let scale: CGFloat = 0.94 + 0.06 * p
        let drop: CGFloat = 30 * (1 - p)
        // Hidden at rest; fades in with the swipe (eased so it stays invisible
        // on tiny accidental drags) and is fully there by the commit point.
        let fade = Double(min(1, p * 1.4))
        let visibility: Double = cardArriving ? 0 : fade * fade
        return shape
            .fill(NotoTheme.card)
            .overlay(shape.strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
            .scaleEffect(scale)
            .offset(y: drop)
            .opacity(visibility)
            .allowsHitTesting(false)
            .accessibilityIdentifier("captureBackCard")
    }

    // MARK: - Gesture

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                guard !isSending, flyDirection == nil else { return }
                let dy = value.translation.height
                // Pinned to the finger: full follow up and sideways, light give down.
                cardDrag = dy < 0 ? dy : dy * 0.12
                cardDragX = value.translation.width
                // Flick past the detach point while still moving → commit
                // mid-gesture, no need to lift the finger.
                let vx = value.velocity.width
                let vy = value.velocity.height
                if canSend, dy < -Self.autoCommitDistance, vy < -500 {
                    commit(.up, remaining: remainingTravel(for: .up, translation: -dy), speed: -vy)
                } else if canSend, cardDragX > Self.autoCommitDistance, vx > 500 {
                    commit(.right, remaining: remainingTravel(for: .right, translation: cardDragX), speed: vx)
                } else if !normalizedDraft.isEmpty, !isSending, cardDragX < -Self.autoCommitDistance, vx < -500 {
                    commit(.left, remaining: remainingTravel(for: .left, translation: -cardDragX), speed: -vx)
                }
            }
            .onEnded { value in
                guard !isSending, flyDirection == nil else { return }
                let dx = value.translation.width
                let dy = value.translation.height
                let vx = value.velocity.width
                let vy = value.velocity.height
                let px = value.predictedEndTranslation.width
                let py = value.predictedEndTranslation.height

                let commitsUp = dy < -Self.commitThreshold || py < -Self.flickThreshold || vy < -Self.commitVelocity
                let commitsRight = dx > Self.commitThreshold || px > Self.flickThreshold || vx > Self.commitVelocity
                let commitsLeft = dx < -Self.commitThreshold || px < -Self.flickThreshold || vx < -Self.commitVelocity

                // Dominant axis wins when several directions qualify.
                let horizontal = abs(dx) >= -dy
                if canSend, commitsRight, horizontal || !commitsUp {
                    commit(.right, remaining: remainingTravel(for: .right, translation: dx), speed: max(900, vx))
                } else if !normalizedDraft.isEmpty, commitsLeft, horizontal || !commitsUp {
                    commit(.left, remaining: remainingTravel(for: .left, translation: -dx), speed: max(900, -vx))
                } else if canSend, commitsUp {
                    commit(.up, remaining: remainingTravel(for: .up, translation: -dy), speed: max(900, -vy))
                } else {
                    if (dy < -60 || abs(dx) > 60), normalizedDraft.isEmpty {
                        UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    }
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) {
                        cardDrag = 0
                        cardDragX = 0
                    }
                }
            }
    }

    private func remainingTravel(for direction: FlyDirection, translation: CGFloat) -> CGFloat {
        let bounds = UIScreen.main.bounds
        let total = (direction == .up ? bounds.height : bounds.width) + 320
        return max(60, total - translation)
    }

    // MARK: - Commit

    private func commit(_ direction: FlyDirection, remaining: CGFloat, speed: CGFloat) {
        flyDuration = min(0.35, max(0.1, Double(remaining / max(900, speed))))
        switch direction {
        case .up, .right: fileDraft(direction)
        case .left: discardDraft()
        }
    }

    /// File (up/right): fly the card off, write the note, swap in the next card.
    private func fileDraft(_ direction: FlyDirection) {
        guard canSend, let vaultURL else { return }
        isSending = true
        let body = draft
        let service = CaptureFilingService(vaultURL: vaultURL)

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.easeOut(duration: flyDuration)) {
            flyDirection = direction
        }

        Task {
            let outcome: Result<CaptureFilingService.Filed, Error> = await Task.detached(priority: .userInitiated) {
                Result { try service.file(body) }
            }.value

            // Let the fly-off finish before the card resets.
            try? await Task.sleep(for: .milliseconds(Int(flyDuration * 1000) + 60))

            switch outcome {
            case .success(let filed):
                logger.info("capture filed \(filed.relativePath, privacy: .public) created=\(filed.didCreate)")
                DebugTrace.record("capture filed \(filed.relativePath) created=\(filed.didCreate)")
                await SearchIndexController.shared.scheduleRefreshFile(vaultURL: vaultURL, fileURL: filed.fileURL)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                clearEditor()
                resetCard()
                isSending = false
                show(CaptureStatus.filed(
                    relativePath: filed.relativePath,
                    fileURL: filed.fileURL,
                    didCreate: filed.didCreate
                ))
            case .failure(let error):
                logger.error("capture failed: \(error.localizedDescription, privacy: .public)")
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                // Bring the unsent card back rather than losing the draft.
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    flyDirection = nil
                    cardDrag = 0
                    cardDragX = 0
                }
                errorMessage = (error as? CaptureFilingService.FilingError).map { "\($0)" } ?? error.localizedDescription
                isSending = false
            }
        }
    }

    /// Discard (left): fly the card off and drop the draft. Nothing is written.
    private func discardDraft() {
        guard !normalizedDraft.isEmpty, !isSending else { return }
        isSending = true
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        withAnimation(.easeOut(duration: flyDuration)) {
            flyDirection = .left
        }
        Task {
            try? await Task.sleep(for: .milliseconds(Int(flyDuration * 1000) + 60))
            clearEditor()
            resetCard()
            isSending = false
            show(CaptureStatus.discarded())
        }
    }

    private func show(_ line: CaptureStatus) {
        status = line
        Task {
            try? await Task.sleep(for: line.dwell)
            if status == line { status = nil }
        }
    }

    /// The background card has animated into the front card's spot during the
    /// fly-off, and the front card resets to the identical empty shell — swap
    /// them with no animation and the handoff is invisible; the (new) back
    /// card then settles into its resting depth.
    private func resetCard() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            cardDrag = 0
            cardDragX = 0
            flyDirection = nil
            cardArriving = true
        }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
            cardArriving = false
        }
    }

    private func clearEditor() {
        draft = ""
        editorDocumentID = UUID().uuidString
    }
}
