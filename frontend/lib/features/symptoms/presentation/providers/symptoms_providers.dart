import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/providers/auth_providers.dart';
import '../../data/symptoms_api.dart';

final symptomsApiProvider = Provider<SymptomsApi>(
  (ref) => SymptomsApi(ref.read(apiClientProvider).dio),
);
