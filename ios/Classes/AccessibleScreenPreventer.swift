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
    // CRASH FIX: Dedicated 1×1 host window for the prevention text field.
    // The text field must NOT be a subview of the protected window, because
    // adding it there and then moving window.layer under screenPrevent.layer
    // creates a circular CALayer hierarchy:
    //   w.layer → screenPrevent.layer → secureSubLayer → w.layer (∞ loop)
    // When VoiceOver is active, UIAccessibility._accessibilityEnumerateAXDescendants
    // follows this cycle recursively until the main thread stack is exhausted,
    // triggering EXC_BAD_ACCESS / SIGSEGV ("Thread stack size exceeded due to
    // excessive recursion"). Using a separate host window breaks the cycle entirely.
    private var preventionHostWindow: UIWindow? = nil
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

    // MARK: - Private helpers

    /// Creates a tiny (1×1 pt) UIWindow that lives in the same UIWindowScene as
    /// the protected window but is otherwise invisible and inaccessible.
    /// This window is used solely to host screenPrevent so that UIKit can
    /// initialise the text field's layer sublayers without that text field
    /// being part of the protected window's view hierarchy.
    private func makePreventionHostWindow(for mainWindow: UIWindow) -> UIWindow {
        let frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        let hostWindow: UIWindow
        if #available(iOS 13.0, *), let scene = mainWindow.windowScene {
            hostWindow = UIWindow(windowScene: scene)
        } else {
            hostWindow = UIWindow(frame: frame)
        }
        hostWindow.frame = frame
        // Place behind the main app window so it never intercepts touches or rendering
        hostWindow.windowLevel = UIWindow.Level.normal - 1
        hostWindow.isHidden = false
        // Exclude entirely from the accessibility tree
        hostWindow.isAccessibilityElement = false
        hostWindow.accessibilityElementsHidden = true
        return hostWindow
    }

    /// Configure the screenshot prevention layer structure.
    /// Call this once during app initialisation.
    public func configurePreventionScreenshot() {
        guard let w = window else { return }
        guard !isConfigured else { return }

        // Step 1 – host screenPrevent in a SEPARATE 1×1 window, NOT in w.
        let hostWindow = makePreventionHostWindow(for: w)
        screenPrevent.translatesAutoresizingMaskIntoConstraints = true
        screenPrevent.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        hostWindow.addSubview(screenPrevent)
        configureAccessibility()
        // Force UIKit to create screenPrevent's layer sublayers before we rearrange them
        hostWindow.layoutIfNeeded()
        preventionHostWindow = hostWindow

        // Step 2 – rearrange CALayers to make w.layer "secure".
        // Because screenPrevent is in hostWindow (not in w), there is no circular
        // UIView parent-child relationship and therefore no circular CALayer chain.
        w.layer.superlayer?.addSublayer(screenPrevent.layer)
        if #available(iOS 17.0, *) {
            screenPrevent.layer.sublayers?.last?.addSublayer(w.layer)
        } else {
            screenPrevent.layer.sublayers?.first?.addSublayer(w.layer)
        }

        isConfigured = true
    }

    public func enabledPreventScreenshot() {
        if !isConfigured {
            configurePreventionScreenshot()
        }
        screenPrevent.isSecureTextEntry = true
        // Re-apply accessibility settings after UIKit may have rebuilt sublayers
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
