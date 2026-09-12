import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/admin/presentation/screens/admin_dashboard_screen.dart';
import '../../features/auth/presentation/providers/auth_providers.dart';
import '../../features/auth/presentation/screens/forgot_password_screen.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/onboarding_screen.dart';
import '../../features/auth/presentation/screens/register_screen.dart';
import '../../features/auth/presentation/screens/reset_password_screen.dart';
import '../../features/auth/presentation/screens/otp_verify_screen.dart';
import '../../features/auth/presentation/screens/splash_screen.dart';
import '../../features/ai/presentation/screens/chat_screen.dart';
import '../../features/home/presentation/screens/home_screen.dart';
import '../../features/home/presentation/screens/global_search_screen.dart';
import '../../features/settings/presentation/screens/settings_screen.dart';
import '../../features/notes/domain/note.dart';
import '../../features/notes/presentation/screens/note_editor_screen.dart';
import '../../features/notes/presentation/screens/notes_list_screen.dart';
import '../../features/calculator/presentation/screens/calculator_screen.dart';
import '../../features/osce/presentation/screens/osce_list_screen.dart';
import '../../features/formulary/presentation/screens/drug_detail_screen.dart';
import '../../features/formulary/presentation/screens/formulary_list_screen.dart';
import '../../features/knowledge_hub/presentation/screens/knowledge_hub_list_screen.dart';
import '../../features/knowledge_hub/presentation/screens/pdf_viewer_screen.dart';
import '../../features/exam_planner/presentation/screens/exam_planner_screen.dart';
import '../../features/pharmacy/presentation/screens/drug_recommendations_screen.dart';
import '../../features/ward/presentation/screens/ward_companion_screen.dart';
import '../../features/symptoms/presentation/screens/symptom_checker_screen.dart';
import '../../features/systems/presentation/screens/disease_detail_screen.dart';
import '../../features/systems/presentation/screens/disease_list_screen.dart';
import '../../features/systems/presentation/screens/disease_search_screen.dart';
import '../../features/systems/presentation/screens/systems_list_screen.dart';
import '../storage/local_prefs.dart';

const _publicRoutes = {
  '/onboarding',
  '/login',
  '/register',
  '/verify-email',
  '/forgot-password',
  '/reset-password',
};

/// Bridges Riverpod's StateNotifier to go_router's ChangeNotifier-based
/// refreshListenable, so a login/logout re-runs `redirect` without rebuilding
/// the whole router (which would otherwise reset the navigation stack).
class _RouterRefreshNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}

final _routerRefreshProvider = Provider<_RouterRefreshNotifier>((ref) {
  final notifier = _RouterRefreshNotifier();
  ref.listen(authControllerProvider, (_, _) => notifier.notify());
  ref.onDispose(notifier.dispose);
  return notifier;
});

final routerProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = ref.watch(_routerRefreshProvider);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refreshNotifier,
    redirect: (context, state) async {
      final authState = ref.read(authControllerProvider);
      final loc = state.matchedLocation;

      if (authState.status == AuthStatus.checking) {
        return loc == '/splash' ? null : '/splash';
      }

      if (authState.status == AuthStatus.unauthenticated) {
        if (loc == '/splash') {
          final seenOnboarding = await LocalPrefs().hasSeenOnboarding();
          return seenOnboarding ? '/login' : '/onboarding';
        }
        return _publicRoutes.contains(loc) ? null : '/login';
      }

      // authenticated
      if (loc == '/splash' || _publicRoutes.contains(loc)) return '/home';
      if (loc == '/admin' && authState.user?.isAdmin != true) return '/home';
      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/verify-email',
        builder: (context, state) =>
            OtpVerifyScreen(email: state.extra as String),
      ),
      GoRoute(
        path: '/forgot-password',
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: '/reset-password',
        builder: (context, state) =>
            ResetPasswordScreen(email: state.extra as String),
      ),
      GoRoute(path: '/home', builder: (context, state) => const HomeScreen()),
      GoRoute(path: '/search', builder: (context, state) => const GlobalSearchScreen()),
      GoRoute(path: '/settings', builder: (context, state) => const SettingsScreen()),
      GoRoute(path: '/admin', builder: (context, state) => const AdminDashboardScreen()),
      GoRoute(
        path: '/ai-chat',
        builder: (context, state) => const ChatScreen(),
      ),
      GoRoute(
        path: '/notes',
        builder: (context, state) => const NotesListScreen(),
      ),
      GoRoute(
        path: '/notes/editor',
        builder: (context, state) {
          // `extra` is either a plain Note? (existing flows — notes list, and
          // opened without a note extra means "new note in no folder") or a
          // map used by entry points that need something other than that
          // default: {note, folderId, folderBreadcrumb} pre-files a
          // brand-new note into a specific folder, and {diseaseId,
          // diseaseNoteContentHtml, folderBreadcrumb} opens a disease
          // topic's single private note instead (see
          // disease_detail_screen.dart).
          final extra = state.extra;
          if (extra is Map) {
            return NoteEditorScreen(
              note: extra['note'] as Note?,
              initialFolderId: extra['folderId'] as String?,
              folderBreadcrumb: extra['folderBreadcrumb'] as String?,
              autoFocus: extra['autoFocus'] as bool? ?? false,
              diseaseId: extra['diseaseId'] as String?,
              diseaseNoteContentHtml: extra['diseaseNoteContentHtml'] as String?,
            );
          }
          return NoteEditorScreen(note: extra as Note?);
        },
      ),
      GoRoute(
        path: '/symptom-checker',
        builder: (context, state) => const SymptomCheckerScreen(),
      ),
      GoRoute(
        path: '/drug-recommendations',
        builder: (context, state) => const DrugRecommendationsScreen(),
      ),
      GoRoute(
        path: '/formulary',
        builder: (context, state) => const FormularyListScreen(),
      ),
      GoRoute(
        path: '/knowledge-hub',
        builder: (context, state) => const KnowledgeHubListScreen(),
      ),
      GoRoute(
        path: '/ward-companion',
        builder: (context, state) => const WardCompanionScreen(),
      ),
      GoRoute(
        path: '/exam-planner',
        builder: (context, state) => const ExamPlannerScreen(),
      ),
      GoRoute(
        path: '/osce',
        builder: (context, state) => const OsceListScreen(),
      ),
      GoRoute(
        path: '/calculator',
        builder: (context, state) => const CalculatorScreen(),
      ),
      GoRoute(
        path: '/knowledge-hub/pdfs/:pdfId',
        builder: (context, state) {
          // `extra` is either a plain filename String (normal library tap) or
          // a {filename, initial_page} map (jumping in from a content-search
          // hit — see KnowledgeHubListScreen) — support both shapes.
          final extra = state.extra;
          final filename = extra is Map
              ? extra['filename'] as String?
              : extra as String?;
          final initialPage = extra is Map
              ? extra['initial_page'] as int?
              : null;
          return PdfViewerScreen(
            pdfId: state.pathParameters['pdfId']!,
            filename: filename,
            initialPage: initialPage,
          );
        },
      ),
      GoRoute(
        path: '/formulary/drugs/:drugId',
        builder: (context, state) => DrugDetailScreen(
          drugId: state.pathParameters['drugId']!,
          genericName: state.extra as String?,
        ),
      ),
      GoRoute(
        path: '/systems',
        builder: (context, state) => const SystemsListScreen(),
      ),
      GoRoute(
        path: '/systems/search',
        builder: (context, state) => const DiseaseSearchScreen(),
      ),
      GoRoute(
        path: '/systems/:systemId',
        builder: (context, state) => DiseaseListScreen(
          systemId: state.pathParameters['systemId']!,
          systemName: state.extra as String?,
        ),
      ),
      GoRoute(
        path: '/diseases/:diseaseId',
        builder: (context, state) => DiseaseDetailScreen(
          diseaseId: state.pathParameters['diseaseId']!,
          diseaseName: state.extra as String?,
        ),
      ),
    ],
  );
});
