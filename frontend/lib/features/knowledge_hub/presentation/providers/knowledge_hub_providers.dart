import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/providers/auth_providers.dart';
import '../../data/knowledge_hub_api.dart';

final knowledgeHubApiProvider = Provider<KnowledgeHubApi>(
  (ref) => KnowledgeHubApi(ref.read(apiClientProvider).dio),
);
