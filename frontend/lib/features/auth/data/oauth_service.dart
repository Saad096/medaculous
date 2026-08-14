import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../../core/config/env.dart';

/// Thrown when the user backs out of the native sign-in sheet — callers
/// should treat this as a silent no-op, not an error to display.
class OAuthCancelledException implements Exception {}

/// Thrown when the real OAuth client IDs haven't been configured yet (see
/// docs/OPEN_QUESTIONS.md "Credentials / accounts") — callers should show a
/// friendly "coming soon" message rather than the raw SDK error text.
class OAuthNotConfiguredException implements Exception {}

class AppleSignInResult {
  const AppleSignInResult({required this.identityToken, this.fullName});

  final String identityToken;
  final String? fullName;
}

/// Wraps the native Google/Apple SDKs. Kept separate from AuthRepository so
/// the repository's job stays "coordinate API + token storage" — this class
/// owns the platform-SDK plumbing (id token retrieval), nothing else.
class OAuthService {
  bool _googleInitialized = false;

  Future<void> _ensureGoogleInitialized() async {
    if (_googleInitialized) return;
    await GoogleSignIn.instance.initialize(
      clientId: Env.googleClientIdIos.isEmpty ? null : Env.googleClientIdIos,
      serverClientId: Env.googleServerClientId.isEmpty
          ? null
          : Env.googleServerClientId,
    );
    _googleInitialized = true;
  }

  /// Returns a Google ID token suitable for POST /auth/google.
  Future<String> signInWithGoogle() async {
    await _ensureGoogleInitialized();
    try {
      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) {
        throw StateError('Google did not return an ID token for this account.');
      }
      return idToken;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw OAuthCancelledException();
      }
      if (e.code == GoogleSignInExceptionCode.clientConfigurationError ||
          e.code == GoogleSignInExceptionCode.providerConfigurationError) {
        throw OAuthNotConfiguredException();
      }
      rethrow;
    }
  }

  /// Returns an Apple identity token (+ display name, only ever sent by Apple
  /// on the very first authorization) suitable for POST /auth/apple.
  Future<AppleSignInResult> signInWithApple() async {
    // The Service ID (~= client ID) is required for the web-redirect flow that
    // Android and web use — iOS/macOS use the native Apple ID sheet instead and
    // don't need it. Checked up front so an unconfigured Android build fails
    // with a clear signal instead of an opaque platform-channel error.
    final needsServiceId =
        kIsWeb || defaultTargetPlatform == TargetPlatform.android;
    if (needsServiceId && Env.appleServiceId.isEmpty) {
      throw OAuthNotConfiguredException();
    }
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        webAuthenticationOptions: Env.appleServiceId.isEmpty
            ? null
            : WebAuthenticationOptions(
                clientId: Env.appleServiceId,
                redirectUri: Uri.parse(Env.appleRedirectUri),
              ),
      );
      final identityToken = credential.identityToken;
      if (identityToken == null) {
        throw StateError('Apple did not return an identity token.');
      }
      final fullName = [
        credential.givenName,
        credential.familyName,
      ].where((s) => s != null && s.trim().isNotEmpty).join(' ');
      return AppleSignInResult(
        identityToken: identityToken,
        fullName: fullName.isEmpty ? null : fullName,
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        throw OAuthCancelledException();
      }
      rethrow;
    }
  }
}
