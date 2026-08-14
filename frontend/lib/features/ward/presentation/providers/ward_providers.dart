import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/providers/auth_providers.dart';
import '../../data/ward_api.dart';

final wardApiProvider = Provider<WardApi>((ref) => WardApi(ref.read(apiClientProvider).dio));
