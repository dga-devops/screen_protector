//
//  AccessibleScreenPreventer.swift
//  screen_protector
//
//  Custom screenshot prevention implementation that is VoiceOver accessible.
//  Based on ScreenProtectorKit but with proper accessibility configuration
//  to prevent VoiceOver from focusing on the hidden UITextField.
//

import UIKit

public class AccessibleScreenPreventer {

    public var window: UIWindow? = nil
    private var screenImage: UIImageView? = nil
    private var screenBlur: UIView? = nil
    private var screenColor: UIView? = nil
    private var screenPrevent = UITextField()
    private var screenshotObserve: NSObjectProtocol? = nil
    private var screenRecordObserve: NSObjectProtocol? = nil
    private var isConfigured = false

    public init(window: UIWindow?) {
        self.window = window
        configureAccessibility()
    }

    /// Configure accessibility properties on the hidden text field to prevent VoiceOver interference
    private func configureAccessibility() {
        // CRITICAL: Configure accessibility to NOT interfere with VoiceOver
        screenPrevent.isAccessibilityElement = false
        screenPrevent.accessibilityElementsHidden = true
        screenPrevent.accessibilityLabel = nil
        screenPrevent.accessibilityHint = nil
        screenPrevent.accessibilityTraits = .none
        screenPrevent.isUserInteractionEnabled = false
    }

    /// Configure the screenshot prevention layer structure
    /// Call this once during app initialization
    public func configurePreventionScreenshot() {
        guard let w = window else { return }
        guard !isConfigured else { return }

        if !w.subviews.contains(screenPrevent) {
            // Re-apply accessibility settings before adding to window
            configureAccessibility()

            w.addSubview(screenPrevent)
            screenPrevent.centerYAnchor.constraint(equalTo: w.centerYAnchor).isActive = true
            screenPrevent.centerXAnchor.constraint(equalTo: w.centerXAnchor).isActive = true
            w.layer.superlayer?.addSublayer(screenPrevent.layer)
            if #available(iOS 17.0, *) {
                screenPrevent.layer.sublayers?.last?.addSublayer(w.layer)
            } else {
                screenPrevent.layer.sublayers?.first?.addSublayer(w.layer)
            }

            // Re-apply accessibility settings after layer manipulation
            configureAccessibility()
            isConfigured = true
        }
    }

    public func enabledPreventScreenshot() {
        if !isConfigured {
            configurePreventionScreenshot()
        }
        screenPrevent.isSecureTextEntry = true
        // Re-apply accessibility settings
        configureAccessibility()
    }

    public func disablePreventScreenshot() {
        screenPrevent.isSecureTextEntry = false
    }

    @available(iOS 11.0, *)
    public func enabledPreventScreenRecording() {
        enabledPreventScreenshot()
    }

    @available(iOS 11.0, *)
    public func disablePreventScreenRecording() {
        // Screen recording prevention uses the same mechanism
    }

    public func enabledBlurScreen(style: UIBlurEffect.Style = UIBlurEffect.Style.light) {
        // Fix: Use window?.snapshotView instead of UIScreen.main.snapshotView
        // See: https://github.com/prongbang/screen_protector/issues/32
        guard let w = window else { return }

        // Create snapshot view - may return nil if window hasn't fully rendered yet
        guard let snapshot = w.snapshotView(afterScreenUpdates: false) else {
            // Fallback: Create a simple blur view covering the window instead
            let fallbackBlur = UIView(frame: w.bounds)
            let blurEffect = UIBlurEffect(style: style)
            let blurBackground = UIVisualEffectView(effect: blurEffect)
            blurBackground.frame = fallbackBlur.bounds
            fallbackBlur.addSubview(blurBackground)
            screenBlur = fallbackBlur
            w.addSubview(fallbackBlur)
            return
        }

        screenBlur = snapshot
        let blurEffect = UIBlurEffect(style: style)
        let blurBackground = UIVisualEffectView(effect: blurEffect)
        blurBackground.frame = snapshot.bounds
        snapshot.addSubview(blurBackground)
        w.addSubview(snapshot)
    }

    public func disableBlurScreen() {
        screenBlur?.removeFromSuperview()
        screenBlur = nil
    }

    public func enabledColorScreen(hexColor: String) {
        guard let w = window else { return }
        screenColor = UIView(frame: w.bounds)
        guard let view = screenColor else { return }
        view.backgroundColor = UIColor(hexString: hexColor)
        w.addSubview(view)
    }

    public func disableColorScreen() {
        screenColor?.removeFromSuperview()
        screenColor = nil
    }

    public func enabledImageScreen(named: String) {
        guard let w = window else { return }
        let imageView = UIImageView(frame: w.bounds)
        imageView.image = UIImage(named: named)
        imageView.isUserInteractionEnabled = false
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        screenImage = imageView
        w.addSubview(imageView)
    }

    public func disableImageScreen() {
        screenImage?.removeFromSuperview()
        screenImage = nil
    }

    public func removeObserver(observer: NSObjectProtocol?) {
        guard let obs = observer else { return }
        NotificationCenter.default.removeObserver(obs)
    }

    public func removeScreenshotObserver() {
        if screenshotObserve != nil {
            removeObserver(observer: screenshotObserve)
            screenshotObserve = nil
        }
    }

    public func removeScreenRecordObserver() {
        if screenRecordObserve != nil {
            removeObserver(observer: screenRecordObserve)
            screenRecordObserve = nil
        }
    }

    public func removeAllObserver() {
        removeScreenshotObserver()
        removeScreenRecordObserver()
    }

    public func screenshotObserver(using onScreenshot: @escaping () -> Void) {
        screenshotObserve = NotificationCenter.default.addObserver(
            forName: UIApplication.userDidTakeScreenshotNotification,
            object: nil,
            queue: OperationQueue.main
        ) { notification in
            onScreenshot()
        }
    }

    @available(iOS 11.0, *)
    public func screenRecordObserver(using onScreenRecord: @escaping (Bool) -> Void) {
        screenRecordObserve = NotificationCenter.default.addObserver(
            forName: UIScreen.capturedDidChangeNotification,
            object: nil,
            queue: OperationQueue.main
        ) { notification in
            let isCaptured = UIScreen.main.isCaptured
            onScreenRecord(isCaptured)
        }
    }

    @available(iOS 11.0, *)
    public func screenIsRecording() -> Bool {
        return UIScreen.main.isCaptured
    }
}

// MARK: - UIColor Extension for hex string support
extension UIColor {
    convenience init(hexString: String) {
        var hexSanitized = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)

        let r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
        let b = CGFloat(rgb & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
}
