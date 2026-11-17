# Flutter toolchain verification

The existing Flutter 3.38.7 / Dart 3.10.7 installation is at `/opt/homebrew/share/flutter`. Xcode 27.2 and CocoaPods 1.16.2 are installed. Flutter was configured to use the existing Android SDK 36 and Java 21, avoiding a duplicate installation.

```sh
flutter config --android-sdk /opt/homebrew/share/android-commandlinetools
flutter config --jdk-dir /opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home
flutter doctor -v
```

A disposable standard Flutter project was generated under `.local/toolchain_check/` for macOS, iOS, Android and Windows. It is verification scaffolding, not the future ERP app. Build logs are kept under `.local/reports/`.

## Verified Apple build settings

The installed Xcode SDKs require macOS 12.0+ and iOS 15.0+ as deployment targets. Flutter 3.38.7's sample template defaults to older versions, so the disposable sample was adjusted to these supported minimums.

The installed Apple `lipo` rejects Flutter's combined `arm64 x86_64` simulator verification command with `-verify_arch requires exactly one input file`, although it lists both slices. A direct `arm64` verification passes. The simulator sample's Debug.xcconfig therefore sets:

```text
ARCHS[sdk=iphonesimulator*] = arm64
```

The resulting native Apple Silicon simulator build passed. Intel iPhone simulator builds have not been validated. Recheck current Flutter/Xcode compatibility when creating the real app rather than carrying this workaround forward automatically. No Flutter SDK source files were patched.

The verification commands are:

```sh
cd .local/toolchain_check
flutter build macos --debug
flutter build ios --simulator --debug
flutter build apk --debug --target-platform android-arm64
```

macOS and iPhone simulator builds succeeded after these sample settings. The Android ARM64 debug APK also built successfully after Gradle installed NDK 28.2.13676358 and CMake 3.22.1. Build output was subsequently deleted to recover disk space; logs and the small verification project remain.

## Host and device limits

A Windows project was generated, but native Windows compilation requires a Windows host with Visual Studio's Desktop development with C++ workload. A physical iPhone was detected during the company invoice review. Physical-device invoice journeys and distribution signing remain open. See the private launch review. iPhone simulator build verification does not imply App Store signing or publishing readiness.

The Android SDK's standard license records are copied under `licenses/android-sdk/`. The optional microXR license was not accepted or installed; Flutter doctor can continue to mention it. The Android SDK package manager may install NDK and CMake versions required by the standard Flutter Android build.

For Android distribution, configure the business's upload keystore using the ignored `apps/erp_client/android/key.properties` with `storeFile`, `keyAlias`, `storePassword` and `keyPassword`. Relative keystore paths resolve from `android/app`. Without this configuration the release artifact is unsigned. Debug builds continue to use the local development key.
