import 'dart:async';

import 'package:jni/jni.dart' as jni;

import 'brightness_monitor.dart';
import 'screen_brightness_monitor_android.g.dart';

/// Android implementation of [BrightnessMonitor] backed by a JNI
/// [ScreenBrightnessMonitor].
class BrightnessMonitorAndroid implements BrightnessMonitor {
  late final ScreenBrightnessMonitor _native;
  StreamController<int>? _controller;
  BrightnessCallback? _callback;

  /// Creates a [BrightnessMonitorAndroid] using the application context from the
  /// current Android activity.
  BrightnessMonitorAndroid() {
    final context = jni.Jni.androidApplicationContext;
    _native = ScreenBrightnessMonitor(context);
  }

  @override
  /// Returns the current screen brightness (0–255), or -1 on error.
  int get brightness => _native.getBrightness();

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
    _callback = BrightnessCallback.implement(
      $BrightnessCallback(
        onBrightnessChanged: (brightness) {
          _controller?.add(brightness);
        },
        onBrightnessChanged$async: true,
      ),
    );
    _native.startObserving(_callback!);
  }

  void _stopObserving() {
    _native.stopObserving();
    _callback?.release();
    _callback = null;
  }

  @override
  /// Releases all native resources. After calling this, the monitor should
  /// not be used.
  void dispose() {
    _stopObserving();
    _controller?.close();
    _controller = null;
    _native.release();
  }
}
