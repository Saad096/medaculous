import 'dart:convert';
import 'dart:typed_data';

import '../../../core/storage/token_storage.dart';
import '../domain/user.dart';
import 'auth_api.dart';
import 'oauth_service.dart';

/// Coordinates AuthApi + TokenStorage: every method that receives a token
/// pair persists it before returning, so callers never handle tokens directly.
class AuthRepository {
  AuthRepository({
    required this._api,
    required TokenStorage tokenStorage,
    required this._oauthService,
  }) : _tokenStorage = tokenStorage;

  final AuthApi _api;
  final TokenStorage _tokenStorage;
  final OAuthService _oauthService;

  Future<void> _saveTokens(Map<String, dynamic> tokenPair) =>
      _tokenStorage.save(
        accessToken: tokenPair['access_token'] as String,
        refreshToken: tokenPair['refresh_token'] as String,
      );

  Future<void> register({
    required String email,
    required String password,
    String? displayName,
  }) {
    return _api.register(
      email: email,
      password: password,
      displayName: displayName,
    );
  }

  /// Returns the newly authenticated user after a successful OTP verification.
  Future<AppUser> verifyEmail({
    required String email,
    required String code,
  }) async {
    final tokenPair = await _api.verifyEmail(email: email, code: code);
    await _saveTokens(tokenPair);
    return me();
  }

  Future<void> resendOtp({required String email}) =>
      _api.resendOtp(email: email);

  Future<AppUser> login({
    required String email,
    required String password,
  }) async {
    final tokenPair = await _api.login(email: email, password: password);
    await _saveTokens(tokenPair);
    return me();
  }

  /// Throws [OAuthCancelledException] if the user backs out of the sheet —
  /// callers should catch that specifically and no-op rather than showing
  /// an error.
  Future<AppUser> signInWithGoogle() async {
    final idToken = await _oauthService.signInWithGoogle();
    final tokenPair = await _api.googleSignIn(idToken: idToken);
    await _saveTokens(tokenPair);
    return me();
  }

  Future<AppUser> signInWithApple() async {
    final result = await _oauthService.signInWithApple();
    final tokenPair = await _api.appleSignIn(
      identityToken: result.identityToken,
      fullName: result.fullName,
    );
    await _saveTokens(tokenPair);
    return me();
  }

  Future<void> logout() async {
    final refreshToken = await _tokenStorage.refreshToken;
    if (refreshToken != null) {
      try {
        await _api.logout(refreshToken: refreshToken);
      } catch (_) {
        // Best-effort server-side revoke; clearing local tokens below is what
        // actually ends the session on this device regardless of network state.
      }
    }
    await _tokenStorage.clear();
  }

  Future<void> forgotPassword({required String email}) =>
      _api.forgotPassword(email: email);

  Future<void> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) {
    return _api.resetPassword(
      email: email,
      code: code,
      newPassword: newPassword,
    );
  }

  Future<AppUser> me() async {
    final data = await _api.me();
    await _tokenStorage.saveCachedUser(jsonEncode(data));
    return AppUser.fromJson(data);
  }

  Future<bool> hasSession() async => (await _tokenStorage.accessToken) != null;

  /// Last-known profile from a prior successful [me] call, or null if this
  /// device has never fetched one (e.g. logged in elsewhere and the token was
  /// restored without ever going online here). Used to let the app open
  /// while offline instead of blocking on a network call that will only fail.
  Future<AppUser?> cachedUser() async {
    final json = await _tokenStorage.cachedUser;
    if (json == null) return null;
    try {
      return AppUser.fromJson(jsonDecode(json) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<AppUser> uploadAvatar(Uint8List bytes, String filename) async {
    final data = await _api.uploadAvatar(bytes, filename);
    return AppUser.fromJson(data);
  }

  Future<Uint8List?> getAvatarBytes() => _api.getAvatarBytes();

  Future<AppUser> deleteAvatar() async {
    final data = await _api.deleteAvatar();
    return AppUser.fromJson(data);
  }
}
