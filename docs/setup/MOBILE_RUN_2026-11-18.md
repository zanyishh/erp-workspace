# Android and iPhone verification, 18 November 2026

The production Flutter entry point compiled to ARM64 machine code for Android and iPhone. Installing the native app, exercising a real keyboard and signing distribution packages remain outstanding.

| Check | Result |
| --- | --- |
| Flutter and Dart versions | Read the compiler, framework, engine and missing package sources from the selected local tool image into disposable workspace storage. All five SDK release fields matched the project lock, including the framework and engine commits. The production source and dependency lock were used without compatibility edits. |
| Android release app code | The pinned Flutter 3.47.9 frontend compiled `lib/main.dart` with the Android target, release mode and the native test service origin. Its ARM64 snapshot generator produced an AArch64 ELF shared object with the generated Dart plugin registrant. APK and AAB packaging remain unverified on this checkout. |
| iPhone release app code | The pinned frontend and iOS ARM64 snapshot generator compiled the same production entry point and generated Dart plugin registrant with the iOS target. Apple's iPhoneOS SDK assembled and linked the output as an ARM64 Mach-O dynamic library. Xcode also type-checked the app delegate using the pinned Flutter release headers and generated plugin registrar header. IPA packaging, plugin linking and signing remain unverified. |
| Native configuration | All four Android configuration tests passed. Both iOS property lists, including the Xcode project, passed `plutil -lint`. |
| Device access | The Android SDK contains platform tools. ADB could not open its local listener. The emulator executable and system images are absent. Xcode's CoreSimulator service refused device discovery. No device session completed. |
| Project build launchers | The external disk contains the selected SDK image. Mounting it from this process failed with “Device not configured.” The normal Android and iOS Flutter build commands stopped at the project SDK selector. The independent release-code checks above used the tools recovered directly from that image. |

## Mobile device walkthrough

The [GitHub workflow](../../.github/workflows/flutter-mobile.yml) runs on matching pushes, pull requests and manual dispatch. It verifies the SDK release and package lock, builds an unsigned Android release bundle and iPhone device release, and installs debug builds on an Android emulator and iPhone simulator. Its [sign-in test](../../apps/erp_client/tool/mobile/sign_in.yaml) covers invitation mode and empty-field validation.

Two additional Maestro journeys sign in to a synthetic mill using the ordinary login screen, open its navigation drawer and enter data. The [invoice journey](../../apps/erp_client/tool/mobile/company_invoice.yaml) opens the shared invoice register, creates an entry and types an item with the review action on screen. The [yarn receipt journey](../../apps/erp_client/tool/mobile/yarn_receipt.yaml) opens the knitting yarn store and enters a weight. Each saves a screenshot with its field focused. The local fixture supplies the test session, company, permissions and read responses. It rejects write operations. ERPNext posting and installed-device interactions require separate verification.

On a prepared development host, run `python3 tool/mobile/fixture_server.py` from the client directory and install the debug app on the emulator or simulator. Then run the selected suite with its app ID and platform device identifier.

```sh
maestro --device "$ANDROID_SERIAL" test -e APP_ID=org.localerp.erp_client tool/mobile/company_invoice.yaml
maestro --device "$IPHONE_UDID" test -e APP_ID=org.localerp.erpClient tool/mobile/yarn_receipt.yaml
```

Four pinned-engine widget walkthroughs at 390 × 844 passed. Both iOS and Android platform variants exercised the real workspace shell, navigation drawer, register or yarn store, and text entry with a simulated keyboard inset. The invoice action remained reachable. These walkthroughs use a synthetic session and the fixture’s response bodies.

The fixture passed 13 offline HTTP request assertions, covering authentication, session cookies, both business reads, company scope and write rejection. The workflow YAML and four Maestro YAML files parsed successfully, and all nine workflow shell blocks passed Bash syntax checking. Hosted CI and native device execution remain pending.

## Flutter verification

The full Flutter test sweep compiled all 120 test files with the pinned frontend and ran them as isolated processes on the pinned Flutter software renderer. It recorded 839 passing cases, 38 transport cases blocked when this process attempted to bind a loopback listener, and one build-variant skip. The desktop opt-out variant was also executed separately and all 14 cases in that file passed. The pinned Dart analyzer completed with zero diagnostics across the app, tests and development tools on the same source snapshot. All 372 Dart files also passed the formatter.

## Accessibility

The Apple runners forward Reduce Transparency changes to Flutter. On iOS the runner also rereads the setting on foregrounding. On the pinned SDK the separate Reduce Motion preference comes from the platform dispatcher. The Flutter accessibility observer now reads that preference and combines it with the system animation flag. The previous use of a nonexistent MediaQuery method prevented the app from compiling. [Apple accessibility settings](https://developer.apple.com/documentation/uikit/uiaccessibility)
