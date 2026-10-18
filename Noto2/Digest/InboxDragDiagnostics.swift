import OSLog
import SwiftUI
import UIKit

/// Opt-in observations only. This does not install recognizers, replace the
/// system context-menu delegate, or change gesture arbitration.
@MainActor
enum InboxDragDiagnostics {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto2", category: "InboxDragDiagnostics")

    static func record(_ phase: String, value: DragGesture.Value) {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["NOTO_INBOX_DRAG_TRACE"] == "1" else { return }
        let event = "phase=\(phase) eventTime=\(value.time.timeIntervalSince1970) uptime=\(ProcessInfo.processInfo.systemUptime) start=\(value.startLocation) location=\(value.location) translation=\(value.translation) velocity=\(value.velocity)"
        log(event, stage: "callback")
        // Observe after SwiftUI has had one turn to apply this drag update.
        // This schedules no UI change or fixed delay.
        DispatchQueue.main.async { log(event, stage: "nextRunLoop") }
        #endif
    }

    #if DEBUG
    private static func log(_ event: String, stage: String) {
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).filter { !$0.isHidden }
        var observations: [String] = []
        for (index, window) in windows.enumerated() {
            observations.append("window\(index):level=\(window.windowLevel.rawValue)")
            inspect(window, in: window, path: "w\(index)", observations: &observations)
        }
        logger.info("\(event, privacy: .public) stage=\(stage, privacy: .public) native=\(observations.joined(separator: ";"), privacy: .public)")
    }

    private static func inspect(_ view: UIView, in window: UIWindow, path: String, observations: inout [String]) {
        guard !view.isHidden, view.alpha > 0 else { return }
        for interaction in view.interactions {
            guard let menu = interaction as? UIContextMenuInteraction else { continue }
            let appearance: String
            switch menu.menuAppearance {
            case .unknown: appearance = "unknown"
            case .rich: appearance = "rich"
            case .compact: appearance = "compact"
            @unknown default: appearance = "future"
            }
            observations.append("\(path):menu=\(appearance),frame=\(view.convert(view.bounds, to: window)),z=\(view.layer.zPosition)")
        }
        for recognizer in view.gestureRecognizers ?? [] {
            guard recognizer.state != .possible, recognizer.state != .failed else { continue }
            let kind = recognizer is UILongPressGestureRecognizer ? "longPress" : recognizer is UIPanGestureRecognizer ? "pan" : "other"
            observations.append("\(path):gesture=\(kind),state=\(recognizer.state.rawValue)")
        }
        for (index, child) in view.subviews.enumerated() {
            inspect(child, in: window, path: path + ".\(index)", observations: &observations)
        }
    }
    #endif
}
