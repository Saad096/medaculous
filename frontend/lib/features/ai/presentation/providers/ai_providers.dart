import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/providers/auth_providers.dart';
import '../../data/ai_api.dart';

final aiApiProvider = Provider<AiApi>(
  (ref) => AiApi(ref.read(apiClientProvider).dio),
);
