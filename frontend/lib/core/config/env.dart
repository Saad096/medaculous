/// Central dev/prod switch + API base URL, overridable at build/run time via
/// --dart-define so the same code ships against localhost, a staging VM, or
/// production without editing source (mirrors the backend's APP_BASE_URL).
///
/// Physical device over USB: `adb reverse tcp:8000 tcp:8000` makes the
/// device's localhost:8000 reach the host machine's backend — no LAN IP or
/// code change needed. Android emulator: use 10.0.2.2 instead of localhost.
class Env {
  Env._();

  static const String flavor = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'dev',
  );

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8000/api/v1',
  );

  // OAuth client IDs — empty until the project owner provides real values
  // (see docs/OPEN_QUESTIONS.md "Credentials / accounts"). The sign-in code
  // paths handle empty values gracefully (GoogleSignIn falls back to
  // platform config files; backend returns 501 for unconfigured providers)
  // rather than crashing, so this is safe to ship before secrets land.
  static const String googleClientIdIos = String.fromEnvironment(
    'GOOGLE_CLIENT_ID_IOS',
  );
  static const String googleServerClientId = String.fromEnvironment(
    'GOOGLE_CLIENT_ID',
  );
  static const String appleServiceId = String.fromEnvironment(
    'APPLE_SERVICE_ID',
  );
  static const String appleRedirectUri = String.fromEnvironment(
    'APPLE_REDIRECT_URI',
  );

  static bool get isDev => flavor == 'dev';
  static bool get isProd => flavor == 'prod';
}
