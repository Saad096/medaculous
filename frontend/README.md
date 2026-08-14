# Medaculous — Flutter app

Feature-first Flutter app (Riverpod, go_router) talking to the FastAPI backend in `../backend`.

## Local setup — running on a physical Android device (no emulator)

```bash
cd frontend
flutter pub get
```

Plug the phone in over USB with USB debugging enabled (Settings → About phone → tap
"Build number" 7 times to unlock Developer Options → enable "USB debugging" there), then
confirm it's actually detected before doing anything else:

```bash
adb devices
```

You should see your device listed as `<serial>	device` (if it says `unauthorized`
instead, look at the phone screen for an "Allow USB debugging?" prompt and accept it).
If `flutter run` picks the wrong target (Linux desktop / Chrome are always listed too
when installed — they're separate targets on the same machine, not your phone), pass
`-d <serial>` to be explicit; get the exact id from `flutter devices`.

```bash
adb reverse tcp:8000 tcp:8000      # makes the device's own localhost:8000 reach
                                    # this machine's backend — no LAN IP needed
flutter run -d <serial> --dart-define=API_BASE_URL=http://localhost:8000/api/v1
```

(Android emulator, if you ever do use one instead: `http://10.0.2.2:8000/api/v1` in
place of `localhost` — no `adb reverse` needed there.)

## Pointing at a hosted backend (IP or domain)

The API base URL is never hardcoded — it's read at build/run time from `API_BASE_URL`
(see `lib/core/config/env.dart`), so the exact same source ships against localhost, a
staging VM's IP, or a production domain just by changing this one flag:

```bash
# A hosted machine's IP address
flutter build apk --dart-define=API_BASE_URL=http://203.0.113.10:8000/api/v1

# A real domain, once one is pointed at the backend (recommended for production —
# also required if you want a plain https:// URL rather than a bare IP)
flutter build apk --dart-define=API_BASE_URL=https://api.medaculous.com/api/v1
```

For a production build, also set `APP_ENV=prod` (`Env.isProd` gates the DEV badge shown on
Home) and match the backend's own `APP_BASE_URL`/`CORS_ORIGINS` to the same host — see
`../backend/README.md`.

If you'd rather not repeat long `--dart-define` flags, put them in a JSON file and pass
`--dart-define-from-file=config/prod.json` instead (keep that file out of version control
if it ever contains anything sensitive — today it only holds a URL, not secrets).

## Building and installing an APK (sideloading, no store involved)

Same `--dart-define` rules as above apply to `flutter build` as to `flutter run`. Debug
build (fastest, includes debugging hooks, fine for internal testing):

```bash
flutter build apk --debug --dart-define=API_BASE_URL=http://localhost:8000/api/v1
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

Release build (optimized, no debugging hooks — closer to what real users would get, but
still just sideloaded, not through a store):

```bash
flutter build apk --release --dart-define=API_BASE_URL=https://api.medaculous.com/api/v1 --dart-define=APP_ENV=prod
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

`-r` reinstalls over whatever's already on the device (keeps app data); drop it for a
completely fresh install. Without a release keystore configured (see below), this
release build is still signed — just with the Flutter template's debug key, which is
fine for sideloading onto your own device but **will be rejected by the Play Store**.

## Building a signed release for the Play Store

**One-time setup — generate a real release keystore** (do this once, keep the resulting
file forever — see the warning below):

```bash
keytool -genkey -v -keystore ~/medaculous-release.jks -keyalg RSA -keysize 2048 \
  -validity 10000 -alias medaculous
```

`keytool` will ask for a keystore password and some identity questions (org name, etc. —
answer honestly but none of it is security-critical, just metadata). Then:

```bash
cd frontend/android
cp key.properties.example key.properties
```

Edit `key.properties` and fill in the real path to the `.jks` file you just created,
plus the password(s) you set. This file (and the keystore it points at) are both
gitignored — **never commit either one.**

> ⚠️ **Back this keystore up somewhere safe outside this machine** (password manager,
> encrypted cloud storage, etc.). If you ever lose it, there is no recovery path — you
> cannot publish an update to an app already live on the Play Store under the same
> listing without the exact same signing key. Losing it means starting over as a brand
> new app listing.

With `key.properties` in place, release builds are automatically signed with your real
key instead of the debug fallback — nothing else changes about the build command:

```bash
flutter build appbundle --release --dart-define=API_BASE_URL=https://api.medaculous.com/api/v1 --dart-define=APP_ENV=prod
```

This produces `build/app/outputs/bundle/release/app-release.aab` — an **App Bundle**,
which is what the Play Store requires for new app submissions (not a plain `.apk`).

**Uploading to the Play Store** (first time):
1. Create a [Google Play Console](https://play.google.com/console) account (one-time
   $25 registration fee) if you don't have one.
2. Create a new app, fill in the store listing (description, screenshots, privacy
   policy URL, content rating questionnaire, data safety form).
3. Under **Release → Production** (or Internal/Closed testing first, recommended for a
   first release), upload the `.aab` file built above.
4. Play Console will flag if the upload isn't properly signed — if that happens, confirm
   `key.properties` was actually picked up (a build log line/warning appears if it falls
   back to the debug key — re-check the file exists and its `storeFile` path is correct).
5. Every subsequent update: bump `version` in `pubspec.yaml` (format `1.0.1+2` — the
   number after `+` must increase every single release), rebuild the same
   `flutter build appbundle` command, upload again.

## iOS — Apple Developer account and the App Store

Building for iOS **requires a Mac with Xcode installed** — there is no way around this
from Ubuntu/Linux (Apple doesn't allow it), which is why this hasn't been built or
tested from this dev machine. The bundle identifier (`com.medaculous.medaculous`) is
already set in the Xcode project, ready for whenever a Mac is available. Options, in
order of how soon you'd have this working:

- **You (or someone on the team) has a Mac**: install Xcode from the App Store, clone
  this repo there, run `flutter pub get`, open `ios/Runner.xcworkspace` in Xcode once to
  let it resolve signing, then `flutter build ipa --dart-define=API_BASE_URL=...` the
  same way as the Android commands above. You'll need an
  [Apple Developer Program](https://developer.apple.com/programs/) membership ($99/year)
  to submit to the App Store (a free Apple ID is enough to run on your own device via
  Xcode, but not to publish).
- **No Mac available**: use a macOS CI service to build and even submit for you without
  ever owning a physical Mac — [Codemagic](https://codemagic.io/) (has a Flutter-specific
  free tier) or a GitHub Actions `macos-latest` runner are the common choices. Both need
  the same Apple Developer Program membership either way — the CI service replaces the
  Mac, not the Apple account.
- Once you have a Mac or CI set up, also revisit the Google/Apple Sign-In setup in
  `docs/OPEN_QUESTIONS.md` — the iOS side of that (a `CFBundleURLSchemes` entry for
  Google's redirect, and the Sign In with Apple capability/entitlement in Xcode) was
  never added since it couldn't be tested here.

Submitting to the App Store itself (once you have a build): upload via Xcode's
Organizer or `xcrun altool`/`xcrun notarytool` command line, fill in the App Store
Connect listing (similar set of screens to Play Console — description, screenshots,
privacy details), submit for review. Apple's review is manual and typically takes
1-3 days, unlike Play Store's largely automated review.

## Running tests

```bash
flutter test
```

Patrol E2E suite lives in `patrol_test/` — see its own setup notes there.
