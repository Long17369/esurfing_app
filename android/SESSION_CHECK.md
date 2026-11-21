# Isolated Android lifecycle check

This opt-in debug harness uses `com.esurfing.esurfing_app.sessioncheck`.
It never reads production configuration or secure storage. A synthetic SM4
library envelope, ticket, and dummy credentials exercise the **real** native
login and keep thread against a Dart HTTP server bound only to `127.0.0.1`.
The library envelope contains parser fixture data, not executable server code.
The native post-login connectivity check still performs its normal public,
credential-free probes; this is not a test of a real campus account.

Build the current backend separately (NDK 28.2, API 24, x86_64 for the
emulator or arm64-v8a for an authorized ARM64 device,
`-DCMAKE_SHARED_LINKER_FLAGS=-Wl,-z,max-page-size=16384`) and copy its output to
an isolated `jni/x86_64/libesurfing.so` directory. Do not reuse the checked-in
JNI binaries as evidence for changed backend code. Verify every ELF LOAD
alignment and the packaged library checksum.
For ARM64 use `jni/arm64-v8a/libesurfing.so` and `-Ptarget-platform=android-arm64`.
The automated device runner below is still restricted to the x86_64 emulator.

From `android/`, with Java 21, Flutter and Android SDK configured:

```sh
./gradlew --no-daemon --max-workers=2 :app:lintDebug :app:testDebugUnitTest :app:assembleDebug
./gradlew --no-daemon --max-workers=2 \
  -PsessionCheck \
  -Ptarget=integration_test/android_session_main.dart \
  -PsessionCheckJni=/absolute/path/to/isolated/jni \
  -Ptarget-platform=android-x64 \
  assembleDebug
```

`sessionCheck` rejects release tasks and any other Dart target. Its exported
command receiver and evidence channel are absent from ordinary builds.
Conversely, this Dart target is rejected without `sessionCheck`, so a normal
production package cannot accidentally be built with the harness entrypoint.
The synthetic fixture can be regenerated with
`python3 integration_test/generate_android_fixture.py` from the app root;
this requires Python's standard library and OpenSSL with SM4 support.

Use the `:app:` prefix for complete first-party lint. An unqualified
`lintDebug` also runs each dependency's standalone library lint:
flutter_secure_storage 10.3.4 currently reports missing `USE_BIOMETRIC`
permissions in its own Java source. Do not suppress App lint or edit the
shared pub cache to hide that upstream failure.

Before installing, inspect `adb devices -l`, ABI, page size, and installed
packages. Select the authorized emulator explicitly for **every** command.
Never launch an existing production app or clear its data.

After explicitly installing the isolated APK on `emulator-5554`, the dedicated
device runner performs the scenarios below using real permission dialogs and a
real notification-shade tap. Run from the app root:

```sh
python3 integration_test/android_session_device_check.py ../.session-android
```

It requires an x86_64 device with a 16 KB page size, saves JSON snapshots and
package-scoped logcat, and finally uninstalls **only** the isolated package and
removes its own device-side UI dump. Do not point it at an unrelated device.
The output directory is a local validation artifact, not source to commit.

After installing and starting the isolated MainActivity, inspect evidence:

```sh
adb -s emulator-5554 shell run-as com.esurfing.esurfing_app.sessioncheck \
  cat files/session-check.json
adb -s emulator-5554 shell am broadcast \
  -n com.esurfing.esurfing_app.sessioncheck/com.esurfing.esurfing_app.SessionCheckReceiver \
  --es command status
```

Receiver commands: `permission` requests notifications; `wifiPermission`
requests location/nearby permission; `notification` sends the **actual active
notification's PendingIntent**; `stop` disposes the real HostClient/native
session, stops the service, and closes the loopback server. Android can block
the receiver's background launch even if a real notification tap would work.
Use the system notification shade for lifecycle acceptance. Reject and grant
permissions using the system dialog or emulator package permission controls.

Press Home and resume before one minute, once from the launcher and once from
the real notification: `destroyCalls` and `activitiesCreated` must remain unchanged,
and `recentTaskIds` must contain the same single task.
Press Home for more than one minute: Activity destruction count must increase,
`recentTaskIds` must be empty, but engine/PID/host identity must remain stable
and `/.../keep.cgi` request count must continue increasing with
`nativeKeepRunning=true`. Tap the isolated session notification:
a new Activity must attach to those same identities and the keep count must
continue increasing. Check service/notification state and logcat for crashes.
After `stop`, verify `phase=disposed`, no keep traffic, and no foreground service.
Finally uninstall only the isolated test package to remove its dummy data.
