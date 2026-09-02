import CoreGraphics

/// Which way the card went, and what that means.
///
/// The four directions map one-to-one onto the four things you can do to a
/// capture. Horizontal swipes tint the card (yellow left, blue right); vertical
/// swipes drag it toward a target icon that lights up (green plus above, red
/// trash below). Two different visual languages because the two axes commit
/// differently — a horizontal swipe is a decision on its own, a vertical one is
/// aimed at something.
enum DigestSwipe: String, Equatable, CaseIterable {
    /// ⟵ Push this capture a week out.
    case snooze
    /// ⟶ Append it to an existing note (opens the picker).
    case addTo
    /// ⟶ upward, toward the plus: turn it into a new note (opens the form).
    case create
    /// ⟶ downward, toward the trash: delete it.
    case discard

    /// True when committing only *opens* something and the real filing happens
    /// later — the card must stay put until the sheet reports back.
    var opensSheet: Bool { self == .addTo || self == .create }
}

/// Turning a drag into a decision.
///
/// Pure geometry, kept out of the view so the thresholds can be exercised
/// without a simulator — gesture tuning is exactly the kind of thing that
/// silently regresses.
enum DigestSwipeResolver {
    /// Travel at which a released drag commits.
    static let commitThreshold: CGFloat = 90
    /// Projected (flick) travel that commits even on a short, fast swipe.
    static let flickThreshold: CGFloat = 240
    /// Speed (pt/s) that commits regardless of distance.
    static let commitVelocity: CGFloat = 700
    /// Travel past which a still-moving flick detaches mid-gesture, so you don't
    /// have to lift your finger.
    static let autoCommitDistance: CGFloat = 150
    /// Speed required for that mid-gesture detach.
    static let autoCommitVelocity: CGFloat = 500
    /// Travel over which a direction's overlay/target reaches full strength.
    static let signalTravel: CGFloat = 120

    /// The decision a *released* drag makes, or `nil` to spring back.
    static func resolveRelease(
        translation: CGSize,
        predicted: CGSize,
        velocity: CGSize
    ) -> DigestSwipe? {
        let horizontal = abs(translation.width) >= abs(translation.height)

        let commitsRight = translation.width > commitThreshold
            || predicted.width > flickThreshold
            || velocity.width > commitVelocity
        let commitsLeft = translation.width < -commitThreshold
            || predicted.width < -flickThreshold
            || velocity.width < -commitVelocity
        let commitsUp = translation.height < -commitThreshold
            || predicted.height < -flickThreshold
            || velocity.height < -commitVelocity
        let commitsDown = translation.height > commitThreshold
            || predicted.height > flickThreshold
            || velocity.height > commitVelocity

        // The dominant axis wins when a diagonal qualifies on both, so a sloppy
        // down-right drag can't delete when the user meant "add to".
        if horizontal {
            if commitsRight { return .addTo }
            if commitsLeft { return .snooze }
            if commitsUp { return .create }
            if commitsDown { return .discard }
        } else {
            if commitsUp { return .create }
            if commitsDown { return .discard }
            if commitsRight { return .addTo }
            if commitsLeft { return .snooze }
        }
        return nil
    }

    /// The decision an *in-flight* drag makes when it is already past the detach
    /// point and still moving fast, or `nil` to keep following the finger.
    static func resolveInFlight(translation: CGSize, velocity: CGSize) -> DigestSwipe? {
        let horizontal = abs(translation.width) >= abs(translation.height)
        if horizontal {
            if translation.width > autoCommitDistance, velocity.width > autoCommitVelocity { return .addTo }
            if translation.width < -autoCommitDistance, velocity.width < -autoCommitVelocity { return .snooze }
        } else {
            if translation.height < -autoCommitDistance, velocity.height < -autoCommitVelocity { return .create }
            if translation.height > autoCommitDistance, velocity.height > autoCommitVelocity { return .discard }
        }
        return nil
    }

    /// How strongly `swipe`'s signal — the card tint, or the target icon's circle
    /// — should read for the current drag. 0…1.
    ///
    /// Only the dominant axis signals, so dragging right doesn't also half-light
    /// the trash.
    static func signalStrength(for swipe: DigestSwipe, translation: CGSize) -> CGFloat {
        let horizontal = abs(translation.width) >= abs(translation.height)
        let travel: CGFloat
        switch swipe {
        case .addTo:   travel = horizontal ? translation.width : 0
        case .snooze:  travel = horizontal ? -translation.width : 0
        case .create:  travel = horizontal ? 0 : -translation.height
        case .discard: travel = horizontal ? 0 : translation.height
        }
        return min(1, max(0, travel / signalTravel))
    }

    /// 0…1 over a longer travel, driving the card behind rising into place.
    static func stackProgress(translation: CGSize) -> CGFloat {
        let travel = max(abs(translation.width), abs(translation.height))
        return min(1, max(0, travel / 280))
    }
}
