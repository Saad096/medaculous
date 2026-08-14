import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/providers/auth_providers.dart';
import '../../data/systems_api.dart';

final systemsApiProvider = Provider<SystemsApi>(
  (ref) => SystemsApi(ref.read(apiClientProvider).dio),
);
