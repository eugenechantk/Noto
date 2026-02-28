//
//  CheckmarkView.swift
//  Noto
//
//  Based on Simple Notes by Paulo Mattos.
//  Draws an animated checkmark vector icon with a circular background.
//

import UIKit

@IBDesignable
final class CheckmarkView: UIControl, CAAnimationDelegate {

    // MARK: - View Initializers

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUpLayers()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setUpLayers()
    }

    override func prepareForInterfaceBuilder() {
        setUpLayers()
        resizeLayers()
    }

    // MARK: - View Properties

    @IBInspectable
    var circleColor: UIColor? = UIColor.tertiarySystemFill {
        didSet {
            circleBackgroundLayer.fillColor = circleColor?.cgColor
        }
    }

    @IBInspectable
    var tickColor: UIColor? = UIColor.tintColor {
        didSet {
            tickLayer.strokeColor = tickColor?.cgColor
        }
    }

    // MARK: - User Interaction

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        showTick(!tickShown, animated: true)
        sendActions(for: .primaryActionTriggered)
    }

    // MARK: - View Layout

    private var oldBounds: CGRect? = nil

    override func layoutSubviews() {
        super.layoutSubviews()
        precondition(bounds.size != .zero)

        if bounds != oldBounds {
            resizeLayers()
            oldBounds = bounds
        }
    }

    // MARK: - View Layers

    private let circleBackgroundLayer = CAShapeLayer()
    private let tickLayer = CAShapeLayer()

    private func setUpLayers() {
        circleBackgroundLayer.strokeColor = UIColor.separator.cgColor
        circleBackgroundLayer.fillColor = circleColor?.cgColor
        circleBackgroundLayer.backgroundColor = nil

        tickLayer.lineJoin = .round
        tickLayer.lineCap = .round
        tickLayer.lineWidth = 1.5
        tickLayer.strokeColor = tickColor?.cgColor
        tickLayer.fillColor = nil
        tickLayer.backgroundColor = nil
        tickLayer.isHidden = !tickShown

        layer.addSublayer(circleBackgroundLayer)
        layer.addSublayer(tickLayer)
        isUserInteractionEnabled = true
    }

    private func resizeLayers() {
        resizeCircleLayer(with: bounds)
        resizeTickLayer(with: bounds)
    }

    private func resizeCircleLayer(with bounds: CGRect) {
        let circlePath = CGMutablePath()
        circlePath.addArc(
            center: bounds.center,
            radius: 0.95 * min(bounds.width, bounds.height) / 2,
            startAngle: 0,
            endAngle: 2 * CGFloat.pi,
            clockwise: false
        )
        circleBackgroundLayer.frame = bounds
        circleBackgroundLayer.path = circlePath
    }

    private func resizeTickLayer(with bounds: CGRect) {
        let scale = 0.45 * bounds.width
        let unitTransform = CGAffineTransform(scaleX: scale, y: scale)

        let tickPath = CGMutablePath()
        let left: CGFloat = 0.27
        let right: CGFloat = 1 - left
        tickPath.move(to: CGPoint(x: -left, y: -left), transform: unitTransform)
        tickPath.addLine(to: .zero, transform: unitTransform)
        tickPath.addLine(to: CGPoint(x: +right, y: -right), transform: unitTransform)

        tickLayer.path = tickPath
        tickLayer.bounds = tickPath.boundingBox
        tickLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        tickLayer.position = bounds.center
    }

    // MARK: - Tick Animation

    private var _tickShown: Bool = true

    private(set) var tickShown: Bool {
        get {
            return _tickShown
        }
        set {
            guard newValue != _tickShown else { return }

            _tickShown = newValue
            CALayer.performWithoutAnimation {
                tickLayer.isHidden = !tickShown
                tickLayer.strokeStart = 0.0
                tickLayer.strokeEnd = 1.0
            }
            setNeedsDisplay()
        }
    }

    func showTick(_ showTick: Bool, animated: Bool = false, delay: TimeInterval = 0) {
        guard showTick != tickShown else { return }

        if animated && showTick {
            _tickShown = true
            animateTick(delay: delay)
        } else {
            tickShown = showTick
        }
    }

    private func animateTick(delay: TimeInterval) {
        resetTickAnimations()

        let strokeAnimation = CABasicAnimation(keyPath: #keyPath(CAShapeLayer.strokeEnd))
        strokeAnimation.duration = 0.15
        strokeAnimation.fromValue = 0
        strokeAnimation.toValue = 1

        strokeAnimation.timingFunction = CAMediaTimingFunction(name: .easeIn)
        strokeAnimation.fillMode = .forwards
        strokeAnimation.isRemovedOnCompletion = false
        strokeAnimation.delegate = self

        let currentTime = tickLayer.convertTime(CACurrentMediaTime(), from: nil)
        strokeAnimation.beginTime = currentTime + delay

        tickLayer.add(strokeAnimation, forKey: "strokeAnimation")
    }

    private func resetTickAnimations() {
        tickLayer.removeAllAnimations()
        CALayer.performWithoutAnimation {
            tickLayer.isHidden = false
            tickLayer.strokeEnd = 0.0
        }
    }

    // MARK: - Delegate

    weak var checkmarkDelegate: CheckmarkViewDelegate?

    func animationDidStart(_ strokeAnimation: CAAnimation) {
        checkmarkDelegate?.tickAnimationDidStart(self)
    }

    func animationDidStop(_ strokeAnimation: CAAnimation, finished: Bool) {
        checkmarkDelegate?.tickAnimationDidStop(self, finished: finished)
    }
}

protocol CheckmarkViewDelegate: AnyObject {
    func tickAnimationDidStart(_ checkmarkView: CheckmarkView)
    func tickAnimationDidStop(_ checkmarkView: CheckmarkView, finished: Bool)
}

// MARK: - CALayer Helpers

fileprivate extension CALayer {

    class func performWithoutAnimation(_ block: () -> Void) {
        CATransaction.begin()
        CATransaction.setValue(true, forKey: kCATransactionDisableActions)
        block()
        CATransaction.commit()
    }
}
