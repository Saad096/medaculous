import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/providers/auth_providers.dart';
import '../../data/exam_planner_api.dart';

final examPlannerApiProvider = Provider<ExamPlannerApi>((ref) => ExamPlannerApi(ref.read(apiClientProvider).dio));
