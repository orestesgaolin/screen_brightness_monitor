import 'dart:async';

import 'brightness_monitor.dart';
import 'screen_brightness_monitor_ios.g.dart';

/// iOS implementation of [BrightnessMonitor] backed by a swiftgen-generated
/// [ScreenBrightnessMonitor].
class BrightnessMonitorIos implements BrightnessMonitor {
  late final ScreenBrightnessMonitor _native;
  StreamController<int>? _controller;
  BrightnessCallback? _callback;

  /// Creates a [BrightnessMonitorIos].
  BrightnessMonitorIos() {
    _native = ScreenBrightnessMonitor();
  }

  @override
  /// Returns the current screen brightness (0–255).
  int get brightness => _native.brightness;

  @override
  /// A broadcast stream that emits brightness values whenever the system
  /// screen brightness setting changes.
  Stream<int> get onBrightnessChanged {
    _controller ??= StreamController<int>.broadcast(
      onListen: _startObserving,
      onCancel: _stopObserving,
    );
    return _controller!.stream;
  }

  void _startObserving() {
    _callback = BrightnessCallback$Builder.implementAsListener(
      onBrightnessChanged_: (brightness) {
        _controller?.add(brightness);
      },
    );
    _native.startObservingWithCallback(_callback!);
  }

  void _stopObserving() {
    _native.stopObserving();
    _callback = null;
  }

  @override
  /// Releases all native resources. After calling this, the monitor should
  /// not be used.
  void dispose() {
    _stopObserving();
    _controller?.close();
    _controller = null;
  }
}
