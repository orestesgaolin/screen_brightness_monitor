import 'dart:io';

import 'package:ffigen/ffigen.dart' as fg;
import 'package:logging/logging.dart';
import 'package:swiftgen/swiftgen.dart';

Future<void> main() async {
  final logger = Logger('swiftgen');
  logger.onRecord.listen((record) {
    stderr.writeln('${record.level.name}: ${record.message}');
  });

  final packageRoot = Platform.script.resolve('../');

  // Resolve iOS SDK path and version manually to avoid swift2objc regex bug.
  final sdkPath = (await Process.run('xcrun', [
    '--sdk',
    'iphoneos',
    '--show-sdk-path',
  ])).stdout.toString().trim();
  final sdkVersion = (await Process.run('xcrun', [
    '--sdk',
    'iphoneos',
    '--show-sdk-version',
  ])).stdout.toString().trim();

  await SwiftGenerator(
    target: Target(
      triple: 'arm64-apple-ios$sdkVersion',
      sdk: Uri.directory(sdkPath),
    ),
    inputs: [
      ObjCCompatibleSwiftFileInput(
        files: [
          packageRoot.resolve('ios/Classes/ScreenBrightnessMonitor.swift'),
        ],
      ),
    ],
    output: Output(
      module: 'screen_brightness_monitor',
      dartFile: packageRoot.resolve(
        'lib/src/screen_brightness_monitor_ios.g.dart',
      ),
      objectiveCFile: packageRoot.resolve(
        'ios/Classes/screen_brightness_monitor.m',
      ),
    ),
    ffigen: FfiGeneratorOptions(
      objectiveC: fg.ObjectiveC(
        interfaces: fg.Interfaces(
          include: (decl) => decl.originalName == 'ScreenBrightnessMonitor',
        ),
        protocols: fg.Protocols(
          include: (decl) => decl.originalName == 'BrightnessCallback',
        ),
      ),
    ),
  ).generate(logger: logger);
}
