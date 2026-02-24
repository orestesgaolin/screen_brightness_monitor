# Best Practices for jnigen & swiftgen in Flutter FFI Plugins

Lessons learned from building a cross-platform screen brightness monitor plugin.

---

## 1. Project Layout

```
my_plugin/
├── pubspec.yaml
├── lib/
│   ├── my_plugin.dart                      # Barrel export
│   └── src/
│       ├── my_widget.dart                  # Abstract class + factory (public API)
│       ├── my_widget_android.dart          # Android impl (imports .g.dart)
│       ├── my_widget_ios.dart              # iOS impl (imports _ios.g.dart)
│       ├── my_widget.g.dart                # jnigen output (DO NOT EDIT)
│       └── my_widget_ios.g.dart            # swiftgen/ffigen output (DO NOT EDIT)
├── android/
│   ├── build.gradle
│   └── src/main/java/com/example/
│       ├── MyWidget.kt                     # Native Kotlin code
│       └── MyCallback.kt                   # Callback interface
├── ios/
│   ├── my_plugin.podspec
│   └── Classes/
│       ├── MyWidget.swift                  # Native Swift code
│       └── my_widget.m                     # swiftgen output (DO NOT EDIT)
└── tool/
    ├── jnigen.dart                         # Android bindings generator script
    └── swiftgen.dart                       # iOS bindings generator script
```

### Key conventions
- Put generator scripts in `tool/` — run them with `dart run tool/jnigen.dart`.
- Generated files use `.g.dart` suffix and live alongside handwritten Dart code in `lib/src/`.
- Native source lives in `android/src/main/java/...` (Kotlin) and `ios/Classes/` (Swift).
- The podspec's `s.source_files = 'Classes/**/*'` picks up both `.swift` and the generated `.m` file automatically.

---

## 2. pubspec.yaml Setup

```yaml
dependencies:
  jni: ^0.15.2           # Android JNI runtime
  objective_c: ^9.3.0    # iOS ObjC runtime (version must match swiftgen's constraint)

dev_dependencies:
  jnigen: ^0.15.0        # Android code generator
  swiftgen: ^0.1.2       # iOS code generator (pulls in swift2objc + ffigen)
  ffigen: ^20.1.1        # Used by swiftgen internally, also needed for config types
  logging: ^1.3.0        # For swiftgen logger

flutter:
  plugin:
    platforms:
      android:
        ffiPlugin: true   # Required — tells Flutter to load native .so
      ios:
        ffiPlugin: true   # Required — tells Flutter to load native dylib
```

> **Gotcha**: `objective_c` version must be compatible with `swiftgen`'s transitive constraint. Run `flutter pub get` early to catch conflicts.

---

## 3. jnigen (Android)

### 3.1 Generator Script (`tool/jnigen.dart`)

```dart
import 'dart:io';
import 'package:jnigen/jnigen.dart';

void main(List<String> args) {
  final packageRoot = Platform.script.resolve('../');
  generateJniBindings(Config(
    outputConfig: OutputConfig(
      dartConfig: DartCodeOutputConfig(
        path: packageRoot.resolve('lib/src/my_plugin.g.dart'),
        structure: OutputStructure.singleFile,
      ),
    ),
    androidSdkConfig: AndroidSdkConfig(
      addGradleDeps: true,
      androidExample: 'example',     // Points to example app for Gradle resolution
    ),
    sourcePath: [packageRoot.resolve('android/src/main/java/')],
    classes: [
      'com.example.MyCallback',       // List ALL classes to bind
      'com.example.MyPlugin',
    ],
  ));
}
```

### 3.2 Callback Interfaces — Use Kotlin Interfaces, Not Lambdas

**Bad** — `(Int) -> Unit` lambdas require internal JNI APIs (`ProtectedJniExtensions`, `MethodInvocation`, `JImplementer`) to proxy from Dart:

```kotlin
// ❌ Generates kotlin.jvm.functions.Function1 — no high-level Dart proxy
fun startObserving(callback: (Int) -> Unit)
```

**Good** — Define a dedicated Kotlin interface. jnigen generates a clean `implement()` method and `$Mixin`:

```kotlin
// ✅ Generates BrightnessCallback.implement($BrightnessCallback(...))
@Keep
interface BrightnessCallback {
    @Keep
    fun onBrightnessChanged(brightness: Int)
}
```

Then in Dart:
```dart
final callback = BrightnessCallback.implement(
  $BrightnessCallback(
    onBrightnessChanged: (brightness) { /* ... */ },
    onBrightnessChanged$async: true,  // Non-blocking (listener pattern)
  ),
);
native.startObserving(callback);
```

### 3.3 The `$async: true` Flag

For callbacks invoked from native threads (observers, listeners), add `$async: true` to each method in the `$Mixin` constructor. Without it, the callback blocks the native caller until Dart completes — which deadlocks if Dart is on the same thread.

```dart
$BrightnessCallback(
  onBrightnessChanged: (b) { controller.add(b); },
  onBrightnessChanged$async: true,  // ← Critical for observer/listener patterns
)
```

### 3.4 Annotate with `@Keep`

ProGuard/R8 strips unreferenced classes. Annotate every class, interface, property, and method that jnigen binds:

```kotlin
@Keep
class ScreenBrightnessMonitor(private val context: Context) {
    @get:Keep          // For Kotlin properties, use @get:Keep
    val brightness: Int
        get() = /* ... */

    @Keep
    fun startObserving(callback: BrightnessCallback) { /* ... */ }
}
```

### 3.5 Build Before Generating

jnigen resolves classes from compiled `.class` files. If your Kotlin code isn't compiled yet, you'll get `"Not found"` errors:

```bash
# Build the example app first (compiles plugin Kotlin code)
cd example && flutter build apk --release
# Then generate
cd .. && dart run tool/jnigen.dart
```

### 3.6 Getting Android Context

Access the application context in Dart via `jni.Jni.androidApplicationContext` — no need to pass it from the Flutter engine:

```dart
import 'package:jni/jni.dart' as jni;

final context = jni.Jni.androidApplicationContext;
final monitor = ScreenBrightnessMonitor(context);
```

### 3.7 Memory Management

Call `.release()` on JNI objects when done to free the JNI global reference:

```dart
void dispose() {
  native.stopObserving();
  callback?.release();
  native.release();
}
```

---

## 4. swiftgen (iOS)

### 4.1 Generator Script (`tool/swiftgen.dart`)

```dart
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

  // ⚠️ Workaround: swift2objc's _parseVersion regex can fail on certain
  // SDK version formats (e.g. "26.2"). Resolve SDK path/version manually:
  final sdkPath = (await Process.run('xcrun', [
    '--sdk', 'iphoneos', '--show-sdk-path',
  ])).stdout.toString().trim();
  final sdkVersion = (await Process.run('xcrun', [
    '--sdk', 'iphoneos', '--show-sdk-version',
  ])).stdout.toString().trim();

  await SwiftGenerator(
    target: Target(
      triple: 'arm64-apple-ios$sdkVersion',
      sdk: Uri.directory(sdkPath),
    ),
    inputs: [
      ObjCCompatibleSwiftFileInput(
        files: [
          packageRoot.resolve('ios/Classes/MyWidget.swift'),
        ],
      ),
    ],
    output: Output(
      module: 'my_plugin',
      dartFile: packageRoot.resolve('lib/src/my_plugin_ios.g.dart'),
      objectiveCFile: packageRoot.resolve('ios/Classes/my_plugin.m'),
    ),
    ffigen: FfiGeneratorOptions(
      objectiveC: fg.ObjectiveC(
        interfaces: fg.Interfaces(
          include: (decl) => decl.originalName == 'MyWidget',
        ),
        protocols: fg.Protocols(
          include: (decl) => decl.originalName == 'MyCallback',
        ),
      ),
    ),
  ).generate(logger: logger);
}
```

### 4.2 `ObjCCompatibleSwiftFileInput` vs `SwiftFileInput`

- **`SwiftFileInput`**: For pure Swift code. swift2objc wraps it in ObjC-compatible wrappers.
- **`ObjCCompatibleSwiftFileInput`**: For Swift code that's **already `@objc` annotated**. Skips the wrapping step — simpler, fewer surprises. **Prefer this when you control the Swift code.**

### 4.3 Writing ObjC-Compatible Swift

All types exposed to Dart must be `@objc` annotated and inherit from `NSObject` (for classes):

```swift
// Protocol — callback interface
@objc public protocol BrightnessCallback {
    @objc func onBrightnessChanged(_ brightness: Int)
}

// Class — must inherit NSObject
@objc public class ScreenBrightnessMonitor: NSObject {
    @objc public override init() { super.init() }

    @objc public var brightness: Int { /* ... */ }

    @objc public func startObserving(callback: BrightnessCallback) { /* ... */ }
    @objc public func stopObserving() { /* ... */ }
}
```

**Rules:**
- Classes must inherit `NSObject` (direct or indirect).
- Use `@objc public` on everything ffigen should see.
- Overriding `init()` requires `override` + calling `super.init()`.
- Only ObjC-compatible types work: `Int`, `String`, `Bool`, `NSObject` subclasses, protocols. No Swift structs, enums with associated values, or generics.

### 4.4 ffigen Include Filters

By default, ffigen generates bindings for **everything** in the ObjC header. Use `include` filters to limit output to your types only:

```dart
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
```

Without filters, you'll get bindings for `NSObject`, `NSString`, etc. — hundreds of unnecessary lines.

### 4.5 Implementing ObjC Protocols in Dart

swiftgen/ffigen generates three flavors for each protocol:

| Method | Use When |
|--------|----------|
| `implement(...)` | Callback runs synchronously, blocking the ObjC caller until Dart returns |
| `implementAsListener(...)` | **Callback is non-blocking** — ObjC caller continues immediately (use for observers/notifications) |
| `implementAsBlocking(...)` | Callback blocks the ObjC thread and waits for Dart to complete |

For observer/notification patterns, always use `implementAsListener`:

```dart
final callback = BrightnessCallback$Builder.implementAsListener(
  onBrightnessChanged_: (brightness) {
    controller.add(brightness);
  },
);
native.startObservingWithCallback(callback);
```

### 4.6 SDK Version Workaround

`Target.iOSArm64Latest()` may crash with `FormatException` if swift2objc's `_parseVersion` regex can't parse your Xcode SDK version string. The workaround is to resolve the SDK path and version manually via `xcrun` and construct the `Target` directly (see generator script above).

### 4.7 Generated Files

swiftgen produces **two** files:
1. **Dart bindings** (`lib/src/..._ios.g.dart`) — extension types wrapping ObjC objects
2. **ObjC bindings** (`ios/Classes/....m`) — C functions that ffigen's Dart code calls via `dart:ffi`

Both must be committed. The `.m` file must be in a location picked up by the podspec (`Classes/**/*`).

---

## 5. Cross-Platform Dart Wrapper

### 5.1 Abstract Class + Factory Constructor

**Don't use conditional imports** with `dart.library.android` / `dart.library.ios` — those libraries don't exist. Use `dart:io`'s `Platform` at runtime:

```dart
// lib/src/brightness_monitor.dart
import 'dart:io' show Platform;
import 'brightness_monitor_android.dart';
import 'brightness_monitor_ios.dart';

abstract class BrightnessMonitor {
  factory BrightnessMonitor() {
    if (Platform.isAndroid) return BrightnessMonitorAndroid();
    if (Platform.isIOS) return BrightnessMonitorIos();
    throw UnsupportedError('Unsupported platform');
  }

  int get brightness;
  Stream<int> get onBrightnessChanged;
  void dispose();
}
```

Each platform file imports only its own generated bindings, so platform-specific `dart:ffi` symbols don't conflict.

### 5.2 Barrel Export

Keep the public barrel export minimal — only export the high-level wrapper:

```dart
// lib/my_plugin.dart
export 'src/brightness_monitor.dart';
```

Don't export `_ios.g.dart` or `.g.dart` directly unless users need low-level access.

---

## 6. Android vs iOS API Comparison

| Concern | jnigen (Android) | swiftgen (iOS) |
|---------|-------------------|----------------|
| **Callback definition** | Kotlin `interface` | Swift `@objc protocol` |
| **Callback creation** | `MyCallback.implement($MyCallback(...))` | `MyCallback$Builder.implementAsListener(...)` |
| **Async/non-blocking** | `method$async: true` in `$Mixin` | `implementAsListener(...)` variant |
| **Context/init** | Pass `Context` via `Jni.androidApplicationContext` | No context needed; `init()` or default constructor |
| **Memory** | `.release()` to free JNI global ref | Automatic (ARC via ObjC runtime) |
| **Native superclass** | Any Java/Kotlin class | Must extend `NSObject` |
| **Allowed types** | Any JNI-compatible type | ObjC-compatible types only (no Swift structs/generics) |

---

## 7. Common Gotchas

1. **`@Keep` everywhere (Android)** — Without it, R8 strips your classes and jnigen bindings crash at runtime with `ClassNotFoundException`.

2. **Build before jnigen** — jnigen reads compiled `.class` files from the Gradle build. If you add a new class, rebuild (`flutter build apk`) before regenerating.

3. **`objective_c` version conflicts** — `swiftgen` transitively depends on a specific `objective_c` version range. Always check compatibility before pinning your own version.

4. **ObjC method name mangling (iOS)** — Swift `func startObserving(callback:)` becomes `startObservingWithCallback:` in ObjC (and thus in the Dart binding). Check the generated `.g.dart` for actual method names.

5. **Podspec `source_files`** — Must include both the Swift source and the generated `.m` file. `Classes/**/*` covers both.

6. **No `dart.library.android`** — Conditional imports only support `dart.library.io` (native), `dart.library.html`, and `dart.library.js`. Use runtime `Platform` checks instead.

7. **`weak` callback references (iOS) — use strong `var`** — If your Swift class holds the protocol callback as `weak var`, ARC deallocates the ObjC proxy object created by `implementAsListener` immediately after `startObserving` returns, because nothing else retains it. The `callback?.method()` optional chain then silently no-ops. **Always use `private var callback` (strong), not `weak var`**, since the Swift side is the intended owner of the proxy's lifetime.

8. **Keep a Dart-side reference to callbacks** — Even with a strong Swift reference, store the callback object in a field (`_callback`) on the Dart side too. If it's only a local variable in `_startObserving()`, the Dart GC can collect the closure backing the protocol proxy, breaking the callback silently. Clean it up in `_stopObserving()`:

    ```dart
    BrightnessCallback? _callback;

    void _startObserving() {
      _callback = BrightnessCallback$Builder.implementAsListener(
        onBrightnessChanged_: (b) { _controller?.add(b); },
      );
      _native.startObservingWithCallback(_callback!);
    }

    void _stopObserving() {
      _native.stopObserving();
      _callback = null;
    }
    ```

9. **Constructor names must match class names** — When using the abstract class + factory pattern, platform implementation classes (e.g. `BrightnessMonitorIos`) must name their constructor after their own class, not the abstract parent. A misnamed constructor compiles without error but becomes a regular method that never runs, leaving `late final` fields uninitialized:

    ```dart
    // ❌ This is a method named "BrightnessMonitor", NOT a constructor
    class BrightnessMonitorIos implements BrightnessMonitor {
      late final ScreenBrightnessMonitor _native;
      BrightnessMonitor() { _native = ScreenBrightnessMonitor(); }  // never called
    }

    // ✅ Correct — constructor matches class name
    class BrightnessMonitorIos implements BrightnessMonitor {
      late final ScreenBrightnessMonitor _native;
      BrightnessMonitorIos() { _native = ScreenBrightnessMonitor(); }
    }
    ```
