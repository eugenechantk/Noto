import CoreGraphics
import Testing
@testable import Noto2

/// Turning a drag into one of four decisions.
///
/// This is the whole gesture contract, and it is exactly the kind of thing that
/// regresses invisibly — a threshold tweak that makes "snooze" occasionally
/// delete would never show up in a screenshot.
///
/// | Test | Covers |
/// | --- | --- |
/// | `mapsEachDirectionToItsAction` | left=snooze, right=addTo, up=create, down=discard |
/// | `shortDragsDoNotCommit` | a nudge springs back instead of firing something |
/// | `flicksCommitOnPredictedTravel` | a short fast swipe still commits |
/// | `flicksCommitOnVelocityAlone` | a very fast short swipe commits |
/// | `dominantAxisWinsOnDiagonals` | a sloppy down-right drag can't delete when you meant add-to |
/// | `inFlightDetachNeedsDistanceAndSpeed` | mid-gesture commit requires both |
/// | `inFlightIgnoresSlowLongDrags` | dragging out and holding does not fire |
/// | `signalOnlyLightsTheDominantAxis` | dragging right must not half-light the trash |
/// | `signalSaturatesAtTheSignalTravel` | overlay/target reach full strength and clamp |
/// | `sheetOpeningActionsAreFlagged` | addTo/create hold the card; snooze/discard commit outright |
struct DigestSwipeTests {
    private func size(_ width: CGFloat, _ height: CGFloat) -> CGSize {
        CGSize(width: width, height: height)
    }

    private func release(_ translation: CGSize, predicted: CGSize? = nil, velocity: CGSize = .zero) -> DigestSwipe? {
        DigestSwipeResolver.resolveRelease(
            translation: translation,
            predicted: predicted ?? translation,
            velocity: velocity
        )
    }

    /// The core mapping Eugene specified.
    @Test func mapsEachDirectionToItsAction() {
        #expect(release(size(-140, 0)) == .snooze)
        #expect(release(size(140, 0)) == .addTo)
        #expect(release(size(0, -140)) == .create)
        #expect(release(size(0, 140)) == .discard)
    }

    /// Below the commit threshold nothing happens — the card springs back.
    @Test func shortDragsDoNotCommit() {
        #expect(release(size(60, 0)) == nil)
        #expect(release(size(-60, 0)) == nil)
        #expect(release(size(0, 60)) == nil)
        #expect(release(size(0, -60)) == nil)
        #expect(release(.zero) == nil)
    }

    /// A short swipe that was clearly *going* somewhere commits on its projection.
    @Test func flicksCommitOnPredictedTravel() {
        #expect(release(size(0, -40), predicted: size(0, -300)) == .create)
        #expect(release(size(40, 0), predicted: size(300, 0)) == .addTo)
    }

    /// And a fast enough one commits on speed alone.
    @Test func flicksCommitOnVelocityAlone() {
        #expect(release(size(0, 30), predicted: size(0, 30), velocity: size(0, 900)) == .discard)
        #expect(release(size(-30, 0), predicted: size(-30, 0), velocity: size(-900, 0)) == .snooze)
    }

    /// Diagonals resolve to the axis the user actually travelled furthest on, so
    /// a rightward drag that sags downward files rather than deletes.
    @Test func dominantAxisWinsOnDiagonals() {
        #expect(release(size(200, 120)) == .addTo)      // mostly right
        #expect(release(size(120, 200)) == .discard)    // mostly down
        #expect(release(size(-200, -120)) == .snooze)   // mostly left
        #expect(release(size(-120, -200)) == .create)   // mostly up
    }

    /// A flick past the detach point fires mid-gesture so you needn't lift off —
    /// but it needs both the distance and the speed.
    @Test func inFlightDetachNeedsDistanceAndSpeed() {
        #expect(DigestSwipeResolver.resolveInFlight(translation: size(0, -200), velocity: size(0, -800)) == .create)
        #expect(DigestSwipeResolver.resolveInFlight(translation: size(0, 200), velocity: size(0, 800)) == .discard)
        // Fast but not far enough.
        #expect(DigestSwipeResolver.resolveInFlight(translation: size(0, -100), velocity: size(0, -800)) == nil)
    }

    /// Dragging the card out slowly and holding it there must not fire; the user
    /// is still deciding.
    @Test func inFlightIgnoresSlowLongDrags() {
        #expect(DigestSwipeResolver.resolveInFlight(translation: size(300, 0), velocity: size(50, 0)) == nil)
        #expect(DigestSwipeResolver.resolveInFlight(translation: size(0, 300), velocity: .zero) == nil)
    }

    /// Only the dominant axis signals. Without this, a rightward drag would tint
    /// the card blue *and* start lighting the red trash, which reads as a threat.
    @Test func signalOnlyLightsTheDominantAxis() {
        let rightAndDown = size(200, 60)
        #expect(DigestSwipeResolver.signalStrength(for: .addTo, translation: rightAndDown) > 0)
        #expect(DigestSwipeResolver.signalStrength(for: .discard, translation: rightAndDown) == 0)
        #expect(DigestSwipeResolver.signalStrength(for: .snooze, translation: rightAndDown) == 0)

        let upAndLeft = size(-40, -200)
        #expect(DigestSwipeResolver.signalStrength(for: .create, translation: upAndLeft) > 0)
        #expect(DigestSwipeResolver.signalStrength(for: .snooze, translation: upAndLeft) == 0)
    }

    /// Strength ramps to 1 by the signal travel and clamps there.
    @Test func signalSaturatesAtTheSignalTravel() {
        let full = DigestSwipeResolver.signalTravel
        #expect(DigestSwipeResolver.signalStrength(for: .create, translation: size(0, -full)) == 1)
        #expect(DigestSwipeResolver.signalStrength(for: .create, translation: size(0, -full * 3)) == 1)
        #expect(DigestSwipeResolver.signalStrength(for: .create, translation: size(0, full)) == 0)
        let half = DigestSwipeResolver.signalStrength(for: .snooze, translation: size(-full / 2, 0))
        #expect(abs(half - 0.5) < 0.001)
    }

    /// The two that need more input hold the card until their sheet reports back;
    /// the other two commit on the swipe alone.
    @Test func sheetOpeningActionsAreFlagged() {
        #expect(DigestSwipe.addTo.opensSheet)
        #expect(DigestSwipe.create.opensSheet)
        #expect(!DigestSwipe.snooze.opensSheet)
        #expect(!DigestSwipe.discard.opensSheet)
    }
}
