import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Tokens live in the platform keystore/keychain, never in plain SharedPreferences.
class TokenStorage {
  TokenStorage() : _storage = const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _accessKey = 'access_token';
  static const _refreshKey = 'refresh_token';
  static const _cachedUserKey = 'cached_user';

  Future<void> save({required String accessToken, required String refreshToken}) async {
    await _storage.write(key: _accessKey, value: accessToken);
    await _storage.write(key: _refreshKey, value: refreshToken);
  }

  Future<String?> get accessToken => _storage.read(key: _accessKey);
  Future<String?> get refreshToken => _storage.read(key: _refreshKey);

  /// Raw `/auth/me` JSON from the last successful fetch — lets a returning
  /// session open straight into the app while offline instead of stalling on
  /// a network call that can't succeed (owner feedback, 2026-08-21: app must
  /// open with no Wifi/data).
  Future<void> saveCachedUser(String json) => _storage.write(key: _cachedUserKey, value: json);
  Future<String?> get cachedUser => _storage.read(key: _cachedUserKey);

  Future<void> clear() async {
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
    await _storage.delete(key: _cachedUserKey);
  }
}
