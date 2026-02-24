import 'dart:async';
import 'dart:io' show Platform;

import 'brightness_monitor_android.dart';
import 'brightness_monitor_ios.dart';

/// Cross-platform screen brightness monitor.
///
/// Usage:
/// ```dart
/// final monitor = BrightnessMonitor();
/// print(monitor.brightness); // 0–255
///
/// final sub = monitor.onBrightnessChanged.listen((value) {
///   print('Brightness: $value');
/// });
///
/// // Later:
/// sub.cancel();
/// monitor.dispose();
/// ```
abstract class BrightnessMonitor {
  /// Creates a [BrightnessMonitor] for the current platform.
  factory BrightnessMonitor() {
    if (Platform.isAndroid) return BrightnessMonitorAndroid();
    if (Platform.isIOS) return BrightnessMonitorIos();
    throw UnsupportedError(
      'BrightnessMonitor is not supported on this platform.',
    );
  }

  /// Returns the current screen brightness (0–255).
  int get brightness;

  /// A broadcast stream that emits brightness values whenever the system
  /// screen brightness setting changes.
  Stream<int> get onBrightnessChanged;

  /// Releases all native resources. After calling this, the monitor should
  /// not be used.
  void dispose();
}
