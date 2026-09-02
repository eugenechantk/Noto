import NotoDigest
import SwiftUI
import UIKit
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto2", category: "DigestScreen")

/// Digest tab: works the `inbox/` backlog down to zero, one capture at a time.
///
/// Four directions, four outcomes. The two axes speak different visual languages
/// on purpose:
///
/// - **Horizontal** is a decision the swipe makes by itself, so the *card* answers:
///   left floods yellow ("Snooze"), right floods blue ("Add to").
/// - **Vertical** is aimed at something, so a *target* answers: the plus above
///   fills green as you drag up ("Create"), the trash below fills red as you drag
///   down ("Discard"). The card stays untinted and simply travels toward the icon.
///
/// Discard commits on release with no confirmation dialog — the red target is the
/// warning, and an alert after the card has already flown off reads as a bug. The
/// safety net is Undo in the status line for as long as the banner is up.
struct DigestScreen: View {
    let vaultController: VaultController

    @State private var model: DigestModel
    @State private var fileMode: DigestFileMode?
    /// Bumped on every appearance so the load task re-runs when the tab is
    /// re-selected (a plain `.task` fires once per view lifetime).
    @State private var appearCount = 0
    @Environment(\.scenePhase) private var scenePhase

    // Card gesture state.
    @State private var drag: CGSize = .zero
    @State private var flyDirection: DigestSwipe?
    /// Which way to fly once an open sheet reports a successful file.
    @State private var pendingFly: DigestSwipe?
    @State private var cardArriving = false
    @State private var flyDuration: Double = 0.25

    init(vaultController: VaultController) {
        self.vaultController = vaultController
        _model = State(wrappedValue: DigestModel(vaultURL: vaultController.vaultURL))
    }

    private static let cardCornerRadius: CGFloat = 24
    private static let targetSize: CGFloat = 46

    /// Left — a week from now. Amber, matching the app's "waiting" status colour.
    private static let snoozeTint = NotoTheme.statusAmber
    /// Right — into a note that already exists. Blue reads as "filed", distinct
    /// from the orange the app spends on primary actions.
    private static let addToTint = Color(red: 0.29, green: 0.56, blue: 0.96)
    /// Up — something new. Green is the universal "add".
    private static let createTint = Color(red: 0.30, green: 0.76, blue: 0.44)
    /// Down — gone.
    private static let discardTint = NotoTheme.destructive

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                statusSlot
                if model.isClear {
                    emptyState
                } else {
                    Spacer(minLength: 4)
                    target(
                        glyph: "plus",
                        tint: Self.createTint,
                        strength: strength(.create),
                        id: "digestCreateTarget",
                        label: "Create a new note"
                    )
                    // Above the card in z-order: the card is dragged *toward* the
                    // target and must slide underneath it. Without this the card
                    // covers the icon exactly when its highlight matters most.
                    .zIndex(1)
                    Spacer(minLength: 6)
                    ZStack {
                        backCard
                        if let entry = model.current {
                            card(for: entry, in: geometry)
                        }
                    }
                    .frame(height: Self.cardHeight(available: geometry.size.height))
                    Spacer(minLength: 6)
                    target(
                        glyph: "trash",
                        tint: Self.discardTint,
                        strength: strength(.discard),
                        id: "digestDiscardTarget",
                        label: "Discard this capture"
                    )
                    .zIndex(1)
                    Spacer(minLength: 4)
                    actionRow
                }
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .simultaneousGesture(dragGesture)
        }
        .background(NotoTheme.background.ignoresSafeArea())
        // Re-read on every appearance, not just the first: Capture writes to
        // `inbox/` in another tab, and a one-shot load left the Digest showing
        // "Inbox clear" over a folder that had captures in it.
        .task(id: appearCount) { await model.refresh() }
        .onAppear { appearCount &+= 1 }
        .onChange(of: scenePhase) { _, phase in
            // Captures can also arrive while the app is backgrounded — from the
            // Lock Screen quick-capture widget, or iCloud syncing another device.
            guard phase == .active else { return }
            Task { await model.refresh() }
        }
        .sheet(item: $fileMode) { mode in
            if let entry = model.current {
                DigestFileSheet(
                    vaultController: vaultController,
                    capture: entry,
                    mode: mode,
                    onFile: { destination in file(destination) }
                )
            }
        }
        .onChange(of: fileMode) { _, newValue in
            // Sheet dismissed without filing: bring the card back.
            if newValue == nil, flyDirection == nil { springBack() }
        }
        .alert("Couldn't file this capture", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    // MARK: - Fixed slots (no layout shift)

    /// One reserved line, exactly like Capture's: the last outcome while it is
    /// fresh, otherwise how much is left. A discard's banner carries Undo.
    private var statusSlot: some View {
        Group {
            if let outcome = model.outcome {
                HStack(spacing: 6) {
                    Image(systemName: outcome.glyph)
                    Text(outcome.text)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if outcome.isUndoable {
                        Button("Undo") {
                            Task { await model.undoDiscard() }
                        }
                        .buttonStyle(.plain)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(NotoTheme.accent)
                        .accessibilityIdentifier("digestUndoButton")
                    }
                }
                .foregroundStyle(AppTheme.secondaryText)
                .accessibilityIdentifier("digestOutcomeLine")
                .task(id: outcome) {
                    // Long enough to notice and reach for Undo, short enough that
                    // the count comes back on its own.
                    try? await Task.sleep(for: .seconds(outcome.isUndoable ? 6 : 2.5))
                    model.clearOutcome(outcome)
                }
            } else if model.remaining > 0 {
                Text("\(model.remaining) to process")
                    .foregroundStyle(AppTheme.mutedText)
                    .accessibilityIdentifier("digestRemainingCount")
            }
        }
        .font(.footnote)
        .frame(maxWidth: .infinity, alignment: .center)
        .frame(height: 22)
        .padding(.top, 12)
        .animation(.easeInOut(duration: 0.2), value: model.outcome)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(NotoTheme.faint)
            Text("Inbox clear")
                .font(.system(size: NotoTheme.FontSize.h2, weight: .semibold))
                .foregroundStyle(NotoTheme.head)
            Text("Everything you captured has been filed or snoozed.")
                .font(.footnote)
                .foregroundStyle(AppTheme.mutedText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("digestEmptyState")
    }

    // MARK: - Drop targets

    /// A vertical swipe's destination. At rest it is a bare, faint glyph — an
    /// affordance, not a button. As the card travels toward it, a tinted circle
    /// grows in behind and the glyph turns white: "let go here and this happens".
    private func target(glyph: String, tint: Color, strength: CGFloat, id: String, label: String) -> some View {
        let p = Double(strength)
        return Image(systemName: glyph)
            .font(.system(size: 19, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.45 + 0.55 * p))
            .frame(width: Self.targetSize, height: Self.targetSize)
            .background {
                Circle()
                    .fill(tint.opacity(0.95 * p))
                    .overlay(Circle().strokeBorder(tint.opacity(0.25 + 0.55 * p), lineWidth: 1.5))
            }
            .scaleEffect(1 + 0.18 * p)
            .animation(.easeOut(duration: 0.12), value: strength)
            .allowsHitTesting(false)
            .accessibilityIdentifier(id)
            .accessibilityLabel(label)
    }

    // MARK: - Card

    private static func cardHeight(available: CGFloat) -> CGFloat {
        min(430, max(220, available * 0.52))
    }

    private func card(for entry: DigestEntry, in geometry: GeometryProxy) -> some View {
        let shape = RoundedRectangle(cornerRadius: Self.cardCornerRadius, style: .continuous)
        return ZStack {
            shape.fill(NotoTheme.card)

            VStack(alignment: .leading, spacing: 10) {
                Text(Self.capturedStamp(entry.capturedAt))
                    .font(.system(size: NotoTheme.FontSize.subtitle))
                    .foregroundStyle(NotoTheme.muted)
                    .accessibilityIdentifier("digestCardDate")

                if entry.isAvailable {
                    ScrollView {
                        Text(entry.body)
                            .font(.system(size: NotoTheme.FontSize.body))
                            .foregroundStyle(NotoTheme.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .accessibilityIdentifier("digestCardBody")
                } else {
                    // Dataless iCloud stub — say so rather than showing a blank card.
                    VStack(spacing: 8) {
                        ProgressView()
                        Text("Downloading from iCloud…")
                            .font(.footnote)
                            .foregroundStyle(AppTheme.mutedText)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("digestCardDownloading")
                }
            }
            .padding(20)

            // Horizontal commits colour the card itself; the vertical ones are
            // announced by their target icon instead.
            tintOverlay(shape: shape, tint: Self.snoozeTint, glyph: "clock",
                        label: "Snooze", strength: strength(.snooze))
                .accessibilityIdentifier("digestSnoozeOverlay")
            tintOverlay(shape: shape, tint: Self.addToTint, glyph: "text.append",
                        label: "Add to", strength: strength(.addTo))
                .accessibilityIdentifier("digestAddToOverlay")
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        .offset(cardOffset(in: geometry))
        .rotationEffect(.degrees(cardRotation), anchor: .bottom)
        .scaleEffect(cardArriving ? 0.94 : 1)
        .opacity(cardArriving ? 0 : 1)
        // `.contain`, not a bare identifier: a plain `.accessibilityIdentifier`
        // here collapses the subtree and the date/body lose their own.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("digestCard")
    }

    private func tintOverlay(shape: RoundedRectangle, tint: Color, glyph: String, label: String, strength: CGFloat) -> some View {
        shape
            .fill(tint.opacity(0.92))
            // Centred, not top-aligned like Capture's: Capture's card is an empty
            // editor, but a digest card already has a date and body text at the
            // top, and a label there lands right on them mid-drag.
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: glyph)
                        .font(.system(size: 30, weight: .bold))
                    Text(label)
                        .font(.title3.weight(.semibold))
                }
                .foregroundStyle(.white)
            }
            .opacity(Double(strength) * 0.95)
            .allowsHitTesting(false)
    }

    /// The next capture, sitting behind the current one.
    ///
    /// Visible **at rest** whenever there is a next card — the stack is how you
    /// see there's more to do — and absent entirely on the last one, so the final
    /// card reads as final. It rises to full size as the front card leaves.
    private var backCard: some View {
        let shape = RoundedRectangle(cornerRadius: Self.cardCornerRadius, style: .continuous)
        let p = DigestSwipeResolver.stackProgress(translation: drag)
        let hasNext = model.next != nil
        return shape
            // Slightly lighter than the front card so the peeking rim separates
            // instead of blending into one taller card.
            .fill(NotoTheme.card.opacity(0.75))
            .overlay(shape.strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
            .scaleEffect(0.93 + 0.07 * p)
            .offset(y: 22 * (1 - p))
            .opacity(hasNext && !cardArriving ? 1 : 0)
            .allowsHitTesting(false)
            .accessibilityIdentifier("digestBackCard")
    }

    private func cardOffset(in geometry: GeometryProxy) -> CGSize {
        let escapeX = geometry.size.width + 320
        let escapeY = geometry.size.height + 320
        switch flyDirection {
        case .snooze:  return CGSize(width: -escapeX, height: drag.height)
        case .addTo:   return CGSize(width: escapeX, height: drag.height)
        case .create:  return CGSize(width: drag.width, height: -escapeY)
        case .discard: return CGSize(width: drag.width, height: escapeY)
        case nil:      return CGSize(width: drag.width, height: drag.height + (cardArriving ? 44 : 0))
        }
    }

    /// Tilt comes from lateral travel only — a vertical swipe should read as the
    /// card lifting toward a target, not toppling.
    private var cardRotation: Double {
        switch flyDirection {
        case .snooze: return -9
        case .addTo: return 9
        case .create, .discard: return 0
        case nil: return min(10, max(-10, Double(drag.width) / 18))
        }
    }

    // MARK: - Actions row

    /// The explicit path for the two actions that need more input anyway. Discard
    /// and snooze are gesture-only — both are one-tap-irreversible-ish, and the
    /// targets above and below already advertise them.
    private var actionRow: some View {
        HStack(spacing: 10) {
            actionButton("Add to", systemImage: "text.append", id: "digestAddToButton") {
                present(.addTo)
            }
            actionButton("Create", systemImage: "doc.badge.plus", id: "digestCreateButton") {
                present(.create)
            }
        }
        .disabled(!canAct)
        .opacity(canAct ? 1 : 0.4)
        .padding(.bottom, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("digestActionRow")
    }

    private func actionButton(_ title: String, systemImage: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(NotoTheme.head)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(NotoTheme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    // MARK: - Gesture

    private func strength(_ swipe: DigestSwipe) -> CGFloat {
        if let flyDirection { return flyDirection == swipe ? 1 : 0 }
        return DigestSwipeResolver.signalStrength(for: swipe, translation: drag)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                guard canAct, flyDirection == nil, fileMode == nil else { return }
                // Full follow in every direction now that all four commit.
                drag = value.translation
                if let swipe = DigestSwipeResolver.resolveInFlight(
                    translation: value.translation,
                    velocity: CGSize(width: value.velocity.width, height: value.velocity.height)
                ) {
                    commit(swipe, translation: value.translation, velocity: value.velocity)
                }
            }
            .onEnded { value in
                guard canAct, flyDirection == nil, fileMode == nil else { return }
                guard let swipe = DigestSwipeResolver.resolveRelease(
                    translation: value.translation,
                    predicted: value.predictedEndTranslation,
                    velocity: CGSize(width: value.velocity.width, height: value.velocity.height)
                ) else {
                    springBack()
                    return
                }
                commit(swipe, translation: value.translation, velocity: value.velocity)
            }
    }

    /// Actions need a card, an idle model, and a capture whose body has actually
    /// downloaded — filing a dataless stub would fail on the read.
    private var canAct: Bool {
        model.current?.isAvailable == true && !model.isBusy
    }

    // MARK: - Commits

    private func commit(_ swipe: DigestSwipe, translation: CGSize, velocity: CGSize) {
        guard canAct else { return }

        if swipe.opensSheet {
            // The filing needs input, so hold the card where it is and let the
            // sheet decide; it flies this way only once the write succeeds.
            pendingFly = swipe
            present(swipe == .create ? .create : .addTo)
            return
        }

        flyDuration = Self.flyDuration(translation: translation, velocity: velocity, swipe: swipe)
        UIImpactFeedbackGenerator(style: swipe == .discard ? .rigid : .medium).impactOccurred()
        withAnimation(.easeOut(duration: flyDuration)) { flyDirection = swipe }

        Task {
            let ok: Bool
            switch swipe {
            case .snooze: ok = await model.snoozeCurrent()
            case .discard: ok = await model.discardCurrent()
            case .addTo, .create: ok = false   // handled above
            }
            await settle(succeeded: ok)
        }
    }

    /// Matches the fly-off to the flick that caused it, so a hard swipe leaves
    /// fast and a slow drag glides.
    private static func flyDuration(translation: CGSize, velocity: CGSize, swipe: DigestSwipe) -> Double {
        let bounds = UIScreen.main.bounds
        let horizontal = swipe == .snooze || swipe == .addTo
        let total = (horizontal ? bounds.width : bounds.height) + 320
        let travelled = horizontal ? abs(translation.width) : abs(translation.height)
        let speed = max(900, horizontal ? abs(velocity.width) : abs(velocity.height))
        return min(0.35, max(0.1, Double(max(60, total - travelled) / speed)))
    }

    private func file(_ destination: DigestDestination) {
        flyDuration = 0.25
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let direction = pendingFly ?? .addTo
        withAnimation(.easeOut(duration: flyDuration)) { flyDirection = direction }

        Task {
            let ok: Bool
            switch destination {
            case .existingNote(let url, let title):
                ok = await model.addCurrent(toNoteAt: url, titled: title)
            case .newNote(let title, let folderURL):
                ok = await model.createNoteFromCurrent(title: title, inFolderAt: folderURL)
            }
            await settle(succeeded: ok)
        }
    }

    private func present(_ mode: DigestFileMode) {
        guard canAct else { return }
        fileMode = mode
    }

    /// Let the fly-off finish, then either swap in the next card (the model has
    /// already popped the queue) or bring this one back.
    private func settle(succeeded: Bool) async {
        try? await Task.sleep(for: .milliseconds(Int(flyDuration * 1000) + 60))
        pendingFly = nil
        if succeeded {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            swapInNextCard()
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                flyDirection = nil
                drag = .zero
            }
        }
    }

    private func springBack() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) {
            drag = .zero
        }
    }

    /// The back card has animated into the front slot during the fly-off, so the
    /// swap has to be instant — animating it would show the same content twice.
    private func swapInNextCard() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            drag = .zero
            flyDirection = nil
            cardArriving = true
        }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
            cardArriving = false
        }
    }

    private static func capturedStamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
