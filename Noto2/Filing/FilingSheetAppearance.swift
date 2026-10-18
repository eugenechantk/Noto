import SwiftUI
import UIKit

/// SwiftUI's task can run before a sheet has completed presentation. Request
/// input focus only after UIKit has made the sheet and its controls visible.
struct FilingSheetAppearance: UIViewControllerRepresentable {
    let onAppear: @MainActor () -> Void

    func makeUIViewController(context: Context) -> ObserverController {
        ObserverController(onAppear: onAppear)
    }

    func updateUIViewController(_ controller: ObserverController, context: Context) {
        controller.onAppear = onAppear
    }

    final class ObserverController: UIViewController {
        var onAppear: @MainActor () -> Void

        init(onAppear: @escaping @MainActor () -> Void) {
            self.onAppear = onAppear
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) { return nil }

        override func loadView() {
            let view = UIView()
            view.backgroundColor = .clear
            view.isUserInteractionEnabled = false
            self.view = view
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            Task { @MainActor [weak self] in
                // Let SwiftUI finish registering the focused text field in the
                // now-presented hierarchy; no fixed animation delay is needed.
                await Task.yield()
                guard let self, self.viewIfLoaded?.window != nil else { return }
                self.onAppear()
            }
        }
    }
}
