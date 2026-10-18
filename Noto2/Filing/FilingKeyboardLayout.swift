import SwiftUI
import UIKit

/// Gives this sheet one owner for keyboard avoidance. In particular, a prior
/// TextKit input accessory must not become a stale SwiftUI bottom safe area.
struct FilingKeyboardLayout<Content: View, BottomBar: View>: UIViewControllerRepresentable {
    let content: Content
    let bottomBar: BottomBar

    init(@ViewBuilder content: () -> Content, @ViewBuilder bottomBar: () -> BottomBar) {
        self.content = content()
        self.bottomBar = bottomBar()
    }

    func makeUIViewController(context: Context) -> FilingKeyboardLayoutController {
        FilingKeyboardLayoutController(content: AnyView(content), bottomBar: AnyView(bottomBar))
    }

    func updateUIViewController(_ controller: FilingKeyboardLayoutController, context: Context) {
        controller.update(content: AnyView(content), bottomBar: AnyView(bottomBar))
    }
}

final class FilingKeyboardLayoutController: UIViewController {
    private let contentHost: UIHostingController<AnyView>
    private let bottomBarHost: UIHostingController<AnyView>
    private var nativeBottom: NSLayoutConstraint!
    private var safeBottom: NSLayoutConstraint!
    private var observedBottom: NSLayoutConstraint!
    private var activeBottom: NSLayoutConstraint?
    private var keyboardFrame: FilingKeyboardFrame?

    var bottomBarView: UIView { bottomBarHost.view }

    init(content: AnyView, bottomBar: AnyView) {
        contentHost = UIHostingController(rootView: content)
        bottomBarHost = UIHostingController(rootView: bottomBar)
        super.init(nibName: nil, bundle: nil)

        // UIKit constrains both children above the keyboard. Keep their ordinary
        // container safe areas, but do not apply SwiftUI keyboard avoidance too.
        contentHost.safeAreaRegions = .container
        bottomBarHost.safeAreaRegions = .container
        bottomBarHost.sizingOptions = .intrinsicContentSize
    }

    required init?(coder: NSCoder) { return nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        install(contentHost)
        install(bottomBarHost)
        // SwiftUI scrolling descendants can paint beyond a hosting view's
        // bounds. Results must stop above the separate search capsule.
        contentHost.view.clipsToBounds = true
        bottomBarView.setContentHuggingPriority(.required, for: .vertical)
        bottomBarView.setContentCompressionResistancePriority(.required, for: .vertical)
        nativeBottom = bottomBarView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor)
        safeBottom = bottomBarView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        observedBottom = bottomBarView.bottomAnchor.constraint(equalTo: view.topAnchor)

        NSLayoutConstraint.activate([
            contentHost.view.topAnchor.constraint(equalTo: view.topAnchor),
            contentHost.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentHost.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentHost.view.bottomAnchor.constraint(equalTo: bottomBarView.topAnchor),
            bottomBarView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBarView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        useBottom(nativeBottom)
        for name in [UIResponder.keyboardWillChangeFrameNotification, UIResponder.keyboardDidChangeFrameNotification,
                     UIResponder.keyboardWillHideNotification, UIResponder.keyboardDidHideNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(keyboardChanged(_:)), name: name, object: nil)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateKeyboardConstraint()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        keyboardFrame = nil
        useBottom(nativeBottom)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func keyboardChanged(_ notification: Notification) {
        guard let window = viewIfLoaded?.window,
              window.isKeyWindow,
              window.windowScene?.activationState == .foregroundActive,
              let frame = FilingKeyboardFrame(notification, window: window) else { return }
        let hiding = notification.name == UIResponder.keyboardWillHideNotification
            || notification.name == UIResponder.keyboardDidHideNotification
        // A keyboard notification is app-wide. Only track this visible sheet's
        // responder, plus the final hide event after that responder resigns.
        guard containsFirstResponder(view) || (hiding && keyboardFrame != nil) else { return }

        view.layoutIfNeeded()
        keyboardFrame = hiding ? frame.hidden : frame
        updateKeyboardConstraint()
        let duration = (notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue ?? 0
        let curve = (notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber)?.uintValue ?? 0
        let changing = notification.name == UIResponder.keyboardWillChangeFrameNotification
            || notification.name == UIResponder.keyboardWillHideNotification
        if changing && duration > 0 {
            UIView.animate(withDuration: duration, delay: 0,
                           options: [UIView.AnimationOptions(rawValue: curve << 16), .beginFromCurrentState, .allowUserInteraction]) {
                self.view.layoutIfNeeded()
            }
        } else {
            view.layoutIfNeeded()
        }
    }

    private func updateKeyboardConstraint() {
        guard let keyboardFrame else { return }
        guard let window = view.window, window.isKeyWindow,
              window.windowScene?.activationState == .foregroundActive else {
            self.keyboardFrame = nil
            useBottom(nativeBottom)
            return
        }
        guard let top = keyboardFrame.dockedTop(in: view) else {
            useBottom(safeBottom)
            return
        }
        // The native guide was measured below the actual keyboard after an
        // accessory-bearing editor disappeared. Use the observed frame only
        // while it disagrees; this is measured geometry, never a fixed offset.
        if abs(view.keyboardLayoutGuide.layoutFrame.minY - top) > 0.5 {
            if abs(observedBottom.constant - top) > 0.001 { observedBottom.constant = top }
            useBottom(observedBottom)
        } else {
            useBottom(nativeBottom)
        }
    }

    private func useBottom(_ constraint: NSLayoutConstraint) {
        guard activeBottom !== constraint else { return }
        activeBottom?.isActive = false
        constraint.isActive = true
        activeBottom = constraint
    }

    private func containsFirstResponder(_ view: UIView) -> Bool {
        view.isFirstResponder || view.subviews.contains(where: containsFirstResponder)
    }

    func update(content: AnyView, bottomBar: AnyView) {
        contentHost.rootView = content
        bottomBarHost.rootView = bottomBar
    }

    private func install(_ child: UIViewController) {
        addChild(child)
        child.view.backgroundColor = .clear
        child.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(child.view)
        child.didMove(toParent: self)
    }
}

/// UIKit keyboard frames are in the notification screen's coordinates, not
/// those of a sheet, split-view window, or Stage Manager window.
@MainActor
struct FilingKeyboardFrame {
    private let screen: UIScreen
    private let windowID: ObjectIdentifier
    private let frame: CGRect
    private var isHidden = false

    init?(_ notification: Notification, window: UIWindow) {
        guard (notification.userInfo?[UIResponder.keyboardIsLocalUserInfoKey] as? NSNumber)?.boolValue == true,
              let screen = notification.object as? UIScreen, screen === window.screen,
              let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              !frame.isNull, !frame.isInfinite,
              frame.minX.isFinite, frame.minY.isFinite, frame.maxX.isFinite, frame.maxY.isFinite else { return nil }
        self.screen = screen
        windowID = ObjectIdentifier(window)
        self.frame = frame
    }

    var hidden: FilingKeyboardFrame {
        var value = self
        value.isHidden = true
        return value
    }

    func dockedTop(in view: UIView) -> CGFloat? {
        guard !isHidden, let window = view.window,
              ObjectIdentifier(window) == windowID, window.screen === screen else { return nil }
        let inWindow = screen.coordinateSpace.convert(frame, to: window)
        let intersection = inWindow.intersection(window.bounds)
        // A floating or undocked keyboard must not lift the full-width bar.
        guard !intersection.isNull, intersection.height > 0,
              inWindow.maxY >= window.bounds.maxY - 0.5,
              intersection.width >= window.bounds.width - 0.5 else { return nil }
        let localTop = view.convert(intersection, from: window).minY
        return max(view.bounds.minY, min(localTop, view.safeAreaLayoutGuide.layoutFrame.maxY))
    }
}
