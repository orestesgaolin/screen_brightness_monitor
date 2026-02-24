import 'dart:io';

import 'package:jnigen/jnigen.dart';

void main(List<String> args) {
  final packageRoot = Platform.script.resolve('../');
  generateJniBindings(
    Config(
      outputConfig: OutputConfig(
        dartConfig: DartCodeOutputConfig(
          path: packageRoot.resolve(
            'lib/src/screen_brightness_monitor_android.g.dart',
          ),
          structure: OutputStructure.singleFile,
        ),
      ),
      androidSdkConfig: AndroidSdkConfig(
        addGradleDeps: true,
        androidExample: 'example',
      ),
      sourcePath: [packageRoot.resolve('android/src/main/java/')],
      classes: [
        'dev.roszkowski.screen_brightness_monitor.BrightnessCallback',
        'dev.roszkowski.screen_brightness_monitor.ScreenBrightnessMonitor',
      ],
    ),
  );
}
