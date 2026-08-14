import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart' show FlutterQuillLocalizations;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_providers.dart';
import 'core/widgets/offline_banner.dart';
import 'features/auth/presentation/providers/auth_providers.dart';

void main() {
  runApp(const ProviderScope(child: MedaculousApp()));
}

class MedaculousApp extends ConsumerWidget {
  const MedaculousApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(authWiringProvider);
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: 'Medaculous',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: router,
      // FlutterQuillLocalizations.delegate is required by the rich-text notes
      // editor (QuillSimpleToolbar tooltips etc.) — the Global*Localizations
      // delegates are its usual companions.
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        FlutterQuillLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en')],
      builder: (context, child) => OfflineBanner(child: child ?? const SizedBox.shrink()),
    );
  }
}
