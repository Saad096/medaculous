import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/providers/auth_providers.dart';
import '../../data/osce_api.dart';

final osceApiProvider = Provider<OsceApi>((ref) => OsceApi(ref.read(apiClientProvider).dio));
