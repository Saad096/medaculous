import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/providers/auth_providers.dart';
import '../../data/formulary_api.dart';

final formularyApiProvider = Provider<FormularyApi>(
  (ref) => FormularyApi(ref.read(apiClientProvider).dio),
);
