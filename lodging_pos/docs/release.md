# Releasing the owner's app (Android)

The owner's app is installed by hand from a release APK. It isn't on the Play Store before go-live, and the web build is compiled in CI but not hosted.

Building the APK needs the Android SDK: install Android Studio once (its setup installs the SDK), then check with `flutter doctor` that "Android toolchain" is ticked.

## The upload key (once)

The APK is signed with an upload key that only you hold. **Lose it and the installed app can't be updated**: a new key means uninstalling the app (and signing in again) on every phone.

1. Create it with `keytool` (it comes with the JDK; in Android Studio's folder it is `jbr\bin\keytool.exe`). Run this outside the repo, e.g. in `%USERPROFILE%\keys`:

   ```bash
   keytool -genkeypair -v -keystore upload-keystore.jks -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```

   It asks for a keystore password, your name and organisation, and a key password (press Enter to use the same one).

2. **Back it up in two places**, both away from this PC, e.g. an encrypted USB drive kept at home and a password manager that stores files. Back up the `.jks` file **and** its passwords together. Test that a backup opens:

   ```bash
   keytool -list -keystore upload-keystore.jks
   ```

3. Create `lodging_pos/android/key.properties` (never committed: `.gitignore` blocks `key.properties`, `*.jks` and `*.keystore`):

   ```properties
   storePassword=<the keystore password>
   keyPassword=<the key password>
   keyAlias=upload
   storeFile=C:\Users\<you>\keys\upload-keystore.jks
   ```

   Backslashes are doubled. Don't put the key or this file in the repo, a chat or a ticket.

## Building and installing

```bash
flutter build apk --release -t lib/main_owner.dart --dart-define-from-file=secrets.json
```

The APK is `build\app\outputs\flutter-apk\app-release.apk`. Copy it to the phone (USB or a private share), open it and allow installing from that source. To update, build again with a higher `version` in `pubspec.yaml` and install over the old one; the owner stays signed in.

Without `android/key.properties` the release build is signed with the debug key (`android/app/build.gradle.kts`). That is what CI builds (job `owner-app-build`, which also compiles the web build and keeps nothing). **Never install a debug-signed APK on the owner's phone**: the next properly signed one won't install over it.

## Before go-live (hardening)

- Show the app version on More's account card ("Android app 1.0"; needs `package_info_plus`).

## Checking a build

```bash
keytool -printcert -jarfile build\app\outputs\flutter-apk\app-release.apk
```

The owner shown must be yours (the name you gave keytool), not "Android Debug".
