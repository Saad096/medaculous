import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/providers/auth_providers.dart';
import '../../data/pharmacy_api.dart';

final pharmacyApiProvider = Provider<PharmacyApi>((ref) => PharmacyApi(ref.read(apiClientProvider).dio));
