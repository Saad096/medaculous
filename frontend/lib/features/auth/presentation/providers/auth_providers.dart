import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/storage/token_storage.dart';
import '../../data/auth_api.dart';
import '../../data/auth_repository.dart';
import '../../data/legal_api.dart';
import '../../data/oauth_service.dart';
import '../../domain/user.dart';

final tokenStorageProvider = Provider<TokenStorage>((ref) => TokenStorage());

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(tokenStorage: ref.read(tokenStorageProvider));
});

/// Wires ApiClient's session-expired callback to AuthController once both
/// exist — kept as a separate provider (rather than passed into
/// apiClientProvider's constructor) because apiClientProvider ->
/// authControllerProvider -> authRepositoryProvider -> authApiProvider ->
/// apiClientProvider would otherwise be a cyclic top-level reference, which
/// the Dart analyzer rejects even though the callback only ever fires well
/// after both providers are constructed. Read once from the app root
/// (see main.dart) to activate it.
final authWiringProvider = Provider<void>((ref) {
  ref.read(apiClientProvider).onSessionExpired = () =>
      ref.read(authControllerProvider.notifier).forceLogout();
});

final authApiProvider = Provider<AuthApi>(
  (ref) => AuthApi(ref.read(apiClientProvider).dio),
);

final oauthServiceProvider = Provider<OAuthService>((ref) => OAuthService());

final legalApiProvider = Provider<LegalApi>(
  (ref) => LegalApi(ref.read(apiClientProvider).dio),
);

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    api: ref.read(authApiProvider),
    tokenStorage: ref.read(tokenStorageProvider),
    oauthService: ref.read(oauthServiceProvider),
  );
});

enum AuthStatus { checking, authenticated, unauthenticated }

class AuthState {
  const AuthState({required this.status, this.user});

  final AuthStatus status;
  final AppUser? user;

  AuthState copyWith({AuthStatus? status, AppUser? user}) =>
      AuthState(status: status ?? this.status, user: user ?? this.user);
}

class AuthController extends StateNotifier<AuthState> {
  AuthController(this._repository)
    : super(const AuthState(status: AuthStatus.checking)) {
    _bootstrap();
  }

  final AuthRepository _repository;

  Future<void> _bootstrap() async {
    if (!await _repository.hasSession()) {
      state = const AuthState(status: AuthStatus.unauthenticated);
      return;
    }

    // No Wifi/data: skip the network round trip entirely rather than
    // stalling the splash screen through connectTimeout + retry backoff
    // (owner feedback, 2026-08-21 — app must open offline, not hang). A
    // returning session opens straight in using its last-cached profile;
    // screens that need live data show their own offline/empty states.
    final connectivity = await Connectivity().checkConnectivity();
    final offline = connectivity.every((r) => r == ConnectivityResult.none);
    if (offline) {
      final cached = await _repository.cachedUser();
      state = cached != null
          ? AuthState(status: AuthStatus.authenticated, user: cached)
          : const AuthState(status: AuthStatus.unauthenticated);
      return;
    }

    try {
      final user = await _repository.me();
      state = AuthState(status: AuthStatus.authenticated, user: user);
    } catch (_) {
      // Connectivity looked fine but the call still failed (e.g. dropped
      // mid-check) — still let a previously-seen session in offline-style
      // rather than bouncing straight to the login screen.
      final cached = await _repository.cachedUser();
      state = cached != null
          ? AuthState(status: AuthStatus.authenticated, user: cached)
          : const AuthState(status: AuthStatus.unauthenticated);
    }
  }

  void setAuthenticated(AppUser user) {
    state = AuthState(status: AuthStatus.authenticated, user: user);
  }

  Future<void> logout() async {
    await _repository.logout();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  void setUser(AppUser user) {
    state = state.copyWith(user: user);
  }

  /// Called by ApiClient when a background silent-refresh fails — the
  /// refresh token is already cleared at that point, this just updates the
  /// UI state so the router redirects to login.
  void forceLogout() {
    state = const AuthState(status: AuthStatus.unauthenticated);
  }
}

final authControllerProvider = StateNotifierProvider<AuthController, AuthState>(
  (ref) {
    return AuthController(ref.read(authRepositoryProvider));
  },
);

/// Caches the fetched avatar image bytes so every place that shows it (Home
/// header, Settings) doesn't each re-download on their own rebuild — loaded
/// once on demand via [ensureLoaded], refreshed on upload/delete, and
/// cleared on logout.
class AvatarController extends StateNotifier<Uint8List?> {
  AvatarController(this._ref, this._repository) : super(null);

  final Ref _ref;
  final AuthRepository _repository;
  bool _loaded = false;

  Future<void> ensureLoaded({required bool hasAvatar}) async {
    if (_loaded) return;
    _loaded = true;
    if (!hasAvatar) return;
    state = await _repository.getAvatarBytes();
  }

  Future<void> upload(Uint8List bytes, String filename) async {
    final updatedUser = await _repository.uploadAvatar(bytes, filename);
    _ref.read(authControllerProvider.notifier).setUser(updatedUser);
    _loaded = true;
    state = bytes;
  }

  Future<void> remove() async {
    final updatedUser = await _repository.deleteAvatar();
    _ref.read(authControllerProvider.notifier).setUser(updatedUser);
    _loaded = true;
    state = null;
  }

  void clear() {
    _loaded = false;
    state = null;
  }
}

final avatarProvider = StateNotifierProvider<AvatarController, Uint8List?>(
  (ref) => AvatarController(ref, ref.read(authRepositoryProvider)),
);
