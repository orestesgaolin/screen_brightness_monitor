import UIKit

/// Callback protocol for screen brightness changes.
@objc public protocol BrightnessCallback {
    /// Called when the screen brightness changes.
    ///
    /// - Parameter brightness: the new brightness value (0–255).
    @objc func onBrightnessChanged(_ brightness: Int)
}

/// Monitors screen brightness and notifies registered callbacks of changes.
@objc public class ScreenBrightnessMonitor: NSObject {
    private var observer: NSObjectProtocol?
    private var callback: BrightnessCallback?

    @objc public override init() {
        super.init()
    }

    /// Returns the current screen brightness value (0–255).
    @objc public var brightness: Int {
        return Int(UIScreen.main.brightness * 255)
    }

    /// Starts observing screen brightness changes.
    ///
    /// The callback will be invoked whenever the screen brightness changes,
    /// receiving the new brightness value (0–255).
    ///
    /// Only one callback can be active at a time. Calling this method again
    /// replaces the previous callback.
    @objc public func startObserving(callback: BrightnessCallback) {
        stopObserving()

        self.callback = callback

        observer = NotificationCenter.default.addObserver(
            forName: UIScreen.brightnessDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            self.callback?.onBrightnessChanged(self.brightness)
        }
    }

    /// Stops observing screen brightness changes and removes the callback.
    @objc public func stopObserving() {
        if let observer = observer {
            NotificationCenter.default.removeObserver(observer)
        }
        observer = nil
        callback = nil
    }

    deinit {
        stopObserving()
    }
}
